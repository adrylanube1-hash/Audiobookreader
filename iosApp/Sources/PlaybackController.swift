import AVFoundation
import Combine
import Foundation
import MediaPlayer

struct PlaybackSnapshot: Equatable {
    var bookId: UUID?
    var chunkIndex = 0
    var position: TimeInterval = 0
    var isPlaying = false
    var isGenerating = false
    var preparedThrough = 0
    var errorMessage: String?
}

@MainActor
final class PlaybackController: ObservableObject {
    typealias Renderer = @Sendable (String, TTSModel, BookVoiceSettings, URL) async throws -> Void
    @Published private(set) var snapshot = PlaybackSnapshot()
    private let player = AVQueuePlayer()
    private var generation: Task<Void, Never>?
    private var itemChunks: [ObjectIdentifier: Int] = [:]
    private var book: LibraryBook?
    private var model: TTSModel?
    private var manager: ModelManager?
    private var renderer: Renderer?
    private var timer: Timer?
    private var shouldPlay = false

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? AVAudioSession.sharedInstance().setActive(true)
        NotificationCenter.default.addObserver(self, selector: #selector(itemFinished(_:)), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(interruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        setupRemoteCommands()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit { NotificationCenter.default.removeObserver(self); timer?.invalidate() }

    func start(book: LibraryBook, model: TTSModel, at chunk: Int, modelManager: ModelManager, renderer: @escaping Renderer) {
        stop(clearIdentity: false)
        self.book = book; self.model = model; self.manager = modelManager; self.renderer = renderer
        shouldPlay = true
        snapshot = PlaybackSnapshot(bookId: book.id, chunkIndex: chunk, position: chunk == book.currentChunk ? book.currentPosition : 0,
                                    isPlaying: false, isGenerating: true, preparedThrough: chunk)
        updateNowPlaying()
        generation = Task { [weak self] in await self?.generate(from: chunk) }
    }

    func toggle() {
        if player.timeControlStatus == .playing { pause() }
        else { shouldPlay = true; player.play(); snapshot.isPlaying = true; updateNowPlaying() }
    }

    func pause() { shouldPlay = false; player.pause(); snapshot.isPlaying = false; updateNowPlaying() }

    func stop() { stop(clearIdentity: true) }
    private func stop(clearIdentity: Bool) {
        generation?.cancel(); generation = nil; player.pause(); player.removeAllItems(); itemChunks.removeAll(); shouldPlay = false
        snapshot.isPlaying = false; snapshot.isGenerating = false
        if clearIdentity { snapshot.bookId = nil; book = nil; model = nil; manager = nil; renderer = nil; MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    }

    func previousChunk() { seekToChunk(max(snapshot.chunkIndex - 1, 0)) }
    func nextChunk() {
        guard let book else { return }
        seekToChunk(min(snapshot.chunkIndex + 1, max(book.chunks.count - 1, 0)))
    }
    func seek(seconds: TimeInterval) {
        let target = max(0, player.currentTime().seconds + seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 1000))
    }

    private func seekToChunk(_ chunk: Int) {
        guard let book, let model, let manager, let renderer else { return }
        start(book: book, model: model, at: chunk, modelManager: manager, renderer: renderer)
    }

    private func generate(from start: Int) async {
        guard let book, let model, let manager, let renderer else { return }
        let chunks = book.chunks
        for index in start..<chunks.count {
            if Task.isCancelled { break }
            let final = manager.audioURL(bookId: book.id, chunk: index, model: model, settings: book.voice)
            let temporary = final.appendingPathExtension("part")
            do {
                if !FileManager.default.fileExists(atPath: final.path) {
                    try? FileManager.default.removeItem(at: temporary)
                    try await renderer(chunks[index], model, book.voice, temporary)
                    try Task.checkCancellation()
                    try FileManager.default.moveItem(at: temporary, to: final)
                }
                guard !Task.isCancelled else { try? FileManager.default.removeItem(at: temporary); break }
                enqueue(final, chunk: index, resumePosition: index == start ? snapshot.position : 0)
                snapshot.preparedThrough = index
            } catch is CancellationError { try? FileManager.default.removeItem(at: temporary); break }
            catch {
                try? FileManager.default.removeItem(at: temporary)
                snapshot.isGenerating = false
                snapshot.errorMessage = error.localizedDescription
                break
            }
        }
        snapshot.isGenerating = false
    }

    private func enqueue(_ url: URL, chunk: Int, resumePosition: TimeInterval) {
        let item = AVPlayerItem(url: url)
        itemChunks[ObjectIdentifier(item)] = chunk
        player.insert(item, after: nil)
        if player.currentItem === item, resumePosition > 0 {
            player.seek(to: CMTime(seconds: resumePosition, preferredTimescale: 1000))
        }
        if shouldPlay { player.play(); snapshot.isPlaying = true }
    }

    @objc private func itemFinished(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem, let index = itemChunks.removeValue(forKey: ObjectIdentifier(item)) else { return }
        snapshot.chunkIndex = index + 1; snapshot.position = 0
        if player.items().isEmpty && !snapshot.isGenerating { shouldPlay = false; snapshot.isPlaying = false }
        updateNowPlaying()
    }

    @objc private func interruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began { pause() }
        else if let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume), shouldPlay { player.play() }
    }

    private func tick() {
        guard let current = player.currentItem else { return }
        snapshot.position = max(0, current.currentTime().seconds.isFinite ? current.currentTime().seconds : 0)
        if let index = itemChunks[ObjectIdentifier(current)] { snapshot.chunkIndex = index }
        snapshot.isPlaying = player.timeControlStatus == .playing
        updateNowPlaying()
    }

    private func setupRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.nextChunk() }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previousChunk() }; return .success }
        commands.skipBackwardCommand.preferredIntervals = [15]
        commands.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.seek(seconds: -15) }; return .success }
        commands.skipForwardCommand.preferredIntervals = [30]
        commands.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.seek(seconds: 30) }; return .success }
    }

    private func updateNowPlaying() {
        guard let book else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = book.title
        info[MPMediaItemPropertyAlbumTitle] = "audiobookreader"
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = snapshot.position
        info[MPNowPlayingInfoPropertyPlaybackRate] = snapshot.isPlaying ? 1.0 : 0.0
        info[MPMediaItemPropertyPlaybackDuration] = player.currentItem?.duration.seconds.isFinite == true ? player.currentItem?.duration.seconds : nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
