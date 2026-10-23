import AVFoundation
import MediaPlayer
import SwiftUI

@MainActor
final class PlayerStore: ObservableObject {
    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var errorMessage: String?

    private let player = AVPlayer()
    private var timeObserver: Any?

    init() {
        configureAudioSession()
        configureRemoteCommands()
        observePlaybackEnd()
        observePlaybackProgress()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    func play(song: Song, sourceURL: URL) {
        errorMessage = nil
        currentSong = song
        currentTime = 0
        duration = 0

        let item = AVPlayerItem(url: sourceURL)
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func togglePlayback() {
        guard currentSong != nil else {
            return
        }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }

        updateNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        guard duration > 0 else {
            return
        }

        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: target)
        currentTime = seconds
        updateNowPlayingInfo()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
        } catch {
            errorMessage = "无法配置 iPhone 的音频播放权限。"
        }
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()

        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                if !self.isPlaying {
                    self.togglePlayback()
                }
            }
            return .success
        }

        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                if self.isPlaying {
                    self.togglePlayback()
                }
            }
            return .success
        }
    }

    private func observePlaybackEnd() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.currentTime = self?.duration ?? 0
                self?.updateNowPlayingInfo()
            }
        }
    }

    private func observePlaybackProgress() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.currentTime = max(time.seconds, 0)
                let itemDuration = self.player.currentItem?.duration.seconds ?? 0
                if itemDuration.isFinite && itemDuration > 0 {
                    self.duration = itemDuration
                }
                self.updateNowPlayingInfo()
            }
        }
    }

    private func updateNowPlayingInfo() {
        guard let currentSong else {
            return
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: currentSong.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1 : 0
        ]
    }
}
