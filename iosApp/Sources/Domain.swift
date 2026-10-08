import Foundation

enum TTSFamily: String, Codable, CaseIterable {
    case piper, coqui, mimic3, kokoro, kitten, supertonic, zipvoice, edge

    var isOnline: Bool { self == .edge }
    var displayName: String {
        switch self {
        case .mimic3: return "Mimic 3"
        case .zipvoice: return "ZipVoice"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

struct TTSModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let family: TTSFamily
    let language: String
    let archiveURL: String
    let modelName: String
    let voices: String
    let lexicon: String
    let ruleFsts: String
    let ruleFars: String
    let dataDir: String
    let storageId: String
    let auxiliaryURL: String
    let auxiliaryName: String
    let licenseSpdx: String
    let licenseURL: String
    let attribution: String
    let requiresAcceptance: Bool
    let referenceAudioRequired: Bool
    let referenceTextRequired: Bool
    let requiredFiles: [String]
    var edgeVoice: String? = nil

    var isOnline: Bool { family.isOnline }
}

struct KokoroVoice: Identifiable, Hashable {
    let id: String
    let speaker: Int
    let language: String

    static let all: [KokoroVoice] = [
        ("af_alloy", "en"), ("af_aoede", "en"), ("af_bella", "en"), ("af_heart", "en"),
        ("af_jessica", "en"), ("af_kore", "en"), ("af_nicole", "en"), ("af_nova", "en"),
        ("af_river", "en"), ("af_sarah", "en"), ("af_sky", "en"), ("am_adam", "en"),
        ("am_echo", "en"), ("am_eric", "en"), ("am_fenrir", "en"), ("am_liam", "en"),
        ("am_michael", "en"), ("am_onyx", "en"), ("am_puck", "en"), ("am_santa", "en"),
        ("bf_alice", "en"), ("bf_emma", "en"), ("bf_isabella", "en"), ("bf_lily", "en"),
        ("bm_daniel", "en"), ("bm_fable", "en"), ("bm_george", "en"), ("bm_lewis", "en"),
        ("ef_dora", "es"), ("em_alex", "es"), ("ff_siwis", "fr"), ("hf_alpha", "hi"),
        ("hf_beta", "hi"), ("hm_omega", "hi"), ("hm_psi", "hi"), ("if_sara", "it"),
        ("im_nicola", "it"), ("jf_alpha", "ja"), ("jf_gongitsune", "ja"), ("jf_nezumi", "ja"),
        ("jf_tebukuro", "ja"), ("jm_kumo", "ja"), ("pf_dora", "pt"), ("pm_alex", "pt"),
        ("pm_santa", "pt"), ("zf_xiaobei", "zh"), ("zf_xiaoni", "zh"), ("zf_xiaoxiao", "zh"),
        ("zf_xiaoyi", "zh"), ("zm_yunjian", "zh"), ("zm_yunxi", "zh"), ("zm_yunxia", "zh"),
        ("zm_yunyang", "zh"), ("em_santa", "es")
    ].enumerated().map { KokoroVoice(id: $0.element.0, speaker: $0.offset, language: $0.element.1) }

    static func sherpaLanguage(for speaker: Int) -> String {
        guard let voice = all.first(where: { $0.speaker == speaker }) else { return "en-us" }
        if voice.language == "en" { return speaker >= 20 && speaker <= 27 ? "en-gb" : "en-us" }
        return ["fr": "fr-fr", "pt": "pt-br"].first(where: { $0.key == voice.language })?.value ?? voice.language
    }
}

struct BookChapter: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let text: String
}

struct ReadingBookmark: Codable, Identifiable, Hashable {
    let id: UUID
    let chunkIndex: Int
    let position: TimeInterval
    let createdAt: Date
}

struct BookVoiceSettings: Codable, Hashable {
    var modelId: String = ""
    var speed: Double = 1.0
    var speakerId: Int = 0
    var referenceAudioPath: String = ""
    var referenceText: String = ""
}

struct LibraryBook: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var fileName: String
    var chapters: [BookChapter]
    var language: String
    var coverFileName: String?
    var currentChunk: Int = 0
    var currentPosition: TimeInterval = 0
    var bookmarks: [ReadingBookmark] = []
    var voice: BookVoiceSettings = BookVoiceSettings()
    var lastOpened: Date = Date()
    var chunks: [String]

