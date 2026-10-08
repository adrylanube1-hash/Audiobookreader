import AVFoundation
import CryptoKit
import Foundation
import SherpaOnnx

enum TTSError: LocalizedError {
    case unsupported, invalidModel(String), generationFailed, invalidOnlineResponse
    var errorDescription: String? {
        switch self {
        case .unsupported: return "This TTS engine is not available on iOS."
        case .invalidModel(let file): return "The model file is missing: \(file)"
        case .generationFailed: return "Speech generation failed."
        case .invalidOnlineResponse: return "The online voice returned no playable audio."
        }
    }
}

actor LocalTTSEngine {
    static let shared = LocalTTSEngine()

    func synthesize(text: String, model: TTSModel, settings: BookVoiceSettings,
                    modelDirectory: URL, output: URL) async throws {
        guard model.family != .edge else { throw TTSError.unsupported }
        let fileManager = FileManager.default
        func find(_ name: String) throws -> String {
            guard !name.isEmpty else { return "" }
            if let enumerator = fileManager.enumerator(at: modelDirectory, includingPropertiesForKeys: [.isRegularFileKey]),
               let found = enumerator.compactMap({ $0 as? URL }).first(where: { $0.lastPathComponent == name }) {
                return found.path
            }
            throw TTSError.invalidModel(name)
        }
        func findList(_ names: String) throws -> String {
            try names.split(separator: ",").map { try find(String($0)) }.joined(separator: ",")
        }

        let modelConfig: SherpaOnnxOfflineTtsModelConfig
        switch model.family {
        case .kokoro:
            modelConfig = sherpaOnnxOfflineTtsModelConfig(
                kokoro: sherpaOnnxOfflineTtsKokoroModelConfig(
                    model: try find(model.modelName), voices: try find(model.voices), tokens: try find("tokens.txt"),
                    dataDir: try findDirectory(model.dataDir, beneath: modelDirectory), lengthScale: 1,
                    lexicon: try findList(model.lexicon), lang: KokoroVoice.sherpaLanguage(for: settings.speakerId)),
                numThreads: processThreads)
        case .supertonic:
            modelConfig = sherpaOnnxOfflineTtsModelConfig(
                numThreads: processThreads,
                supertonic: sherpaOnnxOfflineTtsSupertonicModelConfig(
                    durationPredictor: try find("duration_predictor.int8.onnx"),
                    textEncoder: try find("text_encoder.int8.onnx"),
                    vectorEstimator: try find("vector_estimator.int8.onnx"),
                    vocoder: try find("vocoder.int8.onnx"), ttsJson: try find("tts.json"),
                    unicodeIndexer: try find("unicode_indexer.bin"), voiceStyle: try find("voice.bin")))
        case .zipvoice:
            modelConfig = sherpaOnnxOfflineTtsModelConfig(
                numThreads: processThreads,
                zipvoice: sherpaOnnxOfflineTtsZipvoiceModelConfig(
                    tokens: try find("tokens.txt"), encoder: try find("encoder.int8.onnx"),
                    decoder: try find("decoder.int8.onnx"), vocoder: try find(model.auxiliaryName),
                    dataDir: try findDirectory(model.dataDir, beneath: modelDirectory), lexicon: try find(model.lexicon)))
        case .piper, .coqui, .mimic3, .kitten:
            modelConfig = sherpaOnnxOfflineTtsModelConfig(
                vits: sherpaOnnxOfflineTtsVitsModelConfig(
                    model: try find(model.modelName), lexicon: try findList(model.lexicon), tokens: try find("tokens.txt"),
                    dataDir: try findDirectory(model.dataDir, beneath: modelDirectory), noiseScale: 0.667,
                    noiseScaleW: 0.8, lengthScale: 1), numThreads: processThreads)
        case .edge: throw TTSError.unsupported
        }
        var configuration = sherpaOnnxOfflineTtsConfig(model: modelConfig,
                                                       ruleFsts: try findList(model.ruleFsts),
                                                       ruleFars: try findList(model.ruleFars), maxNumSentences: 1,
                                                       silenceScale: 0.2)
        let tts = withUnsafePointer(to: &configuration) { SherpaOnnxOfflineTtsWrapper(config: $0) }
        let reference = try loadReferenceAudio(path: settings.referenceAudioPath)
        var extra: [String: Any] = [:]
        if model.family == .supertonic { extra["lang"] = model.language }
        if model.family == .zipvoice { extra["min_char_in_sentence"] = "10" }
        let generated = tts.generateWithConfig(
            text: SpeechText.prepare(text),
            config: SherpaOnnxGenerationConfigSwift(speed: Float(settings.speed), sid: settings.speakerId,
                                                     referenceAudio: reference.samples, referenceSampleRate: reference.sampleRate,
                                                     referenceText: settings.referenceText,
                                                     numSteps: model.family == .zipvoice ? 4 : 8, extra: extra),
            callback: nil, arg: nil)
        guard generated.n > 0, generated.save(filename: output.path) != 0 else { throw TTSError.generationFailed }
    }

    private var processThreads: Int { min(max(ProcessInfo.processInfo.activeProcessorCount - 1, 2), 4) }

    private func loadReferenceAudio(path: String) throws -> (samples: [Float], sampleRate: Int) {
        guard !path.isEmpty else { return ([], 16_000) }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let count = min(file.length, AVAudioFramePosition(file.processingFormat.sampleRate * 30))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)) else {
            throw TTSError.generationFailed
        }
        try file.read(into: buffer, frameCount: AVAudioFrameCount(count))
        guard let firstChannel = buffer.floatChannelData?.pointee else { throw TTSError.generationFailed }
        return (Array(UnsafeBufferPointer(start: firstChannel, count: Int(buffer.frameLength))), Int(file.processingFormat.sampleRate))
    }

    private func findDirectory(_ name: String, beneath root: URL) throws -> String {
        guard !name.isEmpty else { return "" }
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]),
           let found = enumerator.compactMap({ $0 as? URL }).first(where: { $0.lastPathComponent == name }) {
            return found.path
        }
        throw TTSError.invalidModel(name)
    }
}

