import Foundation
import AVFoundation
import MediaPlayer

/// Playback state of the audio player
public enum PlaybackState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case failed(String)
}

/// Delegate for audio player events
public protocol AudioPlayerDelegate: AnyObject, Sendable {
    func audioPlayer(_ player: AudioPlayer, didChangeState state: PlaybackState)
    func audioPlayer(_ player: AudioPlayer, didUpdateProgress currentTime: TimeInterval, duration: TimeInterval)
    func audioPlayer(_ player: AudioPlayer, didFinishPlaying track: AudioTrack)
    func audioPlayer(_ player: AudioPlayer, didFailWithError error: Error)
}

/// Audio player service using AVPlayer for playback
public final class AudioPlayer: NSObject, @unchecked Sendable {
    public weak var delegate: AudioPlayerDelegate?
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    
    private let sourceManager: AudioSourceManager
    private let updateInterval: TimeInterval
    
    public private(set) var currentTrack: AudioTrack?
    public private(set) var state: PlaybackState = .idle {
        didSet {
            guard oldValue != state else { return }
            delegate?.audioPlayer(self, didChangeState: state)
        }
    }
    
    public var currentTime: TimeInterval {
        player?.currentTime().seconds ?? 0
    }
    
    public var duration: TimeInterval {
        player?.currentItem?.duration.seconds ?? 0
    }
    
    public var isPlaying: Bool {
        state == .playing
    }
    
    public var volume: Float {
        get { player?.volume ?? 1.0 }
        set { player?.volume = newValue }
    }
    
    public init(sourceManager: AudioSourceManager, updateInterval: TimeInterval = 0.5) {
        self.sourceManager = sourceManager
        self.updateInterval = updateInterval
        super.init()
        
        setupAudioSession()
        setupRemoteCommandCenter()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Playback Control
    
    /// Plays a track
    public func play(_ track: AudioTrack) async {
        state = .loading
        currentTrack = track
        
        do {
            let url = try await sourceManager.getPlayableURL(for: track)
            await MainActor.run {
                setupPlayer(with: url)
                player?.play()
                state = .playing
                updateNowPlayingInfo()
            }
        } catch {
            state = .failed(error.localizedDescription)
            delegate?.audioPlayer(self, didFailWithError: error)
        }
    }
    
    /// Resumes playback
    public func resume() {
        guard state == .paused else { return }
        player?.play()
        state = .playing
        updateNowPlayingInfo()
    }
    
    /// Pauses playback
    public func pause() {
        guard state == .playing else { return }
        player?.pause()
        state = .paused
        updateNowPlayingInfo()
    }
    
    /// Toggles play/pause
    public func togglePlayPause() {
        if state == .playing {
            pause()
        } else if state == .paused {
            resume()
        }
    }
    
    /// Stops playback
    public func stop() {
        player?.pause()
        player?.seek(to: .zero)
        state = .stopped
        clearNowPlayingInfo()
    }
    
    /// Seeks to a specific time
    public func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime) { [weak self] _ in
            self?.updateNowPlayingInfo()
        }
    }
    
    /// Seeks forward by specified seconds
    public func seekForward(by seconds: TimeInterval = 15) {
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
    }
    
    /// Seeks backward by specified seconds
    public func seekBackward(by seconds: TimeInterval = 15) {
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }
    
    // MARK: - Private Methods
    
    private func setupAudioSession() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
        #endif
        // macOS doesn't require AVAudioSession configuration
    }
    
    private func setupPlayer(with url: URL) {
        cleanup()
        
        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        // Observe playback end
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        // Observe playback errors
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFail),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem
        )
        
        // Add periodic time observer
        let interval = CMTime(seconds: updateInterval, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.audioPlayer(self, didUpdateProgress: self.currentTime, duration: self.duration)
        }
    }
    
    @objc private func playerDidFinishPlaying(_ notification: Notification) {
        state = .stopped
        if let track = currentTrack {
            delegate?.audioPlayer(self, didFinishPlaying: track)
        }
    }
    
    @objc private func playerDidFail(_ notification: Notification) {
        let error = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
            ?? AudioSourceError.unknown("Playback failed")
        state = .failed(error.localizedDescription)
        delegate?.audioPlayer(self, didFailWithError: error)
    }
    
    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        NotificationCenter.default.removeObserver(self)
        
        player?.pause()
        player = nil
        playerItem = nil
    }
    
    // MARK: - Now Playing Info
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.seekForward()
            return .success
        }
        
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.seekBackward()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: event.positionTime)
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }
        
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0
        ]
        
        if let artist = track.artist {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        
        if let album = track.album {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