    init(id: UUID, title: String, fileName: String, chapters: [BookChapter], language: String,
         coverFileName: String? = nil, currentChunk: Int = 0, currentPosition: TimeInterval = 0,
         bookmarks: [ReadingBookmark] = [], voice: BookVoiceSettings = BookVoiceSettings(),
         lastOpened: Date = Date()) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.chapters = chapters
        self.language = language
        self.coverFileName = coverFileName
        self.currentChunk = currentChunk
        self.currentPosition = currentPosition
        self.bookmarks = bookmarks
        self.voice = voice
        self.lastOpened = lastOpened
        self.chunks = chapters.flatMap { TextChunker.split($0.text) }
    }
    var percentage: Int {
        let count = max(chunks.count, 1)
        return min(100, max(0, Int((Double(currentChunk) / Double(count)) * 100)))
    }
}

enum InterfaceLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    var id: String { rawValue }
    var label: String { self == .english ? "English" : "Español" }
}

enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

struct AppPreferences: Codable {
    var language: InterfaceLanguage = .english
    var theme: ThemeMode = .system
    var modelLanguage: String = "all"
    var edgeDisclosureAccepted = false
    var recentModels: [String] = []
}

enum TextChunker {
    private static let minimum = 180

    static func normalize(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var paragraphs: [String] = []
        var current = ""
        func cleaned(_ value: String) -> String {
            value.replacingOccurrences(of: "\u{00a0}", with: " ")
                .replacingOccurrences(of: "[\\t\\u{000c} ]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for raw in lines {
            let line = cleaned(raw)
            if line.isEmpty {
                if !current.isEmpty { paragraphs.append(current); current = "" }
            } else if current.isEmpty {
                current = line
            } else if current.hasSuffix("-") && line.first?.isLowercase == true {
                current.removeLast()
                current += line
            } else {
                current += " " + line
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs.joined(separator: "\n\n")
    }

    static func split(_ text: String, maxCharacters: Int = 700) -> [String] {
        let paragraphs = normalize(text).components(separatedBy: "\n\n").filter { !$0.isEmpty }
        var output: [String] = []
        var current = ""
        for paragraph in paragraphs {
            for piece in splitParagraph(paragraph, limit: maxCharacters) {
                let separator = current.isEmpty ? "" : "\n\n"
                if !current.isEmpty && current.count + separator.count + piece.count > maxCharacters {
                    output.append(current)
                    current = piece
                } else {
                    current += separator + piece
                }
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { output.append(current) }
        return output.isEmpty ? [" "] : output
    }

    private static func splitParagraph(_ paragraph: String, limit: Int) -> [String] {
        let expression = try! NSRegularExpression(pattern: "(?<=[.!?。！？…])\\s+")
        let range = NSRange(paragraph.startIndex..., in: paragraph)
        var sentences: [String] = []
        var start = paragraph.startIndex
        for match in expression.matches(in: paragraph, range: range) {
            guard let splitRange = Range(match.range, in: paragraph) else { continue }
            sentences.append(String(paragraph[start..<splitRange.lowerBound]).trimmingCharacters(in: .whitespaces))
            start = splitRange.upperBound
        }
        sentences.append(String(paragraph[start...]).trimmingCharacters(in: .whitespaces))
        var pieces: [String] = []
        var current = ""
        for sentence in sentences.filter({ !$0.isEmpty }) {
            let groups = sentence.count > limit ? balancedWords(sentence, limit: limit) : [sentence]
            for group in groups {
                if !current.isEmpty && current.count + group.count + 1 > limit {
                    pieces.append(current)
                    current = group
                } else { current += (current.isEmpty ? "" : " ") + group }
            }
        }
        if !current.isEmpty { pieces.append(current) }
        if pieces.count > 1, let tail = pieces.last, tail.count < minimum,
           pieces[pieces.count - 2].count + tail.count + 1 <= limit {
            pieces[pieces.count - 2] += " " + tail
            pieces.removeLast()
        }
        return pieces
    }

    private static func balancedWords(_ text: String, limit: Int) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var result: [String] = []
        var current = ""
        for word in words {
            if !current.isEmpty && current.count + word.count + 1 > limit {
                result.append(current)
                current = word
            } else { current += (current.isEmpty ? "" : " ") + word }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
