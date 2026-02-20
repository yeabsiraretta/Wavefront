import SwiftUI

/// Main view displaying the music library
@MainActor
public struct MusicLibraryView: View {
    @StateObject private var viewModel = MusicLibraryViewModel()
    @State private var showingYouTubeSheet = false
    @State private var showingSourcesSheet = false
    @State private var youtubeURL = ""
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading music...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.tracks.isEmpty {
                    EmptyLibraryView()
                } else {
                    TrackListView(
                        tracks: viewModel.tracks,
                        currentTrack: viewModel.currentTrack,
                        isEnrichingMetadata: viewModel.isEnrichingMetadata,
                        onTrackTap: { track in
                            viewModel.play(track)
                        }
                    )
                }
            }
            .navigationTitle("Wavefront")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showingSourcesSheet = true
                    } label: {
                        Image(systemName: "server.rack")
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task {
                                await viewModel.refreshTracks()
                            }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        
                        Button {
                            Task {
                                await viewModel.enrichAllMetadata()
                            }
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
                VStack(spacing: 0) {
                    if viewModel.isEnrichingMetadata {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Fetching metadata...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    
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
        .task {
            await viewModel.refreshTracks()
        }
        .alert("Notice", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { Task { @MainActor in viewModel.clearError() } } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
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
                            // Error handled by viewModel
                        }
                    }
                },
                onCancel: {
                    showingYouTubeSheet = false
                    youtubeURL = ""
                }
            )
        }
        .sheet(isPresented: $showingSourcesSheet) {
            SourcesSettingsView(viewModel: viewModel)
        }
    }
}

/// View shown when library is empty
struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No Music")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Add music files to your Documents folder or connect an SMB share.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// List of tracks
struct TrackListView: View {
    let tracks: [AudioTrack]
    let currentTrack: AudioTrack?
    let isEnrichingMetadata: Bool
    let onTrackTap: (AudioTrack) -> Void
    
    var body: some View {
        List(tracks) { track in
            TrackRow(
                track: track,
                isPlaying: currentTrack?.id == track.id
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onTrackTap(track)
            }
        }
        .listStyle(.plain)
        .disabled(isEnrichingMetadata)
        .opacity(isEnrichingMetadata ? 0.6 : 1.0)
    }
}

