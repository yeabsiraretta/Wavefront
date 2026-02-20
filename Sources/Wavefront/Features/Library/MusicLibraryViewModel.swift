import Foundation
import Combine

/// View model for managing music library display
@MainActor
public final class MusicLibraryViewModel: ObservableObject {
    @Published public private(set) var tracks: [AudioTrack] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public var currentTrack: AudioTrack?
    @Published public var isPlaying = false
    @Published public var currentPlaybackTime: TimeInterval = 0
    @Published public var isEnrichingMetadata = false
    @Published public var youtubeDownloadProgress: Double?
    @Published public var youtubeImportStatus: String?
    
    private let sourceManager: AudioSourceManager
    private let player: AudioPlayer
    private let metadataService: MetadataService
    private let youtubeKitExtractor: YouTubeKitExtractor?
    
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
    
    /// Convenience initializer that creates default local source
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
        
        Task {
            await setupDefaultSources()
        }
    }
    
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
    
    /// Register an additional audio source
    public func addSource(_ source: any AudioSource) async {
        await sourceManager.register(source)
    }
    
    /// Refresh tracks from all sources
    public func refreshTracks() async {
        isLoading = true
        errorMessage = nil
        
        tracks = await sourceManager.fetchAllTracks()
        
        // Sort by title
        tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        
        isLoading = false
    }
    
    /// Play a specific track
    public func play(_ track: AudioTrack) {
        currentTrack = track
        isPlaying = true
        
        Task {
            await player.play(track)
        }
    }
    
    /// Toggle play/pause
    public func togglePlayPause() {
        player.togglePlayPause()
        isPlaying = player.isPlaying
    }
    
    /// Stop playback
    public func stop() {
        player.stop()
        isPlaying = false
        currentTrack = nil
    }
    
    /// Clear error message
    public func clearError() {
        errorMessage = nil
    }
    
    /// Set error message
    public func setError(_ message: String) {
        errorMessage = message
    }
    
    /// Delete a track from the library and file system
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
            self.isPlaying = false
            self.currentPlaybackTime = 0
        }
    }
    
    nonisolated public func audioPlayer(_ player: AudioPlayer, didFailWithError error: Error) {
        Task { @MainActor in
            self.setError("Playback failed: \(error.localizedDescription)")
            self.isPlaying = false
        }
    }
}
