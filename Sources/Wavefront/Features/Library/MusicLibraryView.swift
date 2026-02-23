import SwiftUI
#if os(iOS)
import UIKit
#endif

/**
 * Main view displaying the music library.
 *
 * This is the primary entry point view for the Wavefront music app.
 * It displays the user's music library with playback controls,
 * import options, and metadata enrichment features.
 *
 * ## Features
 * - Track list with playback controls
 * - YouTube and Spotify import sheets
 * - Metadata enrichment from external APIs
 * - Audio source management
 * - Now playing bar with playback controls
 *
 * ## Usage
 * ```swift
 * MusicLibraryView()
 * ```
 */
@MainActor
public struct MusicLibraryView: View {
    /// ViewModel managing library state and operations
    @StateObject private var viewModel = MusicLibraryViewModel()
    
    /// Controls YouTube import sheet visibility
    @State private var showingYouTubeSheet = false
    
    /// Controls audio sources sheet visibility
    @State private var showingSourcesSheet = false
    
    /// URL input for YouTube import
    @State private var youtubeURL = ""
    
    /**
     * Creates a new MusicLibraryView instance.
     */
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

/// Expanded full-screen player view with swipeable pages
struct ExpandedPlayerView: View {
    let track: AudioTrack
    let isPlaying: Bool
    let currentTime: TimeInterval
    let isLiked: Bool
    let onPlayPause: () -> Void
    let onStop: () -> Void
    let onLike: () -> Void
    let onDismiss: () -> Void
    
    @State private var selectedPage = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(selectedPage == index ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 8)
                
                // Swipeable pages
                TabView(selection: $selectedPage) {
                    // Page 0: Main player
                    MainPlayerPage(
                        track: track,
                        isPlaying: isPlaying,
                        currentTime: currentTime,
                        isLiked: isLiked,
                        onPlayPause: onPlayPause,
                        onStop: onStop,
                        onLike: onLike
                    )
                    .tag(0)
                    
                    // Page 1: Waveform
                    WaveformPage(track: track, currentTime: currentTime, isPlaying: isPlaying)
                        .tag(1)
                    
                    // Page 2: Lyrics
                    LyricsPage(track: track)
                        .tag(2)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
            }
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
}

/// Main player page with album art and controls
private struct MainPlayerPage: View {
    let track: AudioTrack
    let isPlaying: Bool
    let currentTime: TimeInterval
    let isLiked: Bool
    let onPlayPause: () -> Void
    let onStop: () -> Void
    let onLike: () -> Void
    
    var body: some View {
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
            HStack(spacing: 24) {
                Button(action: onLike) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundStyle(isLiked ? .red : .primary)
                }
                
                Button(action: onStop) {
                    Image(systemName: "backward.end.fill")
                        .font(.title)
                }
                .padding(.leading, 8)
                
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                }
                .padding(.horizontal, 16)
                
                Button(action: {}) {
                    Image(systemName: "forward.end.fill")
                        .font(.title)
                }
                .disabled(true)
                .opacity(0.3)
                .padding(.trailing, 8)
                
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                }
            }
            .padding(.vertical)
            
            Spacer()
        }
        .padding()
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

/// Waveform visualization page
private struct WaveformPage: View {
    let track: AudioTrack
    let currentTime: TimeInterval
    let isPlaying: Bool
    