/// Single track row
struct TrackRow: View {
    let track: AudioTrack
    let isPlaying: Bool
    var isLiked: Bool = false
    var onLike: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            // Album art placeholder
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay {
                    Image(systemName: isPlaying ? "waveform" : "music.note")
                        .foregroundStyle(isPlaying ? .blue : .secondary)
                }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.body)
                    .fontWeight(isPlaying ? .semibold : .regular)
                    .foregroundStyle(isPlaying ? .blue : .primary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(track.artist ?? "Unknown Artist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    if let duration = track.duration {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(formatDuration(duration))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Like button
            if let onLike = onLike {
                Button {
                    onLike()
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(isLiked ? .red : .secondary)
                }
                .buttonStyle(.borderless)
            }
            
            // Source indicator
            Image(systemName: track.sourceType == .local ? "iphone" : "server.rack")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            if let onLike = onLike {
                Button {
                    onLike()
                } label: {
                    Label(isLiked ? "Unlike" : "Like", systemImage: isLiked ? "heart.slash" : "heart")
                }
            }
            
            if let onDelete = onDelete {
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

/// Now playing bar at bottom - tappable to expand
struct NowPlayingBar: View {
    let track: AudioTrack?
    let isPlaying: Bool
    let currentTime: TimeInterval
    let onPlayPause: () -> Void
    let onStop: () -> Void
    @State private var showingExpandedPlayer = false
    @ObservedObject private var userLibrary = UserLibrary.shared
    
    var body: some View {
        if let track = track {
            HStack(spacing: 12) {
                // Album artwork placeholder
                AlbumArtworkView(track: track, size: 44)
                
                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Text(track.artist ?? "Unknown Artist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Controls
                HStack(spacing: 16) {
                    Button(action: onPlayPause) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }
                    
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                showingExpandedPlayer = true
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showingExpandedPlayer) {
                ExpandedPlayerView(
                    track: track,
                    isPlaying: isPlaying,
                    currentTime: currentTime,
                    isLiked: userLibrary.isLiked(track),
                    onPlayPause: onPlayPause,
                    onStop: onStop,
                    onLike: { userLibrary.toggleLike(track) },
                    onDismiss: { showingExpandedPlayer = false }
                )
            }
            #else
            .sheet(isPresented: $showingExpandedPlayer) {
                ExpandedPlayerView(
                    track: track,
                    isPlaying: isPlaying,
                    currentTime: currentTime,
                    isLiked: userLibrary.isLiked(track),
                    onPlayPause: onPlayPause,
                    onStop: onStop,
                    onLike: { userLibrary.toggleLike(track) },
                    onDismiss: { showingExpandedPlayer = false }
                )
                .frame(minWidth: 400, minHeight: 600)
            }
            #endif
        }
    }
}

/// Expanded full-screen player view
struct ExpandedPlayerView: View {
    let track: AudioTrack
    let isPlaying: Bool
    let currentTime: TimeInterval
    let isLiked: Bool
    let onPlayPause: () -> Void
    let onStop: () -> Void
    let onLike: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                // Large album artwork
                AlbumArtworkView(track: track, size: 280)
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                
                // Track info
                VStack(spacing: 8) {
                    Text(track.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    
                    Text(track.artist ?? "Unknown Artist")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    
                    if let album = track.album {
                        Text(album)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal)
                
                // Progress bar
                VStack(spacing: 8) {
                    ProgressView(value: progressValue, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.primary)
                    
                    HStack {
                        Text(formatTime(currentTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text(formatTime(track.duration ?? 0))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 32)
                
                // Main controls
                HStack(spacing: 48) {
                    // Like button
                    Button(action: onLike) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundStyle(isLiked ? .red : .primary)
                    }
                    
                    // Stop button
                    Button(action: onStop) {
                        Image(systemName: "backward.end.fill")
                            .font(.title)
                    }
                    
                    // Play/Pause button
                    Button(action: onPlayPause) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 72))
                    }
                    
                    // Forward button (placeholder)
                    Button(action: {}) {
                        Image(systemName: "forward.end.fill")
                            .font(.title)
                    }
                    .disabled(true)
                    .opacity(0.3)
                    
                    // Stop button
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.title2)
                    }
                }
                .padding(.vertical)
                
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.down")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }
    
    private var progressValue: Double {
        guard let duration = track.duration, duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Album artwork view with placeholder
struct AlbumArtworkView: View {
    let track: AudioTrack
    let size: CGFloat
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.1)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "music.note")
                .font(.system(size: size * 0.3))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.1))
    }
    
    private var gradientColors: [Color] {
        // Generate consistent colors based on track title
        let hash = abs(track.title.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = Double((hash / 360) % 360) / 360.0
        return [
            Color(hue: hue1, saturation: 0.6, brightness: 0.7),
            Color(hue: hue2, saturation: 0.7, brightness: 0.5)
        ]
    }
}

/// Sheet for importing from YouTube
struct YouTubeImportSheet: View {
    @Binding var url: String
    let isLoading: Bool
    let progress: Double?
    let importStatus: String?
    let onImport: () -> Void
    let onCancel: () -> Void
    
    private var isPlaylistURL: Bool {
        url.contains("list=") || url.contains("/playlist")
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: isPlaylistURL ? "music.note.list" : "play.rectangle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.red)
                
                Text(isPlaylistURL ? "Import Playlist" : "Import from YouTube")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(isPlaylistURL 
                     ? "Import all tracks from a YouTube playlist."
                     : "Paste a YouTube URL to import the audio track.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                TextField("https://youtube.com/watch?v=... or playlist URL", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                
                if isLoading {
                    VStack(spacing: 12) {
                        if let progress = progress {
                            ProgressView(value: progress, total: 1.0) {
                                Text(importStatus ?? "Downloading...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .progressViewStyle(.linear)
                            
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView(importStatus ?? "Preparing...")
                        }
                    }
                } else {
                    Button(action: onImport) {
                        Text(isPlaylistURL ? "Import Playlist" : "Import")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(url.isEmpty)
                }
                
                Spacer()
            }
            .padding()
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isLoading)
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isLoading)
    }
}
