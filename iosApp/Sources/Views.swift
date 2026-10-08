import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        TabView {
            LibraryView(store: store)
                .tabItem { Label(t("Library", "Biblioteca"), systemImage: "books.vertical.fill") }
            ModelsView(store: store)
                .tabItem { Label(t("Models", "Modelos"), systemImage: "waveform.circle.fill") }
            SettingsView(store: store)
                .tabItem { Label(t("Settings", "Ajustes"), systemImage: "gearshape.fill") }
        }
        .tint(.indigo)
        .sheet(item: $store.licenseModel) { model in LicenseSheet(store: store, model: model) }
        .alert(t("Online speech disclosure", "Aviso de voz online"), isPresented: Binding(
            get: { store.edgeConsentModel != nil }, set: { if !$0 { store.edgeConsentModel = nil } })) {
                Button(t("Decline", "Rechazar"), role: .cancel) { store.edgeConsentModel = nil }
                if let id = store.selectedBookId { Button(t("Accept and use", "Aceptar y usar")) { store.acceptEdge(for: id) } }
            } message: {
                Text(t("Only the text fragments being spoken and their voice settings are sent directly to Microsoft over an encrypted connection. Documents, bookmarks and local audio are not uploaded.",
                       "Solo los fragmentos que se van a leer y sus ajustes de voz se envían directamente a Microsoft mediante una conexión cifrada. Los documentos, marcadores y audios locales no se suben."))
            }
        .alert(t("audiobookreader", "audiobookreader"), isPresented: Binding(
            get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
                Button("OK") { store.message = nil }
            } message: { Text(store.message ?? "") }
    }

    private func t(_ en: String, _ es: String) -> String { store.localized(en, es) }
}

struct LibraryView: View {
    @ObservedObject var store: AppStore
    @State private var importing = false

    var body: some View {
        NavigationView {
            ZStack {
                ShelfBackground()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 14)], spacing: 22) {
                        ForEach(store.books.sorted { $0.lastOpened > $1.lastOpened }) { book in
                            NavigationLink(destination: ReaderView(store: store, bookId: book.id)) {
                                BookCover(book: book)
                            }.buttonStyle(.plain)
                        }
                    }.padding()
                }
            }
            .navigationTitle(t("Library", "Biblioteca"))
            .toolbar { Button { importing = true } label: { Label(t("Add book", "Añadir libro"), systemImage: "plus") } }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.pdf, .plainText, .html, UTType(filenameExtension: "epub")!]) { result in
                if case .success(let url) = result { store.importDocument(url) }
                else if case .failure(let error) = result { store.message = error.localizedDescription }
            }
            .overlay {
                if store.books.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "books.vertical").font(.system(size: 54)).foregroundStyle(.secondary)
                        Text(t("Add a PDF, EPUB or text document to begin.", "Añade un PDF, EPUB o documento de texto para empezar."))
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button(t("Add book", "Añadir libro")) { importing = true }.buttonStyle(.borderedProminent)
                    }.padding(32).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                }
            }
        }.navigationViewStyle(.stack)
    }

    private func t(_ en: String, _ es: String) -> String { store.localized(en, es) }
}

private struct ShelfBackground: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.indigo.opacity(0.08).ignoresSafeArea()
                ForEach(0..<12, id: \.self) { row in
                    Rectangle().fill(Color.brown.opacity(0.24)).frame(height: 9)
                        .offset(y: CGFloat(row) * 150 - geometry.size.height / 2 + 130)
                }
            }
        }
    }
}