    @State private var waveformBars: [CGFloat] = []
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Track info header
            VStack(spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(track.artist ?? "Unknown Artist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Waveform visualization
            GeometryReader { geometry in
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<waveformBars.count, id: \.self) { index in
                        WaveformBar(
                            height: waveformBars[index],
                            isPlayed: isBarPlayed(index: index),
                            isPlaying: isPlaying
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
                .onAppear {
                    generateWaveform(width: geometry.size.width)
                }
            }
            .frame(height: 200)
            .padding(.horizontal, 24)
            
            // Time display
            HStack {
                Text(formatTime(currentTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(formatTime(track.duration ?? 0))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            
            Text("Waveform")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            Spacer()
        }
        .padding()
    }
    
    private func generateWaveform(width: CGFloat) {
        let barCount = Int(width / 6)
        let seed = track.title.hashValue
        var bars: [CGFloat] = []
        
        for i in 0..<barCount {
            let random = abs((seed + i * 31) % 100)
            let height = CGFloat(30 + random % 70) / 100.0
            bars.append(height)
        }
        
        waveformBars = bars
    }
    
    private func isBarPlayed(index: Int) -> Bool {
        guard let duration = track.duration, duration > 0 else { return false }
        let progress = currentTime / duration
        let barProgress = Double(index) / Double(waveformBars.count)
        return barProgress <= progress
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Individual waveform bar
private struct WaveformBar: View {
    let height: CGFloat
    let isPlayed: Bool
    let isPlaying: Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isPlayed ? Color.accentColor : Color.secondary.opacity(0.3))
            .frame(width: 4, height: 200 * height)
            .animation(.easeInOut(duration: 0.1), value: isPlayed)
    }
}

/// Lyrics page with placeholder
private struct LyricsPage: View {
    let track: AudioTrack
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Track info header
            VStack(spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(track.artist ?? "Unknown Artist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Lyrics content or placeholder
            if let lyrics = track.lyrics, !lyrics.isEmpty {
                ScrollView {
                    Text(lyrics)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                    
                    Text("No lyrics.")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Text("Lyrics")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            Spacer()
        }
        .padding()
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

/// Sheet for importing from Spotify (uses local web scraping - no API needed)
struct SpotifyImportSheet: View {
    @Binding var url: String
    let isLoading: Bool
    let progress: Double?
    let importStatus: String?
    let onImport: () -> Void
    let onCancel: () -> Void
    
    private var urlType: String {
        if url.contains("/playlist") || url.contains(":playlist:") {
            return "playlist"
        } else if url.contains("/album") || url.contains(":album:") {
            return "album"
        } else if url.contains("/track") || url.contains(":track:") {
            return "track"
        }
        return "content"
    }
    
    private var iconName: String {
        switch urlType {
        case "playlist": return "music.note.list"
        case "album": return "square.stack"
        case "track": return "music.note"
        default: return "music.note"
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: iconName)
                    .font(.system(size: 50))
                    .foregroundStyle(.green)
                
                Text("Import from Spotify")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Paste a Spotify link to import tracks, playlists, or albums.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                TextField("https://open.spotify.com/track/...", text: $url)
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
                            .tint(.green)
                            
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView(importStatus ?? "Preparing...")
                        }
                    }
                } else {
                    Button(action: onImport) {
                        Text("Import \(urlType.capitalized)")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
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

// MARK: - Music Thoughts Sheet

/// Sheet for writing thoughts about music
struct MusicThoughtsSheet: View {
    @State private var thoughtText = ""
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 50))
                    .foregroundStyle(.purple)
                
                Text("Music Thoughts")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Write down your thoughts about the music you've been listening to.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                TextEditor(text: $thoughtText)
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                
                Button {
                    onSave(thoughtText)
                } label: {
                    Text("Save Thought")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(thoughtText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                
                Spacer()
            }
            .padding()
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Track Notes Sheet

/// Sheet for viewing all notes/thoughts for a specific track
struct TrackNotesSheet: View {
    let track: AudioTrack
    let thoughts: [MusicThought]
    let onDismiss: () -> Void
    
    @State private var expandedNoteId: UUID?
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// Thoughts sorted in reverse chronological order (newest first)
    private var sortedThoughts: [MusicThought] {
        thoughts.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if thoughts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "note.text")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                        
                        Text("No Notes Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Long press on this track and select \"Write Thoughts\" to add your first note.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(sortedThoughts) { thought in
                            NoteRow(
                                thought: thought,
                                isExpanded: expandedNoteId == thought.id,
                                dateFormatter: dateFormatter,
                                onTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedNoteId == thought.id {
                                            expandedNoteId = nil
                                        } else {
                                            expandedNoteId = thought.id
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Notes for \(track.title)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Individual note row with tap-to-expand functionality
private struct NoteRow: View {
    let thought: MusicThought
    let isExpanded: Bool
    let dateFormatter: DateFormatter
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Date header
                HStack {
                    Image(systemName: "note.text")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    
                    Text(dateFormatter.string(from: thought.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                // Content preview or full content
                Text(thought.content)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 2)
                    .multilineTextAlignment(.leading)
                
                // Show relative time when expanded
                if isExpanded {
                    Text(relativeTimeString(from: thought.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Album Art Sheet

#if os(iOS)
/// Sheet for setting album art via camera or search
struct AlbumArtSheet: View {
    let track: AudioTrack
    let onSave: (Data) -> Void
    let onCancel: () -> Void
    
    @State private var selectedTab = 0
    @State private var searchQuery = ""
    @State private var searchResults: [CoverSearchResult] = []
    @State private var isSearching = false
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 60, height: 60)
                        .overlay {
                            if let image = capturedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "music.note")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(track.artist ?? "Unknown Artist")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                
                Picker("Method", selection: $selectedTab) {
                    Text("Camera").tag(0)
                    Text("Search").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                if selectedTab == 0 {
                    cameraView
                } else {
                    searchView
                }
                
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Set Album Art")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let image = capturedImage,
                           let data = image.jpegData(compressionQuality: 0.8) {
                            onSave(data)
                        }
                    }
                    .disabled(capturedImage == nil)
                }
            }
            .sheet(isPresented: $showingCamera) {
                ImagePicker(image: $capturedImage, sourceType: .camera)
            }
        }
        .presentationDetents([.large])
        .onAppear {
            searchQuery = "\(track.title) \(track.artist ?? "") album cover"
        }
    }
    
    private var cameraView: some View {
        VStack(spacing: 20) {
            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Button {
                    showingCamera = true
                } label: {
                    Label("Retake Photo", systemImage: "camera")
                }
                .buttonStyle(.bordered)
            } else {
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                
                Text("Take a photo to use as album art")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Button {
                    showingCamera = true
                } label: {
                    Label("Open Camera", systemImage: "camera")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
            }
        }
        .padding()
    }
    
    private var searchView: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search for album covers...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                
                Button {
                    Task {
                        await searchCovers()
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(searchQuery.isEmpty || isSearching)
            }
            .padding(.horizontal)
            
            if isSearching {
                ProgressView("Searching...")
                    .padding()
            } else if searchResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Search for album covers")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(searchResults) { result in
                            AsyncImage(url: URL(string: result.thumbnailURL)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .onTapGesture {
                                            Task {
                                                await selectCover(result)
                                            }
                                        }
                                case .failure:
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(width: 100, height: 100)
                                        .overlay {
                                            Image(systemName: "exclamationmark.triangle")
                                                .foregroundStyle(.secondary)
                                        }
                                case .empty:
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(width: 100, height: 100)
                                        .overlay {
                                            ProgressView()
                                        }
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    private func searchCovers() async {
        isSearching = true
        defer { isSearching = false }
        
        let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchQuery
        let searchURL = "https://itunes.apple.com/search?term=\(encodedQuery)&media=music&entity=album&limit=15"
        
        guard let url = URL(string: searchURL) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
            
            await MainActor.run {
                searchResults = response.results.map { result in
                    CoverSearchResult(
                        id: "\(result.collectionId)",
                        thumbnailURL: result.artworkUrl100,
                        fullURL: result.artworkUrl100.replacingOccurrences(of: "100x100", with: "600x600")
                    )
                }
            }
        } catch {
            print("Cover search failed: \(error)")
        }
    }
    
    private func selectCover(_ result: CoverSearchResult) async {
        guard let url = URL(string: result.fullURL) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    capturedImage = image
                }
            }
        } catch {
            print("Failed to download cover: \(error)")
        }
    }
}
#else
/// macOS fallback for album art - search only
struct AlbumArtSheet: View {
    let track: AudioTrack
    let onSave: (Data) -> Void
    let onCancel: () -> Void
    
    @State private var searchQuery = ""
    @State private var searchResults: [CoverSearchResult] = []
    @State private var isSearching = false
    @State private var selectedImageData: Data?
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Set Album Art")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("\(track.title) - \(track.artist ?? "Unknown")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            HStack {
                TextField("Search for album covers...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                
                Button("Search") {
                    Task { await searchCovers() }
                }
                .disabled(searchQuery.isEmpty || isSearching)
            }
            
            if isSearching {
                ProgressView("Searching...")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(searchResults) { result in
                            AsyncImage(url: URL(string: result.thumbnailURL)) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture { Task { await selectCover(result) } }
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.2))
                                    .frame(width: 80, height: 80)
                            }
                        }
                    }
                }
            }
            
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Save") {
                    if let data = selectedImageData { onSave(data) }
                }
                .disabled(selectedImageData == nil)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .onAppear { searchQuery = "\(track.title) \(track.artist ?? "") album cover" }
    }
    
    private func searchCovers() async {
        isSearching = true
        defer { isSearching = false }
        let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchQuery
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(encodedQuery)&media=music&entity=album&limit=15") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
            await MainActor.run {
                searchResults = response.results.map { CoverSearchResult(id: "\($0.collectionId)", thumbnailURL: $0.artworkUrl100, fullURL: $0.artworkUrl100.replacingOccurrences(of: "100x100", with: "600x600")) }
            }
        } catch { print("Cover search failed: \(error)") }
    }
    
    private func selectCover(_ result: CoverSearchResult) async {
        guard let url = URL(string: result.fullURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            await MainActor.run { selectedImageData = data }
        } catch { print("Failed to download cover: \(error)") }
    }
}
#endif

struct CoverSearchResult: Identifiable {
    let id: String
    let thumbnailURL: String
    let fullURL: String
}

struct iTunesSearchResponse: Codable {
    let results: [iTunesAlbum]
}

struct iTunesAlbum: Codable {
    let collectionId: Int
    let artworkUrl100: String
}

// MARK: - Image Picker

#if os(iOS)
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let sourceType: UIImagePickerController.SourceType
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
