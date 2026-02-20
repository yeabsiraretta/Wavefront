import SwiftUI

/// Main tab-based navigation view
@MainActor
public struct MainTabView: View {
    @StateObject private var viewModel = MusicLibraryViewModel()
    @StateObject private var userLibrary = UserLibrary.shared
    @State private var selectedTab = 0
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            SongsTab(viewModel: viewModel)
                .tabItem {
                    Label("Songs", systemImage: "music.note.list")
                }
                .tag(0)
            
            AlbumsTab(viewModel: viewModel)
                .tabItem {
                    Label("Albums", systemImage: "square.stack")
                }
                .tag(1)
            
            LikedSongsTab(viewModel: viewModel, userLibrary: userLibrary)
                .tabItem {
                    Label("Liked", systemImage: "heart.fill")
                }
                .tag(2)
            
            HistoryTab(viewModel: viewModel, userLibrary: userLibrary)
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(3)
            
            SettingsTab(viewModel: viewModel)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(4)
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

// MARK: - Songs Tab

struct SongsTab: View {
    @ObservedObject var viewModel: MusicLibraryViewModel
    @State private var showingYouTubeSheet = false
    @State private var youtubeURL = ""
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteTrack(track)
                            } label: {
                                Label("Delete", systemImage: "trash")
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