private struct BookCover: View {
    let book: LibraryBook
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let file = book.coverFileName,
                   let image = UIImage(contentsOfFile: Storage.support.appendingPathComponent("books/\(file)").path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "book.closed.fill").font(.system(size: 42)).foregroundStyle(.white.opacity(0.9))
                    }
                }
            }.frame(height: 205).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.28), radius: 5, y: 4)
            Text(book.title).font(.headline).lineLimit(2).foregroundStyle(.primary)
            ProgressView(value: Double(book.percentage), total: 100).tint(.indigo)
            Text("\(book.percentage)%").font(.caption).foregroundStyle(.secondary)
        }.padding(8).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ReaderView: View {
    @ObservedObject var store: AppStore
    @ObservedObject private var playback: PlaybackController
    let bookId: UUID
    @State private var selectedChunk: Int?
    @State private var voiceExpanded = false
    @State private var modelLanguage = "all"
    @State private var referenceImporter = false

    init(store: AppStore, bookId: UUID) {
        self.store = store; self.bookId = bookId; _playback = ObservedObject(wrappedValue: store.playback)
    }

    var body: some View {
        Group {
            if let book = store.books.first(where: { $0.id == bookId }) {
                ScrollViewReader { proxy in
                    ZStack(alignment: .topLeading) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                Color.clear.frame(height: 1).id("top")
                                header(book)
                                ForEach(Array(book.chunks.enumerated()), id: \.offset) { index, chunk in
                                    Text(chunk)
                                        .font(.system(size: 19, weight: index == playback.snapshot.chunkIndex ? .semibold : .regular,
                                                      design: .serif)).lineSpacing(7)
                                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(index == playback.snapshot.chunkIndex ? Color.indigo.opacity(0.19) :
                                                        selectedChunk == index ? Color.orange.opacity(0.13) : Color.clear,
                                                    in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(alignment: .leading) {
                                            if index == playback.snapshot.chunkIndex { Rectangle().fill(Color.indigo).frame(width: 4).clipShape(Capsule()) }
                                        }
                                        .contentShape(Rectangle()).onTapGesture { selectedChunk = index }
                                        .id(index)
                                }
                            }.padding(.horizontal).padding(.bottom, 80)
                        }
                        Button { withAnimation { proxy.scrollTo("top", anchor: .top) } } label: {
                            Image(systemName: "arrow.up.to.line.compact").font(.title3).padding(12)
                        }.buttonStyle(.borderedProminent).clipShape(Circle()).padding(12).shadow(radius: 4)
                    }
                    .onChange(of: playback.snapshot.chunkIndex) { newValue in
                        guard selectedChunk == nil else { return }
                        withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                    }
                }
                .navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
                .onAppear { store.selectedBookId = bookId; modelLanguage = book.language }
                .onChange(of: modelLanguage) { value in if value != "all" { store.updateBook(bookId) { $0.language = value } } }
                .fileImporter(isPresented: $referenceImporter, allowedContentTypes: [.audio]) { result in
                    guard case .success(let url) = result else { return }
                    let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let directory = Storage.support.appendingPathComponent("reference-audio", isDirectory: true)
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
                    let target = directory.appendingPathComponent("\(bookId.uuidString)-\(url.lastPathComponent)")
                    try? FileManager.default.removeItem(at: target); try? FileManager.default.copyItem(at: url, to: target)
                    store.updateBook(bookId) { $0.voice.referenceAudioPath = target.path }
                }
            } else { Text("Book not found") }
        }
    }

    @ViewBuilder private func header(_ book: LibraryBook) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(book.percentage)%").font(.title.bold())
                    Text(t("Listening progress", "Progreso de escucha")).foregroundStyle(.secondary)
                }
                Spacer()
                if playback.snapshot.isGenerating { ProgressView().controlSize(.large) }
            }
            ProgressView(value: Double(book.percentage), total: 100).tint(.indigo)
            controlButtons(book)
            DisclosureGroup(isExpanded: $voiceExpanded) {
                VoiceSettingsView(store: store, bookId: bookId, language: $modelLanguage,
                                  selectReference: { referenceImporter = true })
                    .padding(.top, 10)
            } label: { Label(t("Voice settings", "Ajustes de voz"), systemImage: "gearshape.2.fill").font(.headline) }
            if let selectedChunk {
                HStack {
                    Label(t("Start selected at fragment \(selectedChunk + 1)", "Iniciar en el fragmento \(selectedChunk + 1)"), systemImage: "text.cursor")
                    Spacer(); Button(t("Clear", "Quitar")) { self.selectedChunk = nil }.font(.caption)
                }.padding(10).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            if !book.bookmarks.isEmpty {
                Menu {
                    ForEach(book.bookmarks.sorted { $0.createdAt > $1.createdAt }) { marker in
                        Button("\(t("Fragment", "Fragmento")) \(marker.chunkIndex + 1)") { selectedChunk = marker.chunkIndex }
                    }
                } label: { Label("\(t("Bookmarks", "Marcadores")) (\(book.bookmarks.count))", systemImage: "bookmark.fill") }
            }
        }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)).id("controls")
    }

    private func controlButtons(_ book: LibraryBook) -> some View {
        VStack(spacing: 10) {
            HStack {
                Button { store.playback.previousChunk() } label: { Label(t("Previous", "Anterior"), systemImage: "backward.end.fill") }
                Button {
                    if playback.snapshot.bookId == bookId && playback.snapshot.isPlaying { store.playback.pause() }
                    else if playback.snapshot.bookId == bookId { store.playback.toggle() }
                    else { store.play(bookId, from: selectedChunk) }
                } label: { Label(playback.snapshot.isPlaying ? t("Pause", "Pausar") : t("Play", "Reproducir"),
                                 systemImage: playback.snapshot.isPlaying ? "pause.fill" : "play.fill") }
                    .buttonStyle(.borderedProminent)
                Button { store.playback.nextChunk() } label: { Label(t("Next", "Siguiente"), systemImage: "forward.end.fill") }
            }.labelStyle(.iconOnly).font(.title3)
            HStack {
                Button { store.playback.stop() } label: { Label(t("Stop", "Detener"), systemImage: "stop.fill") }
                Button { store.addBookmark(bookId) } label: { Label(t("Bookmark", "Marcador"), systemImage: "bookmark") }
                Menu {
                    Button(t("Reset reading position", "Reiniciar posición"), role: .destructive) { store.reset(bookId) }
                    Button(t("Clear generated audio", "Borrar audio generado"), role: .destructive) { store.clearAudio(bookId) }
                    Button(t("Delete book", "Eliminar libro"), role: .destructive) { store.deleteBook(bookId) }
                } label: { Label(t("More", "Más"), systemImage: "ellipsis.circle") }
            }.buttonStyle(.bordered).font(.caption)
        }.frame(maxWidth: .infinity)
    }

    private func t(_ en: String, _ es: String) -> String { store.localized(en, es) }
}

