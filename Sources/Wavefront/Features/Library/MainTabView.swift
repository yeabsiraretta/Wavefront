import SwiftUI

/**
 * Main tab-based navigation view for the Wavefront app.
 *
 * Provides the primary navigation structure with tabs for Songs,
 * Albums, Liked Songs, History, and Settings. Coordinates between
 * the shared ViewModel and UserLibrary.
 *
 * ## Tabs
 * - **Songs** - Full track library with search and import
 * - **Albums** - Tracks grouped by album
 * - **Liked** - User's liked/favorite songs
 * - **History** - Recently played tracks
 * - **Settings** - App configuration and audio sources
 *
 * ## Features
 * - Shared ViewModel across all tabs
 * - Automatic track refresh on launch
 * - Listening history recording
 * - Queue management with swipe gestures
 * - Shared play sessions
 *
 * ## Usage
 * ```swift
 * MainTabView()
 * ```
 */
@MainActor
public struct MainTabView: View {
    /// Shared ViewModel for all tabs
    @StateObject private var viewModel = MusicLibraryViewModel()
    
    /// Shared UserLibrary for liked songs and history
    @StateObject private var userLibrary = UserLibrary.shared
    
    /// Currently selected tab index
    @State private var selectedTab = 0
    
    /**
     * Creates a new MainTabView instance.
     */
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            MediaTab(viewModel: viewModel)
                .tabItem {
                    Label("Media", systemImage: "music.note.list")
                }
                .tag(0)
            
            LikedSongsTab(viewModel: viewModel, userLibrary: userLibrary)
                .tabItem {
                    Label("Liked", systemImage: "heart.fill")
                }
                .tag(1)
            
            HistoryTab(viewModel: viewModel, userLibrary: userLibrary)
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(2)
            
            SettingsTab(viewModel: viewModel)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .task {
            await viewModel.refreshTracks()
        }
        .onChange(of: viewModel.currentTrack) { newTrack in
            if let track = newTrack {
                userLibrary.recordPlay(track)
            }
        }
    }
}

// MARK: - Media Tab (Combined Songs & Albums)

/// Combined media tab with Songs and Albums selection
struct MediaTab: View {
    @ObservedObject var viewModel: MusicLibraryViewModel
    @State private var selectedMediaType: MediaType = .songs
    @State private var showingYouTubeSheet = false
    @State private var showingSpotifySheet = false
    @State private var showingThoughtsSheet = false
    @State private var showingAlbumArtSheet = false
    @State private var selectedTrackForArt: AudioTrack?
    @State private var selectedTrackForThoughts: AudioTrack?
    @State private var showingSharedPlaySheet = false
    @State private var showingTrackNotesSheet = false
    @State private var selectedTrackForNotes: AudioTrack?
    @State private var youtubeURL = ""
    @State private var spotifyURL = ""
    @State private var searchText = ""
    
    enum MediaType: String, CaseIterable {
        case songs = "Songs"
        case albums = "Albums"
    }
    
