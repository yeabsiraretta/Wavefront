import Foundation

/// Shuffle mode options
public enum ShuffleMode: String, CaseIterable, Codable {
    case off = "Off"
    case random = "Random"
    case smart = "Smart Shuffle"
    
    public var icon: String {
        switch self {
        case .off: return "arrow.right"
        case .random: return "shuffle"
        case .smart: return "sparkles"
        }
    }
    
    public var description: String {
        switch self {
        case .off: return "Play in order"
        case .random: return "Fully random shuffle"
        case .smart: return "Similar tracks grouped together"
        }
    }
}

/// Service for managing shuffle functionality with multiple modes
public final class ShuffleService {
    public static let shared = ShuffleService()
    
    private init() {
        // Load saved shuffle mode
        if let savedMode = UserDefaults.standard.string(forKey: "shuffleMode"),
           let mode = ShuffleMode(rawValue: savedMode) {
            self.currentMode = mode
        }
    }
    
    /// Current shuffle mode
    public private(set) var currentMode: ShuffleMode = .off {
        didSet {
            UserDefaults.standard.set(currentMode.rawValue, forKey: "shuffleMode")
        }
    }
    
    /// Set the shuffle mode
    public func setMode(_ mode: ShuffleMode) {
        currentMode = mode
    }
    
    /// Cycle to the next shuffle mode
    public func cycleMode() -> ShuffleMode {
        let modes = ShuffleMode.allCases
        guard let currentIndex = modes.firstIndex(of: currentMode) else {
            currentMode = .off
            return .off
        }
        let nextIndex = (currentIndex + 1) % modes.count
        currentMode = modes[nextIndex]
        return currentMode
    }
    
    /// Shuffle a list of tracks based on current mode
    /// - Parameters:
    ///   - tracks: The tracks to shuffle
    ///   - currentTrack: Optional current playing track to base smart shuffle on
    /// - Returns: Shuffled array of tracks
    public func shuffle(_ tracks: [AudioTrack], basedOn currentTrack: AudioTrack? = nil) -> [AudioTrack] {
        switch currentMode {
        case .off:
            return tracks
        case .random:
            return randomShuffle(tracks)
        case .smart:
            return smartShuffle(tracks, basedOn: currentTrack)
        }
    }
    
    /// Get next track based on shuffle mode
    /// - Parameters:
    ///   - currentTrack: The current playing track
    ///   - tracks: All available tracks
    ///   - playedTracks: Set of already played track IDs (for smart shuffle history)
    /// - Returns: The next track to play
    public func getNextTrack(
        current currentTrack: AudioTrack,
        from tracks: [AudioTrack],
        playedTracks: Set<UUID> = []
    ) -> AudioTrack? {
        guard !tracks.isEmpty else { return nil }
        
        switch currentMode {
        case .off:
            // Play in order
            guard let currentIndex = tracks.firstIndex(where: { $0.id == currentTrack.id }) else {
                return tracks.first
            }
            let nextIndex = currentIndex + 1
            return nextIndex < tracks.count ? tracks[nextIndex] : nil
            
        case .random:
            // Pick a random track (avoid current if possible)
            let availableTracks = tracks.filter { $0.id != currentTrack.id }
            return availableTracks.randomElement() ?? tracks.randomElement()
            
        case .smart:
            // Pick a similar track that hasn't been played recently
            return getSmartNextTrack(current: currentTrack, from: tracks, playedTracks: playedTracks)
        }
    }
    
    // MARK: - Private Methods
    
    private func randomShuffle(_ tracks: [AudioTrack]) -> [AudioTrack] {
        return tracks.shuffled()
    }
    
