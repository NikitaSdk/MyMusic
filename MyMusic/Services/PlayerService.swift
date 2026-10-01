import Foundation
import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// Плеер: очередь, фоновое воспроизведение, экран блокировки и кнопки наушников.
@MainActor
@Observable
final class PlayerService {
    static let shared = PlayerService()

    private(set) var queue: [Song] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    var errorMessage: String?

    var current: Song? { queue.indices.contains(index) ? queue[index] : nil }
    var hasNext: Bool { index + 1 < queue.count }

    private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {
        configureAudioSession()
        configureRemoteCommands()

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: nil, queue: .main) { [weak self] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated { self?.handleInterruption(typeValue, optionsValue) }
        })
    }

    // MARK: - Управление

    func play(_ songs: [Song], startAt i: Int = 0) {
        guard songs.indices.contains(i) else { return }
        queue = songs
        index = i
        load()
    }

    func togglePlayPause() {
        guard current != nil else { return }
        if isPlaying { pause() } else { resume() }
    }

    func resume() {
        guard player.currentItem != nil else { load(); return }
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func next() {
        guard hasNext else {
            pause()
            seek(to: 0)
            return
        }
        index += 1
        load()
    }

    func previous() {
        if currentTime > 3 || index == 0 {
            seek(to: 0)
        } else {
            index -= 1
            load()
        }
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        currentTime = seconds
        updateNowPlaying()
    }

    // MARK: - Загрузка трека

    private func load() {
        guard let song = current else { return }
        loadTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        isLoading = true
        isPlaying = false
        currentTime = 0
        duration = 0
        errorMessage = nil
        artwork = nil
        updateNowPlaying()
        loadArtwork(for: song)

        // Даём приложению время получить ссылку, даже если экран выключен
        beginBackgroundTask()

        loadTask = Task {
            defer { endBackgroundTask() }
            do {
                let url: URL
                if let local = DownloadService.localURL(for: song.id) {
                    url = local
                } else {
                    guard NetworkMonitor.shared.isOnline else {
                        throw URLError(.notConnectedToInternet)
                    }
                    url = try await YouTubeService.audioURL(for: song.id)
                }
                guard !Task.isCancelled else { return }
                try? AVAudioSession.sharedInstance().setActive(true)
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                player.play()
                isPlaying = true
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = (error as? URLError)?.code == .notConnectedToInternet
                    ? "Нет интернета: доступны только скачанные треки"
                    : "Не удалось загрузить трек"
                isPlaying = false
            }
            isLoading = false
            updateNowPlaying()
        }
    }

    private func tick(_ time: CMTime) {
        if time.seconds.isFinite { currentTime = time.seconds }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0, d != duration {
            duration = d
            updateNowPlaying()
        }
    }

    // MARK: - Фон и экран блокировки

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = e.positionTime
            MainActor.assumeIsolated { self?.seek(to: position) }
            return .success
        }
    }

    private func handleInterruption(_ typeValue: UInt?, _ optionsValue: UInt) {
        guard let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            isPlaying = false
            updateNowPlaying()
        case .ended:
            if AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
        }
    }

    private func updateNowPlaying() {
        guard let song = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for song: Song) {
        Task {
            var image = UIImage(contentsOfFile: DownloadService.thumbURL(for: song.id).path)
            if image == nil, let url = URL(string: song.thumbnailURL),
               let result = try? await URLSession.shared.data(from: url) {
                image = UIImage(data: result.0)
            }
            guard let image, current?.id == song.id else { return }
            artwork = Self.makeArtwork(image)
            updateNowPlaying()
        }
    }

    /// Создаётся вне MainActor: система вызывает обработчик с фонового потока.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