private struct VoiceSettingsView: View {
    @ObservedObject var store: AppStore
    let bookId: UUID
    @Binding var language: String
    let selectReference: () -> Void
    @State private var speedText = "1.00"

    private var book: LibraryBook? { store.books.first { $0.id == bookId } }
    private var selected: TTSModel? { book.flatMap { value in store.allModels.first { $0.id == value.voice.modelId } } }
    private var choices: [TTSModel] {
        let recent = store.preferences.recentModels
        return store.allModels.filter { model in
            (model.isOnline || store.installedModelIds.contains(model.id)) &&
            (language == "all" || model.language == language || model.language == "all")
        }.sorted {
            if $0.isOnline != $1.isOnline { return !$0.isOnline }
            return (recent.firstIndex(of: $0.id) ?? Int.max) < (recent.firstIndex(of: $1.id) ?? Int.max)
        }
    }

    var body: some View {
        if let book {
            VStack(alignment: .leading, spacing: 13) {
                Picker(t("Language", "Idioma"), selection: $language) {
                    Text(t("All languages", "Todos los idiomas")).tag("all")
                    ForEach(Set(store.allModels.map(\.language).filter { $0 != "all" }).sorted(), id: \.self) { Text($0.uppercased()).tag($0) }
                }.pickerStyle(.menu)
                Menu {
                    Section(t("Downloaded local voices", "Voces locales descargadas")) {
                        ForEach(choices.filter { !$0.isOnline }) { model in modelButton(model, current: book.voice.modelId) }
                    }
                    Section(t("Online voices", "Voces online")) {
                        ForEach(choices.filter { $0.isOnline }) { model in modelButton(model, current: book.voice.modelId) }
                    }
                } label: {
                    HStack { Image(systemName: selected?.isOnline == true ? "cloud.fill" : "iphone"); Text(selected?.name ?? t("Select voice", "Seleccionar voz")).lineLimit(2); Spacer(); Image(systemName: "chevron.up.chevron.down") }
                        .padding(12).background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                HStack {
                    Text(t("Speed", "Velocidad")); Slider(value: Binding(get: { book.voice.speed }, set: { value in
                        store.updateBook(bookId) { $0.voice.speed = value }; speedText = String(format: "%.2f", value)
                    }), in: 0.5...2.5, step: 0.05)
                    TextField("1.00", text: $speedText).keyboardType(.decimalPad).frame(width: 58).textFieldStyle(.roundedBorder)
                        .onSubmit { if let value = Double(speedText.replacingOccurrences(of: ",", with: ".")) { store.updateBook(bookId) { $0.voice.speed = min(max(value, 0.5), 2.5) } } }
                }.onAppear { speedText = String(format: "%.2f", book.voice.speed) }
                if selected?.family == .kokoro {
                    Picker(t("Kokoro voice", "Voz Kokoro"), selection: Binding(get: { book.voice.speakerId }, set: { id in store.updateBook(bookId) { $0.voice.speakerId = id } })) {
                        ForEach(KokoroVoice.all.filter { language == "all" || $0.language == language }) { voice in Text("\(voice.id) · \(voice.language.uppercased())").tag(voice.speaker) }
                    }.pickerStyle(.menu)
                } else if selected?.family == .supertonic {
                    Picker(t("Supertonic voice", "Voz Supertonic"), selection: Binding(get: { book.voice.speakerId }, set: { id in store.updateBook(bookId) { $0.voice.speakerId = id } })) {
                        ForEach(0..<10, id: \.self) { id in Text(id < 5 ? "Male \(id + 1)" : "Female \(id - 4)").tag(id) }
                    }.pickerStyle(.menu)
                }
                if selected?.referenceAudioRequired == true {
                    HStack {
                        Button(action: selectReference) { Label(book.voice.referenceAudioPath.isEmpty ? t("Choose reference audio", "Elegir audio de referencia") : t("Change reference audio", "Cambiar audio de referencia"), systemImage: "waveform.badge.plus") }
                        if !book.voice.referenceAudioPath.isEmpty {
                            Button(role: .destructive) { store.updateBook(bookId) { $0.voice.referenceAudioPath = "" } } label: { Image(systemName: "trash") }
                        }
                    }
                }
                if selected?.referenceTextRequired == true {
                    TextField(t("Exact reference transcript", "Transcripción exacta de referencia"), text: Binding(get: { book.voice.referenceText }, set: { value in store.updateBook(bookId) { $0.voice.referenceText = value } })).textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    @ViewBuilder private func modelButton(_ model: TTSModel, current: String) -> some View {
        Button { store.selectModel(model, for: bookId) } label: {
            Label(model.name, systemImage: current == model.id ? "checkmark.circle.fill" : model.isOnline ? "cloud" : "iphone")
        }
    }
    private func t(_ en: String, _ es: String) -> String { store.localized(en, es) }
}

struct ModelsView: View {
    @ObservedObject var store: AppStore
    @State private var search = ""
    private var filtered: [TTSModel] {
        store.allModels.filter { model in
            (store.preferences.modelLanguage == "all" || model.language == store.preferences.modelLanguage || model.language == "all") &&
            (search.isEmpty || model.name.localizedCaseInsensitiveContains(search) || model.family.rawValue.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        NavigationView {
            List {
                Picker(t("Language", "Idioma"), selection: $store.preferences.modelLanguage) {
                    Text(t("All languages", "Todos los idiomas")).tag("all")
                    ForEach(Set(store.allModels.map(\.language).filter { $0 != "all" }).sorted(), id: \.self) { Text($0.uppercased()).tag($0) }
                }
                Section(t("Local · download once", "Local · una sola descarga")) {
                    ForEach(filtered.filter { !$0.isOnline }) { model in ModelRow(store: store, model: model) }
                }
                Section(t("Online · no download", "Online · sin descarga")) {
                    ForEach(filtered.filter { $0.isOnline }) { model in ModelRow(store: store, model: model) }
                }
            }.searchable(text: $search, prompt: t("Voice, engine or language", "Voz, motor o idioma"))
                .navigationTitle(t("Models", "Modelos"))
                .refreshable { await store.refreshEdgeVoices() }
        }.navigationViewStyle(.stack)
    }
    private func t(_ en: String, _ es: String) -> String { store.localized(en, es) }
}

private struct ModelRow: View {
    @ObservedObject var store: AppStore
    let model: TTSModel
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(model.name).font(.headline)
            HStack { Text(model.family.displayName); Text("·"); Text(model.language.uppercased()); if !model.licenseSpdx.isEmpty { Text("· \(model.licenseSpdx)") } }
                .font(.caption).foregroundStyle(.secondary)
            if let progress = store.downloads[model.id] { ProgressView(value: progress); Text("\(Int(progress * 100))%").font(.caption) }
            else if model.isOnline { Label("ONLINE", systemImage: "cloud.fill").font(.caption.bold()).foregroundStyle(.green) }
            else if store.installedModelIds.contains(model.id) {
                Button(role: .destructive) { store.deleteModel(model) } label: { Label(store.localized("Delete model", "Eliminar modelo"), systemImage: "trash") }.buttonStyle(.bordered)
            } else {
                Button { store.requestDownload(model) } label: { Label(store.localized("Download", "Descargar"), systemImage: "arrow.down.circle.fill") }.buttonStyle(.borderedProminent)
            }
            if store.queuedDownloads.contains(model.id) { Label(store.localized("Queued", "En cola"), systemImage: "list.number").font(.caption).foregroundStyle(.orange) }
        }.padding(.vertical, 5)
    }
}

private struct LicenseSheet: View {
    @ObservedObject var store: AppStore
    let model: TTSModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.name).font(.title2.bold())
                    Text(model.licenseSpdx).font(.headline)
                    Text(model.attribution)
                    if let url = URL(string: model.licenseURL) { Link(store.localized("Read full license", "Leer licencia completa"), destination: url) }
                    Text(store.localized("By accepting, you confirm that you have reviewed the model license and will use it under those terms.", "Al aceptar, confirmas que has revisado la licencia del modelo y lo usarás bajo esas condiciones."))
                }.padding()
            }.navigationTitle(store.localized("Model license", "Licencia del modelo"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(store.localized("Decline", "Rechazar")) { store.licenseModel = nil; dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(store.localized("Accept", "Aceptar")) { store.acceptLicense(); dismiss() } }
                }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @State private var importingOnnx = false
    @State private var importLanguage = "eng"
    var body: some View {
        NavigationView {
            Form {
                Section(t("Interface", "Interfaz")) {
                    Picker(t("Language", "Idioma"), selection: $store.preferences.language) { ForEach(InterfaceLanguage.allCases) { Text($0.label).tag($0) } }
                    Picker(t("Appearance", "Apariencia"), selection: $store.preferences.theme) {
                        Text(t("System", "Sistema")).tag(ThemeMode.system); Text(t("Light", "Claro")).tag(ThemeMode.light); Text(t("Dark", "Oscuro")).tag(ThemeMode.dark)
                    }.pickerStyle(.segmented)
                }
                Section(t("Storage", "Almacenamiento")) {
                    Button(role: .destructive) { store.clearAllAudio() } label: { Label(t("Clear generated audio cache", "Borrar caché de audio generado"), systemImage: "trash") }
                }
                Section(t("Custom local model", "Modelo local personalizado")) {
                    TextField(t("ISO language code (eng, spa…)", "Código ISO de idioma (eng, spa…)"), text: $importLanguage)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button { importingOnnx = true } label: { Label(t("Import ONNX and tokens.txt", "Importar ONNX y tokens.txt"), systemImage: "square.and.arrow.down") }
                    Text(t("Select the Piper/VITS .onnx file, tokens.txt and any optional JSON, lexicon or espeak-ng-data folder required by that model.",
                           "Selecciona el archivo Piper/VITS .onnx, tokens.txt y cualquier JSON, léxico o carpeta espeak-ng-data opcional que necesite el modelo."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(t("Online speech", "Voz online")) {
                    Toggle(t("Allow Edge TTS", "Permitir Edge TTS"), isOn: $store.preferences.edgeDisclosureAccepted)
                    Text(t("When enabled, only fragments selected for speech are sent to Microsoft.", "Al activarlo, solo los fragmentos seleccionados para leer se envían a Microsoft.")).font(.caption)
                }
                Section(t("Playback", "Reproducción")) {
                    Text(t("Progress is saved automatically. Background audio and lock-screen controls remain available while audio is playing.",
                           "El progreso se guarda automáticamente. El audio en segundo plano y los controles de bloqueo siguen disponibles mientras se reproduce."))
                }
                Section(t("Credits and licenses", "Créditos y licencias")) {
                    Link("sherpa-onnx · Apache-2.0", destination: URL(string: "https://github.com/k2-fsa/sherpa-onnx")!)
                    Link("Piper voices", destination: URL(string: "https://huggingface.co/rhasspy/piper-voices")!)
                    Link("Kokoro-82M", destination: URL(string: "https://huggingface.co/hexgrad/Kokoro-82M")!)
                    Link("Supertonic", destination: URL(string: "https://huggingface.co/Supertone/supertonic-3")!)
                    Text(t("PocketTTS is intentionally not included in the iOS version.", "PocketTTS no está incluido intencionadamente en la versión iOS.")).font(.caption)
                }
            }.navigationTitle(t("Settings", "Ajustes"))
                .fileImporter(isPresented: $importingOnnx, allowedContentTypes: [.data, .plainText, .json, .folder], allowsMultipleSelection: true) { result in
                    switch result {
                    case .success(let urls): store.importOnnx(urls, language: importLanguage)
                    case .failure(let error): store.message = error.localizedDescription
                    }
                }
        }.navigationViewStyle(.stack)
    }
    private func t(_ en: String, _ es: String) -> String { store.localized(en, es) }
}