    var filteredTracks: [AudioTrack] {
        if searchText.isEmpty {
            return viewModel.tracks
        }
        return viewModel.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.artist?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.album?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var albums: [Album] {
        Album.groupTracks(viewModel.tracks)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Media type selector
                Picker("Media Type", selection: $selectedMediaType) {
                    ForEach(MediaType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content based on selection
                Group {
                    switch selectedMediaType {
                    case .songs:
                        songsContent
                    case .albums:
                        albumsContent
                    }
                }
            }
            .navigationTitle("Media")
            .searchable(text: $searchText, prompt: "Search music")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task { await viewModel.refreshTracks() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        
                        Button {
                            Task { await viewModel.enrichAllMetadata() }
                        } label: {
                            Label("Fetch Metadata", systemImage: "info.circle")
                        }
                        
                        Divider()
                        
                        Button {
                            showingYouTubeSheet = true
                        } label: {
                            Label("Import from YouTube", systemImage: "play.rectangle")
                        }
                        
                        Button {
                            showingSpotifySheet = true
                        } label: {
                            Label("Import from Spotify", systemImage: "music.note")
                        }
                        
                        Divider()
                        
                        Button {
                            showingSharedPlaySheet = true
                        } label: {
                            Label("Shared Play", systemImage: "person.2.wave.2")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.currentTrack != nil {
                    NowPlayingBar(
                        track: viewModel.currentTrack,
                        isPlaying: viewModel.isPlaying,
                        currentTime: viewModel.currentPlaybackTime,
                        onPlayPause: { viewModel.togglePlayPause() },
                        onStop: { viewModel.stop() }
                    )
                }
            }
        }
        .sheet(isPresented: $showingYouTubeSheet) {
            YouTubeImportSheet(
                url: $youtubeURL,
                isLoading: viewModel.youtubeDownloadProgress != nil,
                progress: viewModel.youtubeDownloadProgress,
                importStatus: viewModel.youtubeImportStatus,
                onImport: {
                    Task {
                        do {
                            try await viewModel.importFromYouTube(urlString: youtubeURL)
                            youtubeURL = ""
                            showingYouTubeSheet = false
                        } catch {
                            viewModel.setError("YouTube import failed: \(error.localizedDescription)")
                            showingYouTubeSheet = false
                        }
                    }
                },
                onCancel: {
                    showingYouTubeSheet = false
                    youtubeURL = ""
                }
            )
        }
        .sheet(isPresented: $showingSpotifySheet) {
            SpotifyImportSheet(
                url: $spotifyURL,
                isLoading: viewModel.spotifyDownloadProgress != nil,
                progress: viewModel.spotifyDownloadProgress,
                importStatus: viewModel.spotifyImportStatus,
                onImport: {
                    Task {
                        do {
                            try await viewModel.importFromSpotify(urlString: spotifyURL)
                            spotifyURL = ""
                            showingSpotifySheet = false
                        } catch {
                            viewModel.setError("Spotify import failed: \(error.localizedDescription)")
                            showingSpotifySheet = false
                        }
                    }
                },
                onCancel: {
                    showingSpotifySheet = false
                    spotifyURL = ""
                }
            )
        }
        .sheet(isPresented: $showingThoughtsSheet) {
            MusicThoughtsSheet(
                onSave: { thought in
                    viewModel.saveMusicThought(thought)
                    showingThoughtsSheet = false
                },
                onCancel: {
                    showingThoughtsSheet = false
                }
            )
        }
        .sheet(isPresented: $showingAlbumArtSheet) {
            if let track = selectedTrackForArt {
                AlbumArtSheet(
                    track: track,
                    onSave: { imageData in
                        viewModel.setAlbumArt(for: track, imageData: imageData)
                        showingAlbumArtSheet = false
                        selectedTrackForArt = nil
                    },
                    onCancel: {
                        showingAlbumArtSheet = false
                        selectedTrackForArt = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showingSharedPlaySheet) {
            SharedPlayView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingTrackNotesSheet) {
            if let track = selectedTrackForNotes {
                TrackNotesSheet(
                    track: track,
                    thoughts: viewModel.getThoughtsForTrack(track),
                    onDismiss: {
                        showingTrackNotesSheet = false
                        selectedTrackForNotes = nil
                    }
                )
            }
        }
        .alert("Notice", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    // MARK: - Songs Content
    
    @ViewBuilder
    private var songsContent: some View {
        if viewModel.isLoading {
            ProgressView("Loading music...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.tracks.isEmpty {
            EmptyLibraryView()
        } else {
            List(filteredTracks) { track in
                TrackRow(
                    track: track,
                    isPlaying: viewModel.currentTrack?.id == track.id,
                    isLiked: UserLibrary.shared.isLiked(track),
                    onLike: { UserLibrary.shared.toggleLike(track) },
                    onDelete: { viewModel.deleteTrack(track) }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.play(track)
                }
                .contextMenu {
                    if viewModel.isInQueue(track) {
                        Button {
                            viewModel.removeFromQueue(track)
                        } label: {
                            Label("Remove from Queue", systemImage: "minus.circle")
                        }
                    } else {
                        Button {
                            viewModel.addToQueue(track)
                        } label: {
                            Label("Add to Queue", systemImage: "text.badge.plus")
                        }
                    }
                    
                    Divider()
                    
                    Button {
                        selectedTrackForThoughts = track
                        showingThoughtsSheet = true
                    } label: {
                        Label("Write Thoughts", systemImage: "pencil.and.scribble")
                    }
                    
                    Button {
                        selectedTrackForNotes = track
                        showingTrackNotesSheet = true
                    } label: {
                        let noteCount = viewModel.getThoughtsForTrack(track).count
                        Label("View Notes (\(noteCount))", systemImage: "note.text")
                    }
                    
                    Button {
                        selectedTrackForArt = track
                        showingAlbumArtSheet = true
                    } label: {
                        Label("Set Album Art", systemImage: "photo")
                    }
                    
                    Button {
                        UserLibrary.shared.toggleLike(track)
                    } label: {
                        Label(
                            UserLibrary.shared.isLiked(track) ? "Unlike" : "Like",
                            systemImage: UserLibrary.shared.isLiked(track) ? "heart.slash" : "heart"
                        )
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        viewModel.deleteTrack(track)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteTrack(track)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if viewModel.isInQueue(track) {
                        Button {
                            viewModel.removeFromQueue(track)
                        } label: {
                            Label("Unqueue", systemImage: "minus.circle")
                        }
                        .tint(.orange)
                    } else {
                        Button {
                            viewModel.addToQueue(track)
                        } label: {
                            Label("Queue", systemImage: "text.badge.plus")
                        }
                        .tint(.blue)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
    
    // MARK: - Albums Content
    
    @ViewBuilder
    private var albumsContent: some View {
        if viewModel.isLoading {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if albums.isEmpty {
            EmptyStateView(
                title: "No Albums",
                systemImage: "square.stack",
                description: "Import music to see albums here."
            )
        } else {
            List(albums) { album in
                NavigationLink(destination: AlbumDetailView(album: album, viewModel: viewModel)) {
                    AlbumRow(album: album)
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Songs Tab (Legacy - kept for compatibility)

struct SongsTab: View {
    @ObservedObject var viewModel: MusicLibraryViewModel
    @State private var showingYouTubeSheet = false
    @State private var showingSpotifySheet = false
    @State private var showingThoughtsSheet = false
    @State private var showingAlbumArtSheet = false
    @State private var selectedTrackForArt: AudioTrack?
    @State private var selectedTrackForThoughts: AudioTrack?
    @State private var showingSharedPlaySheet = false
    @State private var showingTrackNotesSheet = false
    @State private var selectedTrackForNotes: AudioTrack?
    @State private var youtubeURL = ""
    @State private var spotifyURL = ""
    @State private var searchText = ""
    
    var filteredTracks: [AudioTrack] {
        if searchText.isEmpty {
            return viewModel.tracks
        }
        return viewModel.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.artist?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.album?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading music...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.tracks.isEmpty {
                    EmptyLibraryView()
                } else {
                    List(filteredTracks) { track in
                        TrackRow(
                            track: track,
                            isPlaying: viewModel.currentTrack?.id == track.id,
                            isLiked: UserLibrary.shared.isLiked(track),
                            onLike: { UserLibrary.shared.toggleLike(track) },
                            onDelete: { viewModel.deleteTrack(track) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.play(track)
                        }
                        .onLongPressGesture(minimumDuration: 1.0) {
                            selectedTrackForThoughts = track
                            showingThoughtsSheet = true
                        }
                        .contextMenu {
                            // Queue actions
                            if viewModel.isInQueue(track) {
                                Button {
                                    viewModel.removeFromQueue(track)
                                } label: {
                                    Label("Remove from Queue", systemImage: "minus.circle")
                                }
                            } else {
                                Button {
                                    viewModel.addToQueue(track)
                                } label: {
                                    Label("Add to Queue", systemImage: "text.badge.plus")
                                }
                            }
                            
                            Divider()
                            
                            Button {
                                selectedTrackForThoughts = track
                                showingThoughtsSheet = true
                            } label: {
                                Label("Write Thoughts", systemImage: "pencil.and.scribble")
                            }
                            
                            Button {
                                selectedTrackForNotes = track
                                showingTrackNotesSheet = true
                            } label: {
                                let noteCount = viewModel.getThoughtsForTrack(track).count
                                Label("View Notes (\(noteCount))", systemImage: "note.text")
                            }
                            
                            Button {
                                selectedTrackForArt = track
                                showingAlbumArtSheet = true
                            } label: {
                                Label("Set Album Art", systemImage: "photo")
                            }
                            
                            Button {
                                UserLibrary.shared.toggleLike(track)
                            } label: {
                                Label(
                                    UserLibrary.shared.isLiked(track) ? "Unlike" : "Like",
                                    systemImage: UserLibrary.shared.isLiked(track) ? "heart.slash" : "heart"
                                )
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                viewModel.deleteTrack(track)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteTrack(track)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if viewModel.isInQueue(track) {
                                Button {
                                    viewModel.removeFromQueue(track)
                                } label: {
                                    Label("Unqueue", systemImage: "minus.circle")
                                }
                                .tint(.orange)
                            } else {
                                Button {
                                    viewModel.addToQueue(track)
                                } label: {
                                    Label("Queue", systemImage: "text.badge.plus")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Search songs")
                }
            }
            .navigationTitle("Songs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task { await viewModel.refreshTracks() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        
                        Button {
                            Task { await viewModel.enrichAllMetadata() }
                        } label: {
                            Label("Fetch Metadata", systemImage: "info.circle")
                        }
                        .disabled(viewModel.tracks.isEmpty || viewModel.isEnrichingMetadata)
                        
                        Divider()
                        
                        Button {
                            showingYouTubeSheet = true
                        } label: {
                            Label("Import from YouTube", systemImage: "play.rectangle")
                        }
                        
                        Button {
                            showingSpotifySheet = true
                        } label: {
                            Label("Import from Spotify", systemImage: "music.note")
                        }
                        
                        Divider()
                        
                        Button {
                            showingThoughtsSheet = true
                        } label: {
                            Label("Music Thoughts", systemImage: "pencil.and.scribble")
                        }
                        
                        Button {
                            showingSharedPlaySheet = true
                        } label: {
                            Label("Shared Play", systemImage: "airplayaudio")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.currentTrack != nil {
                    NowPlayingBar(
                        track: viewModel.currentTrack,
                        isPlaying: viewModel.isPlaying,
                        currentTime: viewModel.currentPlaybackTime,
                        onPlayPause: { viewModel.togglePlayPause() },
                        onStop: { viewModel.stop() }
                    )
                }
            }
        }
        .sheet(isPresented: $showingYouTubeSheet) {
            YouTubeImportSheet(
                url: $youtubeURL,
                isLoading: viewModel.youtubeDownloadProgress != nil,
                progress: viewModel.youtubeDownloadProgress,
                importStatus: viewModel.youtubeImportStatus,
                onImport: {
                    Task {
                        do {
                            try await viewModel.importFromYouTube(urlString: youtubeURL)
                            youtubeURL = ""
                            showingYouTubeSheet = false
                        } catch {
                            viewModel.setError("Import failed: \(error.localizedDescription)")
                            showingYouTubeSheet = false
                        }
                    }
                },
                onCancel: {
                    showingYouTubeSheet = false
                    youtubeURL = ""
                }
            )
        }
        .sheet(isPresented: $showingSpotifySheet) {
            SpotifyImportSheet(
                url: $spotifyURL,
                isLoading: viewModel.spotifyDownloadProgress != nil,
                progress: viewModel.spotifyDownloadProgress,
                importStatus: viewModel.spotifyImportStatus,
                onImport: {
                    Task {
                        do {
                            try await viewModel.importFromSpotify(urlString: spotifyURL)
                            spotifyURL = ""
                            showingSpotifySheet = false
                        } catch {
                            viewModel.setError("Spotify import failed: \(error.localizedDescription)")
                            showingSpotifySheet = false
                        }
                    }
                },
                onCancel: {
                    showingSpotifySheet = false
                    spotifyURL = ""
                }
            )
        }
        .sheet(isPresented: $showingThoughtsSheet) {
            MusicThoughtsSheet(
                onSave: { thought in
                    viewModel.saveMusicThought(thought)
                    showingThoughtsSheet = false
                },
                onCancel: {
                    showingThoughtsSheet = false
                }
            )
        }
        .sheet(isPresented: $showingAlbumArtSheet) {
            if let track = selectedTrackForArt {
                AlbumArtSheet(
                    track: track,
                    onSave: { imageData in
                        viewModel.setAlbumArt(for: track, imageData: imageData)
                        showingAlbumArtSheet = false
                        selectedTrackForArt = nil
                    },
                    onCancel: {
                        showingAlbumArtSheet = false
                        selectedTrackForArt = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showingSharedPlaySheet) {
            SharedPlayView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingTrackNotesSheet) {
            if let track = selectedTrackForNotes {
                TrackNotesSheet(
                    track: track,
                    thoughts: viewModel.getThoughtsForTrack(track),
                    onDismiss: {
                        showingTrackNotesSheet = false
                        selectedTrackForNotes = nil
                    }
                )
            }
        }
        .alert("Notice", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

// MARK: - Albums Tab

struct AlbumsTab: View {
    @ObservedObject var viewModel: MusicLibraryViewModel
    
    var albums: [Album] {
        Album.groupTracks(viewModel.tracks)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if albums.isEmpty {
                    EmptyStateView(
                        title: "No Albums",
                        systemImage: "square.stack",
                        description: "Import music to see albums here."
                    )
                } else {
                    List(albums) { album in
                        NavigationLink(destination: AlbumDetailView(album: album, viewModel: viewModel)) {
                            AlbumRow(album: album)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Albums")
            .safeAreaInset(edge: .bottom) {
                if viewModel.currentTrack != nil {
                    NowPlayingBar(
                        track: viewModel.currentTrack,
                        isPlaying: viewModel.isPlaying,
                        currentTime: viewModel.currentPlaybackTime,
                        onPlayPause: { viewModel.togglePlayPause() },
                        onStop: { viewModel.stop() }
                    )
                }
            }
        }
    }
}

struct AlbumRow: View {
    let album: Album
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(album.artist ?? "Unknown Artist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Text("\(album.tracks.count) song\(album.tracks.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AlbumDetailView: View {
    let album: Album
    @ObservedObject var viewModel: MusicLibraryViewModel
    
    var body: some View {
        List(album.tracks) { track in
            TrackRow(
                track: track,
                isPlaying: viewModel.currentTrack?.id == track.id,
                isLiked: UserLibrary.shared.isLiked(track),
                onLike: { UserLibrary.shared.toggleLike(track) },
                onDelete: { viewModel.deleteTrack(track) }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.play(track)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    viewModel.deleteTrack(track)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(album.name)
        .safeAreaInset(edge: .bottom) {
            if viewModel.currentTrack != nil {
                NowPlayingBar(
                    track: viewModel.currentTrack,
                    isPlaying: viewModel.isPlaying,
                    currentTime: viewModel.currentPlaybackTime,
                    onPlayPause: { viewModel.togglePlayPause() },
                    onStop: { viewModel.stop() }
                )
            }
        }
    }
}

// MARK: - Liked Songs Tab

struct LikedSongsTab: View {
    @ObservedObject var viewModel: MusicLibraryViewModel
    @ObservedObject var userLibrary: UserLibrary
    
    var likedTracks: [AudioTrack] {
        userLibrary.getLikedTracks(from: viewModel.tracks)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if likedTracks.isEmpty {
                    EmptyStateView(
                        title: "No Liked Songs",
                        systemImage: "heart",
                        description: "Songs you like will appear here.\nTap the heart icon on any song to add it."
                    )
                } else {
                    List(likedTracks) { track in
                        TrackRow(
                            track: track,
                            isPlaying: viewModel.currentTrack?.id == track.id,
                            isLiked: true,
                            onLike: { userLibrary.toggleLike(track) },
                            onDelete: { viewModel.deleteTrack(track) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.play(track)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteTrack(track)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Liked Songs")
            .safeAreaInset(edge: .bottom) {
                if viewModel.currentTrack != nil {
                    NowPlayingBar(
                        track: viewModel.currentTrack,
                        isPlaying: viewModel.isPlaying,
                        currentTime: viewModel.currentPlaybackTime,
                        onPlayPause: { viewModel.togglePlayPause() },
                        onStop: { viewModel.stop() }
                    )
                }
            }
        }
    }
}

// MARK: - History Tab

struct HistoryTab: View {
    @ObservedObject var viewModel: MusicLibraryViewModel
    @ObservedObject var userLibrary: UserLibrary
    
    var body: some View {
        NavigationStack {
            Group {
                if userLibrary.listeningHistory.isEmpty {
                    EmptyStateView(
                        title: "No Listening History",
                        systemImage: "clock",
                        description: "Your recently played songs will appear here."
                    )
                } else {
                    List(userLibrary.listeningHistory) { entry in
                        HistoryRow(entry: entry, allTracks: viewModel.tracks) {
                            if let track = viewModel.tracks.first(where: { $0.id == entry.trackID }) {
                                viewModel.play(track)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !userLibrary.listeningHistory.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear") {
                            userLibrary.clearHistory()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.currentTrack != nil {
                    NowPlayingBar(
                        track: viewModel.currentTrack,
                        isPlaying: viewModel.isPlaying,
                        currentTime: viewModel.currentPlaybackTime,
                        onPlayPause: { viewModel.togglePlayPause() },
                        onStop: { viewModel.stop() }
                    )
                }
            }
        }
    }
}

struct HistoryRow: View {
    let entry: ListeningHistoryEntry
    let allTracks: [AudioTrack]
    let onTap: () -> Void
    
    private var isTrackAvailable: Bool {
        allTracks.contains { $0.id == entry.trackID }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.trackTitle)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundStyle(isTrackAvailable ? .primary : .secondary)
                    
                    Text(entry.artist ?? "Unknown Artist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Text(entry.playedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
            }
        }
        .disabled(!isTrackAvailable)
        .padding(.vertical, 4)
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    @ObservedObject var viewModel: MusicLibraryViewModel
    @State private var showingSourcesSheet = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    Button {
                        showingSourcesSheet = true
                    } label: {
                        Label("Manage Sources", systemImage: "folder.badge.gearshape")
                    }
                    
                    HStack {
                        Label("Total Songs", systemImage: "music.note")
                        Spacer()
                        Text("\(viewModel.tracks.count)")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label("Albums", systemImage: "square.stack")
                        Spacer()
                        Text("\(Album.groupTracks(viewModel.tracks).count)")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Playback") {
                    HStack {
                        Label("Audio Quality", systemImage: "waveform")
                        Spacer()
                        Text("High")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com")!) {
                        Label("GitHub", systemImage: "link")
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .sheet(isPresented: $showingSourcesSheet) {
            SourcesSettingsView(viewModel: viewModel)
        }
    }
}

// MARK: - Empty State View (cross-platform)

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

