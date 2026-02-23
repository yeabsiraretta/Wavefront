import Foundation

/**
 * Manages multiple audio sources and provides unified access to tracks.
 *
 * This actor coordinates access to various audio sources (local storage,
 * SMB shares, etc.) and provides methods to fetch tracks, register/unregister
 * sources, and get playable URLs.
 *
 * ## Thread Safety
 * As an actor, all access is automatically serialized to prevent data races.
 *
 * ## Usage
 * ```swift
 * let manager = AudioSourceManager()
 * await manager.register(localSource)
 * let tracks = await manager.fetchAllTracks()
 * ```
 */
public actor AudioSourceManager {
    /// Dictionary of registered sources keyed by source ID
    private var sources: [String: any AudioSource] = [:]
    
    /**
     * Creates a new AudioSourceManager instance.
     */
    public init() {}
    
    /**
     * Registers an audio source with the manager.
     *
     * The source will be available for track fetching and URL resolution.
     * If a source with the same ID already exists, it will be replaced.
     *
     * @param source - The AudioSource implementation to register
     */
    public func register(_ source: any AudioSource) {
        sources[source.sourceId] = source
    }
    
    /**
     * Unregisters an audio source by its ID.
     *
     * @param sourceId - The unique identifier of the source to remove
     */
    public func unregister(sourceId: String) {
        sources.removeValue(forKey: sourceId)
    }
    
    /**
     * Retrieves a registered source by its ID.
     *
     * @param id - The unique identifier of the source
     * @returns The AudioSource if found, nil otherwise
     */
    public func source(for id: String) -> (any AudioSource)? {
        sources[id]
    }
    
    /**
     * Returns all registered audio sources.
     *
     * @returns Array of all registered AudioSource implementations
     */
    public func allSources() -> [any AudioSource] {
        Array(sources.values)
    }
    
    /**
     * Returns only sources that are currently available.
     *
     * Checks each source's availability status asynchronously.
     *
     * @returns Array of available AudioSource implementations
     */
    public func availableSources() async -> [any AudioSource] {
        var available: [any AudioSource] = []
        
        for source in sources.values {
            if await source.isAvailable {
                available.append(source)
            }
        }
        
        return available
    }
    
    /**
     * Fetches tracks from all registered sources concurrently.
     *
     * Uses Swift's TaskGroup to fetch from all sources in parallel,
     * combining results into a single array. Errors from individual
     * sources are silently ignored to prevent partial failures.
     *
     * @returns Combined array of AudioTracks from all sources
     */
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
