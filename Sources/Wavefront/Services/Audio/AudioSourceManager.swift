import Foundation

/// Manages multiple audio sources and provides unified access
public actor AudioSourceManager {
    private var sources: [String: any AudioSource] = [:]
    
    public init() {}
    
    /// Registers an audio source
    public func register(_ source: any AudioSource) {
        sources[source.sourceId] = source
    }
    
    /// Unregisters an audio source by ID
    public func unregister(sourceId: String) {
        sources.removeValue(forKey: sourceId)
    }
    
    /// Gets a source by ID
    public func source(for id: String) -> (any AudioSource)? {
        sources[id]
    }
    
    /// Gets all registered sources
    public func allSources() -> [any AudioSource] {
        Array(sources.values)
    }
    
    /// Gets all available sources
    public func availableSources() async -> [any AudioSource] {
        var available: [any AudioSource] = []
        
        for source in sources.values {
            if await source.isAvailable {
                available.append(source)
            }
        }
        
        return available
    }
    
    /// Fetches tracks from all registered sources
    public func fetchAllTracks() async -> [AudioTrack] {
        var allTracks: [AudioTrack] = []
        
        await withTaskGroup(of: [AudioTrack].self) { group in
            for source in sources.values {
                group.addTask {
                    do {
                        return try await source.fetchTracks()
                    } catch {
                        return []
                    }
                }
            }
            
            for await tracks in group {
                allTracks.append(contentsOf: tracks)
            }
        }
        
        return allTracks
    }
    
    /// Fetches tracks from a specific source
    public func fetchTracks(from sourceId: String) async throws -> [AudioTrack] {
        guard let source = sources[sourceId] else {
            throw AudioSourceError.sourceUnavailable
        }
        
        return try await source.fetchTracks()
    }
    
    /// Gets a playable URL for a track
    public func getPlayableURL(for track: AudioTrack) async throws -> URL {
        // Find the source that owns this track
        for source in sources.values where source.sourceType == track.sourceType {
            if await source.trackExists(track) {
                return try await source.getPlayableURL(for: track)
            }
        }
        
        throw AudioSourceError.trackNotFound(track.title)
    }
}
