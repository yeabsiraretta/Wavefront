import Foundation
import Combine

/**
 * ViewModel for managing the music library UI and business logic.
 *
 * This class serves as the central coordinator for all music-related operations
 * including playback control, track management, metadata enrichment, and
 * external service integration (YouTube, Spotify).
 *
 * ## Features
 * - Track library management with multiple audio sources
 * - Playback control with queue support
 * - YouTube and Spotify import capabilities
 * - Metadata enrichment from external services
 * - Music thoughts journaling
 * - Custom album art management
 *
 * ## Usage
 * ```swift
 * @StateObject private var viewModel = MusicLibraryViewModel()
 * ```
 *
 * @property tracks - Array of all audio tracks in the library
 * @property isLoading - Indicates if a loading operation is in progress
 * @property errorMessage - Current error message to display, if any
 * @property currentTrack - The currently playing or selected track
 * @property isPlaying - Whether audio is currently playing
 * @property currentPlaybackTime - Current playback position in seconds
 * @property playQueue - Queue of tracks to play after current track
 */
@MainActor
public final class MusicLibraryViewModel: ObservableObject {
    /// All audio tracks in the library, sorted alphabetically by title
    @Published public private(set) var tracks: [AudioTrack] = []
    
    /// Indicates whether a loading operation is currently in progress
    @Published public private(set) var isLoading = false
    
    /// Current error message to display to the user, nil if no error
    @Published public private(set) var errorMessage: String?
    
    /// The track that is currently playing or was last played
    @Published public var currentTrack: AudioTrack?
    
    /// Whether audio playback is currently active
    @Published public var isPlaying = false
    
    /// Current playback position in seconds
    @Published public var currentPlaybackTime: TimeInterval = 0
    
    /// Whether metadata enrichment is currently running
    @Published public var isEnrichingMetadata = false
    
    /// Progress of YouTube download (0.0 to 1.0), nil when not downloading
    @Published public var youtubeDownloadProgress: Double?
    
    /// Status message for YouTube import operations
    @Published public var youtubeImportStatus: String?
    
    /// Progress of Spotify download (0.0 to 1.0), nil when not downloading
    @Published public var spotifyDownloadProgress: Double?
    
    /// Status message for Spotify import operations
    @Published public var spotifyImportStatus: String?
    
    /// Queue of tracks to play next, in order
    @Published public private(set) var playQueue: [AudioTrack] = []
    
    private let sourceManager: AudioSourceManager
    private let player: AudioPlayer
    private let metadataService: MetadataService
    private let youtubeKitExtractor: YouTubeKitExtractor?
    private var spotifyExtractor: SpotifyExtractor?
    
    /**
     * Creates a new MusicLibraryViewModel with specified dependencies.
     *
     * Use this initializer for dependency injection in testing scenarios
     * or when custom configurations are needed.
     *
     * @param sourceManager - The AudioSourceManager for managing audio sources
     * @param player - The AudioPlayer instance for playback control
     * @param metadataService - Service for fetching track metadata
     * @param youtubeKitExtractor - Optional YouTube extractor for imports
     */
    public init(
        sourceManager: AudioSourceManager,
        player: AudioPlayer,
        metadataService: MetadataService = MetadataService(),
        youtubeKitExtractor: YouTubeKitExtractor? = nil
    ) {
        self.sourceManager = sourceManager
        self.player = player
        self.metadataService = metadataService
        self.youtubeKitExtractor = youtubeKitExtractor
    }
    
    /**
     * Convenience initializer that creates the ViewModel with default dependencies.
     *
     * This is the recommended initializer for production use. It automatically:
     * - Creates an AudioSourceManager and AudioPlayer
     * - Initializes the YouTube and Spotify extractors
     * - Sets up the local audio source
     * - Restores any previously saved folder bookmarks
     */
    public convenience init() {
        let manager = AudioSourceManager()
        let player = AudioPlayer(sourceManager: manager)
        let ytKitExtractor = try? YouTubeKitExtractor()
        self.init(
            sourceManager: manager,
            player: player,
            metadataService: MetadataService(),
            youtubeKitExtractor: ytKitExtractor
        )
        
        // Set up player delegate for time updates
        player.delegate = self
        
        // Set up Spotify extractor if credentials are configured
        setupSpotifyExtractor()
        
        Task {
            await setupDefaultSources()
        }
    }
    