    /// Smart shuffle groups similar tracks together based on artist, album, and title patterns
    private func smartShuffle(_ tracks: [AudioTrack], basedOn currentTrack: AudioTrack?) -> [AudioTrack] {
        guard !tracks.isEmpty else { return [] }
        
        // If no current track, start with a random one
        guard let seedTrack = currentTrack ?? tracks.randomElement() else {
            return tracks.shuffled()
        }
        
        var result: [AudioTrack] = []
        var remaining = tracks
        var current = seedTrack
        
        // Remove seed from remaining if present
        remaining.removeAll { $0.id == current.id }
        result.append(current)
        
        // Build playlist by always picking the most similar remaining track
        while !remaining.isEmpty {
            let scored = remaining.map { track -> (track: AudioTrack, score: Double) in
                let score = calculateSimilarity(between: current, and: track)
                return (track, score)
            }
            
            // Sort by score descending and pick from top candidates with some randomness
            let sorted = scored.sorted { $0.score > $1.score }
            let topCount = min(3, sorted.count)
            let topCandidates = Array(sorted.prefix(topCount))
            
            // Weighted random selection from top candidates
            if let selected = weightedRandomSelect(from: topCandidates) {
                result.append(selected)
                remaining.removeAll { $0.id == selected.id }
                current = selected
            } else if let first = remaining.first {
                result.append(first)
                remaining.removeFirst()
                current = first
            }
        }
        
        return result
    }
    
    private func getSmartNextTrack(
        current: AudioTrack,
        from tracks: [AudioTrack],
        playedTracks: Set<UUID>
    ) -> AudioTrack? {
        // Filter out recently played tracks
        let unplayed = tracks.filter { !playedTracks.contains($0.id) && $0.id != current.id }
        let candidates = unplayed.isEmpty ? tracks.filter { $0.id != current.id } : unplayed
        
        guard !candidates.isEmpty else { return tracks.first }
        
        // Score candidates by similarity
        let scored = candidates.map { track -> (track: AudioTrack, score: Double) in
            let score = calculateSimilarity(between: current, and: track)
            return (track, score)
        }
        
        // Pick from top similar tracks with some randomness
        let sorted = scored.sorted { $0.score > $1.score }
        let topCount = min(5, sorted.count)
        let topCandidates = Array(sorted.prefix(topCount))
        
        return weightedRandomSelect(from: topCandidates)
    }
    
    /// Calculate similarity score between two tracks (0.0 to 1.0)
    private func calculateSimilarity(between track1: AudioTrack, and track2: AudioTrack) -> Double {
        var score: Double = 0.0
        
        // Same artist: high similarity
        if let artist1 = track1.artist?.lowercased(),
           let artist2 = track2.artist?.lowercased() {
            if artist1 == artist2 {
                score += 0.4
            } else if artist1.contains(artist2) || artist2.contains(artist1) {
                score += 0.2
            }
        }
        
        // Same album: high similarity
        if let album1 = track1.album?.lowercased(),
           let album2 = track2.album?.lowercased() {
            if album1 == album2 {
                score += 0.3
            } else if album1.contains(album2) || album2.contains(album1) {
                score += 0.15
            }
        }
        
        // Similar title words (might indicate similar genre/theme)
        let words1 = Set(track1.title.lowercased().split(separator: " ").map(String.init))
        let words2 = Set(track2.title.lowercased().split(separator: " ").map(String.init))
        let commonWords = words1.intersection(words2)
        if !commonWords.isEmpty {
            score += min(Double(commonWords.count) * 0.05, 0.15)
        }
        
        // Similar duration (within 1 minute): slight similarity
        if let duration1 = track1.duration, let duration2 = track2.duration {
            let durationDiff = abs(duration1 - duration2)
            if durationDiff < 60 {
                score += 0.1 * (1.0 - durationDiff / 60.0)
            }
        }
        
        // Add small random factor to avoid always same order
        score += Double.random(in: 0...0.05)
        
        return min(score, 1.0)
    }
    
    /// Weighted random selection - higher scored tracks more likely to be selected
    private func weightedRandomSelect(from candidates: [(track: AudioTrack, score: Double)]) -> AudioTrack? {
        guard !candidates.isEmpty else { return nil }
        
        let totalScore = candidates.reduce(0.0) { $0 + max($1.score, 0.1) }
        var random = Double.random(in: 0..<totalScore)
        
        for candidate in candidates {
            random -= max(candidate.score, 0.1)
            if random <= 0 {
                return candidate.track
            }
        }
        
        return candidates.last?.track
    }
}
