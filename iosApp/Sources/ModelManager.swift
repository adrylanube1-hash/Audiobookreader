import Foundation
import SWCompression

enum ModelError: LocalizedError {
    case invalidCatalogue, invalidURL, emptyDownload, unsafeArchive, incomplete(String)
    var errorDescription: String? {
        switch self {
        case .invalidCatalogue: return "The shared model catalogue is unavailable."
        case .invalidURL: return "The model download URL is invalid."
        case .emptyDownload: return "The model download was empty."
        case .unsafeArchive: return "The model archive contains an unsafe path."
        case .incomplete(let file): return "The model is incomplete. Missing \(file)."
        }
    }
}

enum ModelCatalogLoader {
    static func load() -> [TTSModel] {
        guard let url = Bundle.main.url(forResource: "model-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let models = try? JSONDecoder().decode([TTSModel].self, from: data) else { return [] }
        return models.filter { $0.family != .edge }
    }
}

final class ModelManager: @unchecked Sendable {
    private let root: URL
    private let audioRoot: URL
    private let fileManager = FileManager.default

    init() {
        root = Storage.support.appendingPathComponent("tts-models", isDirectory: true)
        audioRoot = Storage.cache.appendingPathComponent("audio", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        try? fileManager.createDirectory(at: audioRoot, withIntermediateDirectories: true, attributes: nil)
    }

    func rootDirectory(for model: TTSModel) -> URL { root.appendingPathComponent(model.storageId, isDirectory: true) }

    func directory(for model: TTSModel) -> URL {
        let root = rootDirectory(for: model)
        let marker = model.modelName.isEmpty ? model.requiredFiles.first : model.modelName
        guard let marker, !marker.isEmpty, let file = recursiveFile(named: marker, under: root) else { return root }
        return file.deletingLastPathComponent()
    }

    func isInstalled(_ model: TTSModel) -> Bool {
        if model.isOnline { return true }
        let directory = directory(for: model)
        let needed = [model.modelName, model.voices, model.auxiliaryName] + model.requiredFiles +
            model.lexicon.split(separator: ",").map(String.init) + model.ruleFsts.split(separator: ",").map(String.init)
        let needsTokens = [.piper, .coqui, .mimic3, .kokoro, .zipvoice].contains(model.family)
        let hasData = model.dataDir.isEmpty || recursiveFile(named: "phontab", under: directory) != nil
        return needed.filter { !$0.isEmpty }.allSatisfy { recursiveFile(named: $0, under: directory) != nil }
            && (!needsTokens || recursiveFile(named: "tokens.txt", under: directory) != nil) && hasData
    }

    func download(_ model: TTSModel, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let url = URL(string: model.archiveURL), url.scheme == "https" else { throw ModelError.invalidURL }
        let temporaryArchive = root.appendingPathComponent(".\(model.storageId).download")
        let installing = root.appendingPathComponent(".\(model.storageId).installing", isDirectory: true)
        try? fileManager.removeItem(at: temporaryArchive)
        try? fileManager.removeItem(at: installing)
        try fileManager.createDirectory(at: installing, withIntermediateDirectories: true, attributes: nil)
        do {
            let (bytes, response) = try await URLSession.shared.bytes(from: url)
            let total = max(response.expectedContentLength, 1)
            fileManager.createFile(atPath: temporaryArchive.path, contents: nil)
            let handle = try FileHandle(forWritingTo: temporaryArchive)
            var buffer = Data(); var received: Int64 = 0
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 128 * 1024 {
                    try handle.write(contentsOf: buffer); received += Int64(buffer.count); buffer.removeAll(keepingCapacity: true)
                    progress(min(0.60, Double(received) / Double(total) * 0.60))
                }
            }
            if !buffer.isEmpty { try handle.write(contentsOf: buffer); received += Int64(buffer.count) }
            try handle.close()
            guard received > 0 else { throw ModelError.emptyDownload }
            progress(0.62)
            let compressed = try Data(contentsOf: temporaryArchive, options: .mappedIfSafe)
            let tar = try BZip2.decompress(data: compressed)
            progress(0.78)
            let entries = try TarContainer.open(container: tar)
            let sharedRoot = commonArchiveRoot(entries.map { $0.info.name })
            for (index, entry) in entries.enumerated() {
                var name = entry.info.name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if let sharedRoot, name == sharedRoot { continue }
                if let sharedRoot, name.hasPrefix(sharedRoot + "/") { name.removeFirst(sharedRoot.count + 1) }
                guard !name.isEmpty else { continue }
                let destination = installing.appendingPathComponent(name).standardizedFileURL
                guard destination.path.hasPrefix(installing.standardizedFileURL.path + "/") else { throw ModelError.unsafeArchive }
                if let data = entry.data {
                    try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                    try data.write(to: destination, options: .atomic)
                } else { try fileManager.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil) }
                progress(0.78 + 0.17 * Double(index + 1) / Double(max(entries.count, 1)))
            }
            if !model.auxiliaryURL.isEmpty, let auxiliaryURL = URL(string: model.auxiliaryURL) {
                let (downloaded, _) = try await URLSession.shared.data(from: auxiliaryURL)
                try downloaded.write(to: installing.appendingPathComponent(model.auxiliaryName), options: .atomic)
            }
            try validate(model, in: installing)
            let destination = rootDirectory(for: model)
            let backup = root.appendingPathComponent(".\(model.storageId).backup")
            try? fileManager.removeItem(at: backup)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.moveItem(at: destination, to: backup) }
            try fileManager.moveItem(at: installing, to: destination)
            try? fileManager.removeItem(at: backup)
            try? fileManager.removeItem(at: temporaryArchive)
            progress(1)
        } catch {
            try? fileManager.removeItem(at: installing)
            try? fileManager.removeItem(at: temporaryArchive)
            throw error
        }
    }

    func delete(_ model: TTSModel) throws {
        let destination = rootDirectory(for: model).standardizedFileURL
        guard destination.deletingLastPathComponent() == root.standardizedFileURL else { throw ModelError.unsafeArchive }
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
    }

    func importOnnx(urls: [URL], language: String) async throws -> TTSModel {
        try await Task.detached(priority: .userInitiated) { [self] in
            let entries = urls.map { ($0.lastPathComponent, $0) }
            guard let modelEntry = entries.first(where: { $0.0.lowercased().hasSuffix(".onnx") }) else {
                throw ModelError.incomplete("model.onnx")
            }
            guard let tokensEntry = entries.first(where: { $0.0.lowercased() == "tokens.txt" }) else {
                throw ModelError.incomplete("tokens.txt")
            }
            let id = "local-\(UUID().uuidString.lowercased())"
            let destination = root.appendingPathComponent(id, isDirectory: true)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil)
            do {
                for (name, source) in entries {
                    let accessed = source.startAccessingSecurityScopedResource()
                    defer { if accessed { source.stopAccessingSecurityScopedResource() } }
                    let safeName = source == tokensEntry.1 ? "tokens.txt" : name.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
                    guard !safeName.isEmpty else { throw ModelError.unsafeArchive }
                    try fileManager.copyItem(at: source, to: destination.appendingPathComponent(safeName))
                }
            } catch { try? fileManager.removeItem(at: destination); throw error }
            let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let modelName = modelEntry.0.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
            let dataDirectory = entries.contains { $0.0.lowercased() == "espeak-ng-data" } ? "espeak-ng-data" : ""
            return TTSModel(id: id, name: "Local ONNX · \(modelEntry.0.replacingOccurrences(of: ".onnx", with: ""))",
                            family: .piper, language: normalized.isEmpty ? "all" : normalized,
                            archiveURL: "", modelName: modelName, voices: "", lexicon: "", ruleFsts: "", ruleFars: "",
                            dataDir: dataDirectory, storageId: id, auxiliaryURL: "", auxiliaryName: "", licenseSpdx: "User supplied",
                            licenseURL: "", attribution: "Imported by the user", requiresAcceptance: false,
                            referenceAudioRequired: false, referenceTextRequired: false, requiredFiles: [])
        }.value
    }

    func audioURL(bookId: UUID, chunk: Int, model: TTSModel, settings: BookVoiceSettings) -> URL {
        let directory = audioRoot.appendingPathComponent(bookId.uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let speed = Int((settings.speed * 100).rounded())
        let extensionName = model.isOnline ? "mp3" : "wav"
        return directory.appendingPathComponent("\(chunk)-\(model.id)-\(settings.speakerId)-\(speed).\(extensionName)")
    }

    func clearAudio(bookId: UUID) { try? fileManager.removeItem(at: audioRoot.appendingPathComponent(bookId.uuidString)) }
    func clearAllAudio() { try? fileManager.removeItem(at: audioRoot); try? fileManager.createDirectory(at: audioRoot, withIntermediateDirectories: true, attributes: nil) }

    private func validate(_ model: TTSModel, in directory: URL) throws {
        let tokenFiles = [.piper, .coqui, .mimic3, .kokoro, .zipvoice].contains(model.family) ? ["tokens.txt"] : []
        let required = [model.modelName, model.voices, model.auxiliaryName] + model.requiredFiles +
            model.lexicon.split(separator: ",").map(String.init) + model.ruleFsts.split(separator: ",").map(String.init) + tokenFiles
        for file in required where !file.isEmpty {
            guard recursiveFile(named: file, under: directory) != nil else { throw ModelError.incomplete(file) }
        }
    }

    private func recursiveFile(named name: String, under directory: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return nil }
        return enumerator.compactMap { $0 as? URL }.first { $0.lastPathComponent == name }
    }

    private func commonArchiveRoot(_ names: [String]) -> String? {
        let roots = Set(names.compactMap { $0.split(separator: "/").first.map(String.init) })
        return roots.count == 1 ? roots.first : nil
    }
}