    /**
     * Initializes the Spotify extractor for web scraping.
     *
     * This method sets up the SpotifyExtractor which uses web scraping
     * instead of API credentials to fetch track metadata from Spotify.
     * Called automatically during ViewModel initialization.
     */
    public func setupSpotifyExtractor() {
        spotifyExtractor = try? SpotifyExtractor()
    }
    
    /**
     * Indicates whether Spotify import is available.
     *
     * Always returns true since web scraping doesn't require API credentials.
     *
     * @returns true - Spotify is always available
     */
    public var isSpotifyConfigured: Bool {
        true
    }
    
    /**
     * Sets up the default local audio source and restores saved folders.
     *
     * This private method is called during initialization to configure
     * the local file system as an audio source and restore any
     * previously bookmarked folders.
     */
    private func setupDefaultSources() async {
        do {
            let localSource = try LocalAudioSource()
            await sourceManager.register(localSource)
        } catch {
            errorMessage = "Failed to setup local storage: \(error.localizedDescription)"
        }
        
        // Restore any previously saved folder bookmarks
        await restoreSavedFolders()
    }
    
    /**
     * Registers an additional audio source with the source manager.
     *
     * Use this to add custom audio sources such as network shares,
     * cloud storage, or other external sources.
     *
     * @param source - The AudioSource implementation to register
     */
    public func addSource(_ source: any AudioSource) async {
        await sourceManager.register(source)
    }
    
    /**
     * Refreshes the track list from all registered audio sources.
     *
     * This method fetches tracks from all registered sources (local storage,
     * SMB shares, etc.) and updates the tracks array. Tracks are sorted
     * alphabetically by title after fetching.
     *
     * Sets isLoading to true during the operation and clears any
     * existing error messages.
     */
    public func refreshTracks() async {
        isLoading = true
        errorMessage = nil
        
        tracks = await sourceManager.fetchAllTracks()
        
        // Sort by title
        tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        
        isLoading = false
    }
    
    /**
     * Begins playback of the specified track.
     *
     * Sets the track as the current track, updates the isPlaying state,
     * and initiates playback through the audio player.
     *
     * @param track - The AudioTrack to play
     */
    public func play(_ track: AudioTrack) {
        currentTrack = track
        isPlaying = true
        
        Task {
            await player.play(track)
        }
    }
    
    /**
     * Toggles between play and pause states.
     *
     * If currently playing, pauses playback. If paused, resumes playback.
     * Updates the isPlaying state to reflect the new state.
     */
    public func togglePlayPause() {
        player.togglePlayPause()
        isPlaying = player.isPlaying
    }
    
    /**
     * Stops playback completely and clears the current track.
     *
     * This method stops the audio player, sets isPlaying to false,
     * and clears the currentTrack reference.
     */
    public func stop() {
        player.stop()
        isPlaying = false
        currentTrack = nil
    }
    
    // MARK: - Queue Management
    
    /**
     * Adds a track to the play queue.
     *
     * The track will be appended to the end of the current queue and will play
     * after all previously queued tracks have finished. If the track is already
     * in the queue, it will not be added again.
     *
     * @param track - The AudioTrack to add to the queue
     */
    public func addToQueue(_ track: AudioTrack) {
        guard !playQueue.contains(where: { $0.id == track.id }) else { return }
        playQueue.append(track)
    }
    
    /**
     * Removes a track from the play queue.
     *
     * If the track is not in the queue, this method has no effect.
     *
     * @param track - The AudioTrack to remove from the queue
     */
    public func removeFromQueue(_ track: AudioTrack) {
        playQueue.removeAll { $0.id == track.id }
    }
    
