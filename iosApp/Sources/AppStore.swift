import Combine
import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var books: [LibraryBook] = [] { didSet { saveBooks() } }
    @Published var preferences = AppPreferences() { didSet { savePreferences() } }
    @Published var localModels: [TTSModel] = []
    @Published var edgeModels: [TTSModel] = []
    @Published var installedModelIds: Set<String> = []
    @Published var downloads: [String: Double] = [:]
    @Published var queuedDownloads: [String] = []
    @Published var message: String?
    @Published var selectedBookId: UUID?
    @Published var licenseModel: TTSModel?
    @Published var edgeConsentModel: TTSModel?

    let modelManager = ModelManager()
    let playback = PlaybackController()
    private let documents = DocumentImporter()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        books = Storage.load([LibraryBook].self, from: "library.json") ?? []
        preferences = Storage.load(AppPreferences.self, from: "preferences.json") ?? AppPreferences()
        localModels = ModelCatalogLoader.load() + (Storage.load([TTSModel].self, from: "imported-models.json") ?? [])
        installedModelIds = Set(localModels.filter(modelManager.isInstalled).map(\.id))
        playback.$snapshot
            .removeDuplicates()
            .throttle(for: .seconds(5), scheduler: RunLoop.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.consumePlayback(snapshot) }
            .store(in: &cancellables)
        Task { await refreshEdgeVoices() }
    }

    var allModels: [TTSModel] { localModels + edgeModels }
    var selectedBook: LibraryBook? { books.first(where: { $0.id == selectedBookId }) }
    var colorScheme: ColorScheme? {
        switch preferences.theme { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }

    func importDocument(_ url: URL) {
        Task {
            do {
                let book = try await documents.importDocument(url)
                books.removeAll { $0.id == book.id }
                books.insert(book, at: 0)
                selectedBookId = book.id
            } catch { message = error.localizedDescription }
        }
    }

    func deleteBook(_ id: UUID) {
        playback.stop()
        modelManager.clearAudio(bookId: id)
        books.removeAll { $0.id == id }
        if selectedBookId == id { selectedBookId = nil }
    }

    func updateBook(_ id: UUID, _ body: (inout LibraryBook) -> Void) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        body(&books[index])
    }

    func selectModel(_ model: TTSModel, for bookId: UUID) {
        if !model.isOnline && !installedModelIds.contains(model.id) {
            message = localized("Download this model first.", "Descarga primero este modelo.")
            return
        }
        if model.isOnline && !preferences.edgeDisclosureAccepted {
            edgeConsentModel = model
            return
        }
        applyModel(model, bookId: bookId)
    }

    private func applyModel(_ model: TTSModel, bookId: UUID) {
        updateBook(bookId) { book in
            book.voice.modelId = model.id
            if model.family == .kokoro {
                let language = book.language
                book.voice.speakerId = KokoroVoice.all.first(where: { $0.language == language })?.speaker ?? 0
            } else { book.voice.speakerId = 0 }
        }
        preferences.recentModels.removeAll { $0 == model.id }
        preferences.recentModels.insert(model.id, at: 0)
        preferences.recentModels = Array(preferences.recentModels.prefix(30))
    }

    func acceptEdge(for bookId: UUID) {
        guard let model = edgeConsentModel else { return }
        preferences.edgeDisclosureAccepted = true
        edgeConsentModel = nil
        applyModel(model, bookId: bookId)
    }

    func requestDownload(_ model: TTSModel) {
        if model.requiresAcceptance { licenseModel = model } else { enqueueDownload(model) }
    }

    func acceptLicense() {
        guard let model = licenseModel else { return }
        licenseModel = nil
        enqueueDownload(model)
    }

    private func enqueueDownload(_ model: TTSModel) {
        guard downloads[model.id] == nil, !queuedDownloads.contains(model.id) else { return }
        queuedDownloads.append(model.id)
        Task { await runDownloadQueue() }
    }

    private func runDownloadQueue() async {
        guard downloads.isEmpty, let id = queuedDownloads.first,
              let model = localModels.first(where: { $0.id == id }) else { return }
        queuedDownloads.removeFirst()
        downloads[id] = 0
        do {
            try await modelManager.download(model) { [weak self] progress in
                Task { @MainActor in self?.downloads[id] = progress }
            }
            installedModelIds = Set(localModels.filter(modelManager.isInstalled).map(\.id))
            message = localized("Model installed.", "Modelo instalado.")
        } catch { message = error.localizedDescription }
        downloads[id] = nil
        await runDownloadQueue()
    }

    func deleteModel(_ model: TTSModel) {
        do {
            try modelManager.delete(model)
            installedModelIds = Set(localModels.filter(modelManager.isInstalled).map(\.id))
            for index in books.indices where books[index].voice.modelId == model.id { books[index].voice.modelId = "" }
            if model.id.hasPrefix("local-") {
                localModels.removeAll { $0.id == model.id }
                Storage.save(localModels.filter { $0.id.hasPrefix("local-") }, to: "imported-models.json")
            }
        } catch { message = error.localizedDescription }
    }

    func importOnnx(_ urls: [URL], language: String) {
        Task {
            do {
                let model = try await modelManager.importOnnx(urls: urls, language: language)
                localModels.append(model)
                installedModelIds.insert(model.id)
                Storage.save(localModels.filter { $0.id.hasPrefix("local-") }, to: "imported-models.json")
                message = localized("ONNX model imported.", "Modelo ONNX importado.")
            } catch { message = error.localizedDescription }
        }
    }

    func play(_ bookId: UUID, from requestedChunk: Int? = nil) {
        guard let book = books.first(where: { $0.id == bookId }),
              let model = allModels.first(where: { $0.id == book.voice.modelId }) else {
            message = localized("Select an installed or online voice first.", "Selecciona primero una voz instalada u online.")
            return
        }
        let start = min(max(requestedChunk ?? book.currentChunk, 0), max(book.chunks.count - 1, 0))
        updateBook(bookId) { if requestedChunk != nil { $0.currentChunk = start; $0.currentPosition = 0 } }
        playback.start(book: book, model: model, at: start, modelManager: modelManager) { [weak self] text, model, settings, output in
            guard let self else { throw CancellationError() }
            if model.isOnline {
                try await EdgeTTSClient.shared.synthesize(text: text, model: model, speed: settings.speed, output: output)
            } else {
                try await LocalTTSEngine.shared.synthesize(text: text, model: model, settings: settings,
                                                           modelDirectory: self.modelManager.directory(for: model), output: output)
            }
        }
    }

    func seek(bookId: UUID, chunk: Int) {
        updateBook(bookId) { $0.currentChunk = chunk; $0.currentPosition = 0 }
        play(bookId, from: chunk)
    }

    func reset(_ bookId: UUID) {
        playback.stop()
        updateBook(bookId) { $0.currentChunk = 0; $0.currentPosition = 0 }
    }

    func addBookmark(_ bookId: UUID) {
        updateBook(bookId) { book in
            book.bookmarks.append(ReadingBookmark(id: UUID(), chunkIndex: book.currentChunk,
                                                  position: book.currentPosition, createdAt: Date()))
        }
    }

    func clearAudio(_ bookId: UUID) { playback.stop(); modelManager.clearAudio(bookId: bookId) }
    func clearAllAudio() { playback.stop(); modelManager.clearAllAudio() }

    func refreshEdgeVoices() async {
        do { edgeModels = try await EdgeTTSClient.shared.fetchVoices() }
        catch { edgeModels = await EdgeTTSClient.shared.cachedVoices() }
    }

    private func consumePlayback(_ snapshot: PlaybackSnapshot) {
        if let error = snapshot.errorMessage { message = error }
        guard let bookId = snapshot.bookId else { return }
        updateBook(bookId) { book in
            book.currentChunk = snapshot.chunkIndex
            book.currentPosition = snapshot.position
        }
    }

    func localized(_ english: String, _ spanish: String) -> String {
        preferences.language == .spanish ? spanish : english
    }

    private func saveBooks() { Storage.save(books, to: "library.json") }
    private func savePreferences() { Storage.save(preferences, to: "preferences.json") }
}

enum Storage {
    static let support: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audiobookreader", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }()

    static let cache: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audiobookreader", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }()

    static func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let data = try? Data(contentsOf: support.appendingPathComponent(file)) else { return nil }
        return try? JSONDecoder.app.decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to file: String) {
        guard let data = try? JSONEncoder.app.encode(value) else { return }
        let destination = support.appendingPathComponent(file)
        let temporary = support.appendingPathComponent(".\(file).tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else { try FileManager.default.moveItem(at: temporary, to: destination) }
        } catch { try? FileManager.default.removeItem(at: temporary) }
    }
}

private extension JSONEncoder {
    static var app: JSONEncoder { let coder = JSONEncoder(); coder.dateEncodingStrategy = .iso8601; return coder }
}
private extension JSONDecoder {
    static var app: JSONDecoder { let coder = JSONDecoder(); coder.dateDecodingStrategy = .iso8601; return coder }
}