enum SpeechText {
    static func prepare(_ text: String) -> String {
        text.replacingOccurrences(of: "...", with: "…")
            .replacingOccurrences(of: "\\s*[—–]\\s*", with: ", ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

actor EdgeTTSClient {
    static let shared = EdgeTTSClient()
    private let cacheURL = Storage.support.appendingPathComponent("edge-voices.json")
    private let trustedToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private let gecVersion = "1-143.0.3650.75"
    private let origin = "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold"
    private let userAgent = "Mozilla/5.0 AppleWebKit/537.36 Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0"

    func fetchVoices() async throws -> [TTSModel] {
        let endpoint = "https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/voices/list"
        guard let url = URL(string: "\(endpoint)?trustedclienttoken=\(trustedToken)&Sec-MS-GEC=\(secMsGec())&Sec-MS-GEC-Version=\(gecVersion)") else {
            throw ModelError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard ((response as? HTTPURLResponse)?.statusCode ?? 500) < 300 else { throw TTSError.invalidOnlineResponse }
        let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        let models = raw.compactMap { item -> TTSModel? in
            guard let shortName = item["ShortName"] as? String,
                  let locale = item["Locale"] as? String else { return nil }
            let friendly = item["FriendlyName"] as? String ?? shortName
            let gender = item["Gender"] as? String ?? ""
            let language = locale.split(separator: "-").first.map(String.init)?.lowercased() ?? "all"
            return TTSModel(id: "edge-" + shortName.lowercased(), name: "Edge · \(friendly) · \(gender)", family: .edge,
                            language: language, archiveURL: "", modelName: "", voices: "", lexicon: "", ruleFsts: "",
                            ruleFars: "", dataDir: "", storageId: "edge-" + shortName.lowercased(), auxiliaryURL: "",
                            auxiliaryName: "", licenseSpdx: "Online service", licenseURL: "https://www.microsoft.com/servicesagreement",
                            attribution: "Microsoft Edge Read Aloud", requiresAcceptance: false,
                            referenceAudioRequired: false, referenceTextRequired: false, requiredFiles: [], edgeVoice: shortName)
        }.uniqued(by: \TTSModel.id)
        try? JSONEncoder().encode(models).write(to: cacheURL, options: .atomic)
        return models
    }

    func cachedVoices() -> [TTSModel] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [] }
        return (try? JSONDecoder().decode([TTSModel].self, from: data)) ?? []
    }

    func synthesize(text: String, model: TTSModel, speed: Double, output: URL) async throws {
        guard let voice = model.edgeVoice else { throw TTSError.invalidOnlineResponse }
        let connection = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let endpoint = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"
        guard let url = URL(string: "\(endpoint)?TrustedClientToken=\(trustedToken)&Sec-MS-GEC=\(secMsGec())&Sec-MS-GEC-Version=\(gecVersion)&ConnectionId=\(connection)") else {
            throw ModelError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        let timestamp = Self.timestamp()
        try await socket.send(.string("X-Timestamp:\(timestamp)\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}\r\n"))
        let requestId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let rate = Int((min(max(speed, 0.5), 2.5) - 1) * 100)
        let rateText = rate >= 0 ? "+\(rate)%" : "\(rate)%"
        let safe = SpeechText.prepare(text).xmlEscaped
            .replacingOccurrences(of: "…", with: "<break time='550ms'/>")
        let ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='\(model.language)'><voice name='\(voice)'><prosody rate='\(rateText)' pitch='+0Hz' volume='+0%'>\(safe)</prosody></voice></speak>"
        try await socket.send(.string("X-RequestId:\(requestId)\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:\(timestamp)Z\r\nPath:ssml\r\n\r\n\(ssml)"))
        var audio = Data()
        receiveLoop: while true {
            switch try await socket.receive() {
            case .string(let message):
                if message.localizedCaseInsensitiveContains("Path:turn.end") { break receiveLoop }
            case .data(let frame):
                guard frame.count >= 2 else { continue }
                let headerSize = Int(frame[frame.startIndex]) << 8 | Int(frame[frame.startIndex + 1])
                let start = 2 + headerSize
                guard start <= frame.count,
                      let header = String(data: frame.subdata(in: 2..<start), encoding: .utf8),
                      header.localizedCaseInsensitiveContains("Content-Type:audio") else { continue }
                audio.append(frame.subdata(in: start..<frame.count))
            @unknown default: break
            }
        }
        guard !audio.isEmpty else { throw TTSError.invalidOnlineResponse }
        try audio.write(to: output, options: .atomic)
    }

    private func secMsGec() -> String {
        let seconds = Int64(Date().timeIntervalSince1970) + 11_644_473_600
        let ticks = (seconds - seconds % 300) * 10_000_000
        return SHA256.hash(data: Data("\(ticks)\(trustedToken)".utf8)).map { String(format: "%02X", $0) }.joined()
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
        return formatter.string(from: Date())
    }
}

private extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private extension Array {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var keys = Set<Key>(); return filter { keys.insert($0[keyPath: keyPath]).inserted }
    }
}