    /**
     * Checks if a track is currently in the play queue.
     *
     * @param track - The AudioTrack to check
     * @returns Boolean indicating whether the track is queued
     */
    public func isInQueue(_ track: AudioTrack) -> Bool {
        playQueue.contains { $0.id == track.id }
    }
    
    /**
     * Clears all tracks from the play queue.
     *
     * This does not affect the currently playing track.
     */
    public func clearQueue() {
        playQueue.removeAll()
    }
    
    /**
     * Moves a track within the queue to a new position.
     *
     * @param from - The current index of the track in the queue
     * @param to - The target index to move the track to
     */
    public func moveInQueue(from: Int, to: Int) {
        guard from >= 0, from < playQueue.count,
              to >= 0, to < playQueue.count else { return }
        let track = playQueue.remove(at: from)
        playQueue.insert(track, at: to)
    }
    
    /**
     * Plays the next track in the queue.
     *
     * Removes the first track from the queue and begins playback.
     * If the queue is empty, this method has no effect.
     */
    public func playNextInQueue() {
        guard !playQueue.isEmpty else { return }
        let nextTrack = playQueue.removeFirst()
        play(nextTrack)
    }
    
    /**
     * Clears the current error message.
     *
     * Sets errorMessage to nil, which dismisses any error UI.
     */
    public func clearError() {
        errorMessage = nil
    }
    
    /**
     * Sets an error message to display to the user.
     *
     * @param message - The error message string to display
     */
    public func setError(_ message: String) {
        errorMessage = message
    }
    
    /**
     * Deletes a track from the library and file system.
     *
     * This method:
     * - Stops playback if the track is currently playing
     * - Removes the track from the tracks array
     * - Removes the track from liked songs
     * - Deletes the file from disk (for local tracks only)
     *
     * @param track - The AudioTrack to delete
     */
    public func deleteTrack(_ track: AudioTrack) {
        // Stop playback if this track is playing
        if currentTrack?.id == track.id {
            stop()
        }
        
        // Remove from tracks array
        tracks.removeAll { $0.id == track.id }
        
        // Remove from liked songs if applicable
        UserLibrary.shared.unlike(track)
        
        // Delete from file system if it's a local file
        if track.sourceType == .local {
            do {
                try FileManager.default.removeItem(at: track.fileURL)
            } catch {
                setError("Could not delete file: \(error.localizedDescription)")
            }
        }
    }
    
    /// Delete multiple tracks
    public func deleteTracks(_ tracksToDelete: [AudioTrack]) {
        for track in tracksToDelete {
            deleteTrack(track)
        }
    }
    
    /// Get tracks grouped by source type
    public var tracksBySource: [AudioSourceType: [AudioTrack]] {
        Dictionary(grouping: tracks, by: { $0.sourceType })
    }
    
    /// Get tracks grouped by artist
    public var tracksByArtist: [String: [AudioTrack]] {
        Dictionary(grouping: tracks, by: { $0.artist ?? "Unknown Artist" })
    }
    
    // MARK: - Local Source Management
    
    private var _localSources: [LocalAudioSource] = []
    
    /// Get all registered local sources (including custom folders)
    public var localSources: [LocalAudioSource] {
        _localSources
    }
    
    /// Add a local source from a user-selected folder
    public func addLocalSource(url: URL, bookmark: Data?) async throws {
        let sourceId = "local-\(url.lastPathComponent)-\(UUID().uuidString.prefix(8))"
        let displayName = url.lastPathComponent
        
        // If we have a bookmark, resolve it
        var resolvedURL = url
        var isSecurityScoped = false
        
        if let bookmark = bookmark {
            var isStale = false
            #if os(macOS)
            if let bookmarkedURL = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                resolvedURL = bookmarkedURL
                isSecurityScoped = true
            }
            #else
            if let bookmarkedURL = try? URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                resolvedURL = bookmarkedURL
                isSecurityScoped = true
            }
            #endif
        }
        
        let source = LocalAudioSource(
            sourceId: sourceId,
            displayName: displayName,
            baseDirectory: resolvedURL,
            isSecurityScoped: isSecurityScoped
        )
        
        _localSources.append(source)
        await sourceManager.register(source)
        
        // Save bookmark for persistence
        if let bookmark = bookmark {
            saveBookmark(bookmark, forSourceId: sourceId)
        }
    }
    
    /// Remove a local source by ID
    public func removeLocalSource(sourceId: String) async {
        _localSources.removeAll { $0.sourceId == sourceId }
        await sourceManager.unregister(sourceId: sourceId)
        removeBookmark(forSourceId: sourceId)
        
        // Remove tracks from this source
        tracks.removeAll { track in
            track.sourceType == .local && track.fileURL.absoluteString.contains(sourceId)
        }
    }
    
    // MARK: - Bookmark Persistence
    
    private func saveBookmark(_ bookmark: Data, forSourceId sourceId: String) {
        var bookmarks = UserDefaults.standard.dictionary(forKey: "folderBookmarks") as? [String: Data] ?? [:]
        bookmarks[sourceId] = bookmark
        UserDefaults.standard.set(bookmarks, forKey: "folderBookmarks")
    }
    
    private func removeBookmark(forSourceId sourceId: String) {
        var bookmarks = UserDefaults.standard.dictionary(forKey: "folderBookmarks") as? [String: Data] ?? [:]
        bookmarks.removeValue(forKey: sourceId)
        UserDefaults.standard.set(bookmarks, forKey: "folderBookmarks")
    }
    
    /// Restore saved folder bookmarks on launch
    public func restoreSavedFolders() async {
        guard let bookmarks = UserDefaults.standard.dictionary(forKey: "folderBookmarks") as? [String: Data] else {
            return
        }
        
        for (sourceId, bookmark) in bookmarks {
            var isStale = false
            #if os(macOS)
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            #else
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            #endif
            
            let source = LocalAudioSource(
                sourceId: sourceId,
                displayName: url.lastPathComponent,
                baseDirectory: url,
                isSecurityScoped: true
            )
            
            _localSources.append(source)
            await sourceManager.register(source)
        }
    }
    
    // MARK: - SMB Source Management
    
    private var _smbSources: [SMBAudioSource] = []
    
    /// Get all registered SMB sources
    public var smbSources: [SMBAudioSource] {
        _smbSources
    }
    
    /// Add an SMB source from configuration
    public func addSMBSource(configuration: SMBConfiguration) async throws {
        let source = try SMBAudioSource(configuration: configuration)
        
        // Test connection
        guard await source.isAvailable else {
            throw AudioSourceError.connectionFailed("Could not connect to SMB share")
        }
        
        _smbSources.append(source)
        await sourceManager.register(source)
    }
    
    /// Remove an SMB source by ID
    public func removeSMBSource(sourceId: String) async {
        _smbSources.removeAll { $0.sourceId == sourceId }
        await sourceManager.unregister(sourceId: sourceId)
        
        // Remove tracks from this source
        tracks.removeAll { track in
            track.sourceType == .smb && track.fileURL.absoluteString.contains(sourceId)
        }
    }
    
    // MARK: - Metadata Enrichment
    
    /// Enrich all tracks with missing metadata from TheAudioDB
    public func enrichAllMetadata() async {
        isEnrichingMetadata = true
        
        tracks = await metadataService.enrichTracks(tracks)
        tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        
        isEnrichingMetadata = false
    }
    
    /// Enrich a single track's metadata
    public func enrichMetadata(for track: AudioTrack) async {
        let enriched = await metadataService.enrichTrack(track)
        
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[index] = enriched
        }
    }
    
    // MARK: - YouTube Download
    
    /// Check if YouTube downloading is available
    public var isYouTubeDownloadAvailable: Bool {
        youtubeKitExtractor != nil
    }
    
    /// Import audio from a YouTube URL using native YouTubeKit extraction
    /// Supports both single videos and playlists
    public func importFromYouTube(urlString: String) async throws {
        guard let extractor = youtubeKitExtractor else {
            throw YouTubeKitError.extractionFailed("YouTube extractor not initialized")
        }
        
        youtubeDownloadProgress = 0
        youtubeImportStatus = "Analyzing URL..."
        
        // Ensure progress is always cleared, even on error
        defer {
            youtubeDownloadProgress = nil
            youtubeImportStatus = nil
        }
        
        // Check if it's a playlist URL
        if urlString.contains("list=") || urlString.contains("/playlist") {
            try await importPlaylist(urlString: urlString, extractor: extractor)
        } else {
            try await importSingleVideo(urlString: urlString, extractor: extractor)
        }
    }
    
    private func importSingleVideo(urlString: String, extractor: YouTubeKitExtractor) async throws {
        guard let videoID = await extractor.extractVideoID(from: urlString) else {
            throw YouTubeKitError.invalidURL
        }
        
        youtubeImportStatus = "Downloading audio..."
        
        let result = try await extractor.downloadAudio(
            videoID: videoID,
            quality: .high
        ) { [weak self] progress in
            Task { @MainActor in
                self?.youtubeDownloadProgress = progress
            }
        }
        
        youtubeImportStatus = "Processing..."
        
        let track = AudioTrack(
            title: result.title,
            artist: result.author ?? "Unknown Artist",
            album: result.album ?? "YouTube Downloads",
            duration: result.duration,
            fileURL: result.localURL,
            sourceType: .local
        )
        
        let enrichedTrack = await metadataService.enrichTrack(track)
        tracks.append(enrichedTrack)
        tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    
    private func importPlaylist(urlString: String, extractor: YouTubeKitExtractor) async throws {
        youtubeImportStatus = "Fetching playlist..."
        
        let videoIDs = await extractor.extractPlaylistVideoIDs(from: urlString)
        
        guard !videoIDs.isEmpty else {
            throw YouTubeKitError.extractionFailed("Could not extract videos from playlist")
        }
        
        var successCount = 0
        var failCount = 0
        
        for (index, videoID) in videoIDs.enumerated() {
            youtubeImportStatus = "Downloading \(index + 1)/\(videoIDs.count)..."
            youtubeDownloadProgress = Double(index) / Double(videoIDs.count)
            
            do {
                let result = try await extractor.downloadAudio(
                    videoID: videoID,
                    quality: .high
                ) { [weak self] progress in
                    Task { @MainActor in
                        let baseProgress = Double(index) / Double(videoIDs.count)
                        let itemProgress = progress / Double(videoIDs.count)
                        self?.youtubeDownloadProgress = baseProgress + itemProgress
                    }
                }
                
                let track = AudioTrack(
                    title: result.title,
                    artist: result.author ?? "Unknown Artist",
                    album: result.album ?? "YouTube Downloads",
                    duration: result.duration,
                    fileURL: result.localURL,
                    sourceType: .local
                )
                
                let enrichedTrack = await metadataService.enrichTrack(track)
                tracks.append(enrichedTrack)
                successCount += 1
            } catch {
                failCount += 1
                // Continue with next video
            }
        }
        
        tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        
        if failCount > 0 {
            setError("Imported \(successCount) tracks. \(failCount) failed.")
        }
    }
    
    // MARK: - Spotify Import
    
    /// Import from Spotify URL (track, playlist, or album)
    public func importFromSpotify(urlString: String) async throws {
        guard let extractor = spotifyExtractor else {
            throw SpotifyExtractionError.noYouTubeExtractor
        }
        
        spotifyDownloadProgress = 0
        spotifyImportStatus = "Analyzing URL..."
        
        defer {
            spotifyDownloadProgress = nil
            spotifyImportStatus = nil
        }
        
        let urlType = await extractor.parseURL(urlString)
        
        switch urlType {
        case .track(let id):
            try await importSpotifyTrack(id: id, extractor: extractor)
        case .playlist(let id):
            try await importSpotifyPlaylist(id: id, extractor: extractor)
        case .album(let id):
            try await importSpotifyAlbum(id: id, extractor: extractor)
        case .invalid:
            throw SpotifyExtractionError.invalidURL
        }
    }
    
    private func importSpotifyTrack(id: String, extractor: SpotifyExtractor) async throws {
        spotifyImportStatus = "Fetching track info..."
        
        let track = try await extractor.scrapeTrack(id: id)
        
        spotifyImportStatus = "Downloading: \(track.name)..."
        
        let result = try await extractor.downloadTrack(track) { [weak self] progress in
            Task { @MainActor in
                self?.spotifyDownloadProgress = progress
            }
        }
        
        spotifyImportStatus = "Processing..."
        
        let audioTrack = AudioTrack(
            title: result.title,
            artist: result.artist,
            album: result.album,
            duration: result.duration,
            fileURL: result.localURL,
            sourceType: .local
        )
        
        tracks.append(audioTrack)
        tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    
    private func importSpotifyPlaylist(id: String, extractor: SpotifyExtractor) async throws {
        spotifyImportStatus = "Fetching playlist..."
        
        let (playlistName, spotifyTracks) = try await extractor.scrapePlaylist(id: id)
        
        guard !spotifyTracks.isEmpty else {
            throw SpotifyExtractionError.extractionFailed("Playlist is empty")
        }
        
        var successCount = 0
        var failCount = 0
        
        for (index, track) in spotifyTracks.enumerated() {
            spotifyImportStatus = "Downloading \(index + 1)/\(spotifyTracks.count): \(track.name)"
            spotifyDownloadProgress = Double(index) / Double(spotifyTracks.count)
            
            do {
                let result = try await extractor.downloadTrack(track) { [weak self] progress in
                    Task { @MainActor in
                        let baseProgress = Double(index) / Double(spotifyTracks.count)
                        let itemProgress = progress / Double(spotifyTracks.count)
                        self?.spotifyDownloadProgress = baseProgress + itemProgress
                    }
                }
                
                let audioTrack = AudioTrack(
                    title: result.title,
                    artist: result.artist,
                    album: result.album,
                    duration: result.duration,
                    fileURL: result.localURL,
                    sourceType: .local
                )
                
                tracks.append(audioTrack)
                successCount += 1
            } catch {
                failCount += 1
                // Continue with next track
            }
        }
        
        tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        
        if failCount > 0 {
            setError("Imported \(successCount)/\(spotifyTracks.count) from '\(playlistName)'. \(failCount) failed.")
        }
    }
    
    private func importSpotifyAlbum(id: String, extractor: SpotifyExtractor) async throws {
        spotifyImportStatus = "Fetching album..."
        
        let (albumName, spotifyTracks) = try await extractor.scrapeAlbum(id: id)
        
        guard !spotifyTracks.isEmpty else {
            throw SpotifyExtractionError.extractionFailed("Album is empty")
        }
        
        var successCount = 0
        var failCount = 0
        
        for (index, track) in spotifyTracks.enumerated() {
            spotifyImportStatus = "Downloading \(index + 1)/\(spotifyTracks.count): \(track.name)"
            spotifyDownloadProgress = Double(index) / Double(spotifyTracks.count)
            
            do {
                let result = try await extractor.downloadTrack(track) { [weak self] progress in
                    Task { @MainActor in
                        let baseProgress = Double(index) / Double(spotifyTracks.count)
                        let itemProgress = progress / Double(spotifyTracks.count)
                        self?.spotifyDownloadProgress = baseProgress + itemProgress
                    }
                }
                
                let audioTrack = AudioTrack(
                    title: result.title,
                    artist: result.artist,
                    album: result.album,
                    duration: result.duration,
                    fileURL: result.localURL,
                    sourceType: .local
                )
                
                tracks.append(audioTrack)
                successCount += 1
            } catch {
                failCount += 1
                // Continue with next track
            }
        }
        
        tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        
        if failCount > 0 {
            setError("Imported \(successCount)/\(spotifyTracks.count) from '\(albumName)'. \(failCount) failed.")
        }
    }
    
    // MARK: - Music Thoughts
    
    /// Save a music thought to storage
    public func saveMusicThought(_ thought: String) {
        let trimmedThought = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedThought.isEmpty else { return }
        
        var thoughts = loadMusicThoughts()
        let newThought = MusicThought(
            id: UUID(),
            content: trimmedThought,
            date: Date(),
            trackTitle: currentTrack?.title,
            trackArtist: currentTrack?.artist
        )
        thoughts.insert(newThought, at: 0)
        
        if let data = try? JSONEncoder().encode(thoughts) {
            UserDefaults.standard.set(data, forKey: "musicThoughts")
        }
    }
    
    /// Load saved music thoughts
    public func loadMusicThoughts() -> [MusicThought] {
        guard let data = UserDefaults.standard.data(forKey: "musicThoughts"),
              let thoughts = try? JSONDecoder().decode([MusicThought].self, from: data) else {
            return []
        }
        return thoughts
    }
    
    /// Get thoughts for a specific track
    /// - Parameter track: The track to get thoughts for
    /// - Returns: Array of thoughts matching the track's title and artist
    public func getThoughtsForTrack(_ track: AudioTrack) -> [MusicThought] {
        let allThoughts = loadMusicThoughts()
        return allThoughts.filter { thought in
            thought.trackTitle == track.title &&
            thought.trackArtist == track.artist
        }
    }
    
    // MARK: - Album Art
    
    /// Set album art for a track
    public func setAlbumArt(for track: AudioTrack, imageData: Data) {
        let artworkDir = getDocumentsDirectory().appendingPathComponent("Artwork")
        
        do {
            try FileManager.default.createDirectory(at: artworkDir, withIntermediateDirectories: true)
            
            let filename = "\(track.id.uuidString).jpg"
            let artworkURL = artworkDir.appendingPathComponent(filename)
            
            try imageData.write(to: artworkURL)
            
            UserDefaults.standard.set(artworkURL.path, forKey: "artwork_\(track.id.uuidString)")
        } catch {
            setError("Failed to save album art: \(error.localizedDescription)")
        }
    }
    
    /// Get album art URL for a track
    public func getAlbumArtURL(for track: AudioTrack) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: "artwork_\(track.id.uuidString)") else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

// MARK: - Music Thought Model

public struct MusicThought: Codable, Identifiable {
    public let id: UUID
    public let content: String
    public let date: Date
    public let trackTitle: String?
    public let trackArtist: String?
}

// MARK: - AudioPlayerDelegate

extension MusicLibraryViewModel: AudioPlayerDelegate {
    nonisolated public func audioPlayer(_ player: AudioPlayer, didChangeState state: PlaybackState) {
        Task { @MainActor in
            self.isPlaying = state == .playing
            if state == .stopped {
                self.currentPlaybackTime = 0
            }
        }
    }
    
    nonisolated public func audioPlayer(_ player: AudioPlayer, didUpdateProgress currentTime: TimeInterval, duration: TimeInterval) {
        Task { @MainActor in
            self.currentPlaybackTime = currentTime
        }
    }
    
    nonisolated public func audioPlayer(_ player: AudioPlayer, didFinishPlaying track: AudioTrack) {
        Task { @MainActor in
            self.currentPlaybackTime = 0
            // Auto-play next track in queue if available
            if !self.playQueue.isEmpty {
                self.playNextInQueue()
            } else {
                self.isPlaying = false
            }
        }
    }
    
    nonisolated public func audioPlayer(_ player: AudioPlayer, didFailWithError error: Error) {
        Task { @MainActor in
            self.setError("Playback failed: \(error.localizedDescription)")
            self.isPlaying = false
        }
    }
}
