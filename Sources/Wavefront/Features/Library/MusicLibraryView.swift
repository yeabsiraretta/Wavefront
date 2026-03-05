import SwiftUI
import AVFoundation
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
                            onStop: { viewModel.stop() },
                            onNext: { viewModel.playNextTrack() },
                            onPrevious: { viewModel.playPreviousTrack() },
                            onShuffleToggle: { viewModel.toggleShuffle() },
                            shuffleMode: viewModel.shuffleMode
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
    #if os(iOS)
    var albumArt: UIImage? = nil
    #endif
    var onLike: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            // Album art
            albumArtView
                .frame(width: 50, height: 50)
            
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
    
    @ViewBuilder
    private var albumArtView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.2))
            
            #if os(iOS)
            if let albumArt = albumArt {
                Image(uiImage: albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: isPlaying ? "waveform" : "music.note")
                    .foregroundStyle(isPlaying ? .blue : .secondary)
            }
            #else
            Image(systemName: isPlaying ? "waveform" : "music.note")
                .foregroundStyle(isPlaying ? .blue : .secondary)
            #endif
        }
    }
}

/// Now playing bar at bottom - tappable to expand
struct NowPlayingBar: View {
    let track: AudioTrack?
    let isPlaying: Bool
    let currentTime: TimeInterval
    let onPlayPause: () -> Void
    let onStop: () -> Void
    var onNext: (() -> Void)? = nil
    var onPrevious: (() -> Void)? = nil
    var onShuffleToggle: (() -> ShuffleMode)? = nil
    var shuffleMode: ShuffleMode = .off
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
                    onDismiss: { showingExpandedPlayer = false },
                    onNext: onNext,
                    onPrevious: onPrevious,
                    onShuffleToggle: onShuffleToggle,
                    shuffleMode: shuffleMode
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
                    onDismiss: { showingExpandedPlayer = false },
                    onNext: onNext,
                    onPrevious: onPrevious,
                    onShuffleToggle: onShuffleToggle,
                    shuffleMode: shuffleMode
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
    var onNext: (() -> Void)? = nil
    var onPrevious: (() -> Void)? = nil
    var onShuffleToggle: (() -> ShuffleMode)? = nil
    var shuffleMode: ShuffleMode = .off
    
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
                        onLike: onLike,
                        onNext: onNext,
                        onPrevious: onPrevious,
                        onShuffleToggle: onShuffleToggle,
                        shuffleMode: shuffleMode
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
    var onNext: (() -> Void)? = nil
    var onPrevious: (() -> Void)? = nil
    var onShuffleToggle: (() -> ShuffleMode)? = nil
    var shuffleMode: ShuffleMode = .off
    
    @State private var currentShuffleMode: ShuffleMode = .off
    
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
            
            // Shuffle indicator
            if currentShuffleMode != .off {
                HStack(spacing: 4) {
                    Image(systemName: currentShuffleMode.icon)
                    Text(currentShuffleMode.rawValue)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
            }
            
            // Main controls
            HStack(spacing: 20) {
                // Shuffle button
                Button {
                    if let toggle = onShuffleToggle {
                        currentShuffleMode = toggle()
                    }
                } label: {
                    Image(systemName: currentShuffleMode.icon)
                        .font(.title3)
                        .foregroundStyle(currentShuffleMode != .off ? Color.accentColor : Color.primary)
                }
                
                // Previous button
                Button {
                    onPrevious?()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title)
                }
                
                // Play/Pause button
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                }
                .padding(.horizontal, 8)
                
                // Next button
                Button {
                    onNext?()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title)
                }
                
                // Like button
                Button(action: onLike) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(isLiked ? .red : .primary)
                }
            }
            .padding(.vertical)
            
            Spacer()
        }
        .padding()
        .onAppear {
            currentShuffleMode = shuffleMode
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

/**
 * Waveform visualization page with 10-second sliding window.
 *
 * Displays a procedurally generated waveform visualization that shows
 * a 10-second window centered on the current playback position. The
 * waveform scrolls as playback progresses.
 *
 * ## Features
 * - 10-second sliding window visualization
 * - Current position indicator (white bar)
 * - Played/unplayed bar coloring
 * - Large time display
 * - Overall progress bar showing position in full song
 *
 * ## Properties
 * @property track - The audio track being visualized
 * @property currentTime - Current playback position in seconds
 * @property isPlaying - Whether audio is currently playing
 */
private struct WaveformPage: View {
    /// The audio track being visualized
    let track: AudioTrack
    
    /// Current playback position in seconds
    let currentTime: TimeInterval
    
    /// Whether audio is currently playing
    let isPlaying: Bool
    
    /// Window size in seconds (10 seconds)
    private let windowDuration: TimeInterval = 10.0
    
    /// Number of bars to display in the window
    private let displayBarCount = 60
    
    @State private var allWaveformBars: [CGFloat] = []
    
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
            
            // Current time prominently displayed
            Text(formatTime(currentTime))
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(.primary)
            
            // Waveform visualization - sliding window
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<displayBarCount, id: \.self) { index in
                    let barData = getBarData(displayIndex: index)
                    WaveformBar(
                        height: barData.height,
                        isPlayed: barData.isPlayed,
                        isCurrent: barData.isCurrent,
                        isPlaying: isPlaying
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 200)
            .padding(.horizontal, 24)
            .onAppear {
                generateFullWaveform()
            }
            
            // Window time range display
            HStack {
                Text(formatTime(windowStartTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("10s window")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                Text(formatTime(windowEndTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            
            // Progress in song
            VStack(spacing: 4) {
                ProgressView(value: progressValue, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(height: 4)
                
                Text("\(formatTime(currentTime)) / \(formatTime(track.duration ?? 0))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .padding()
    }
    
    /// Start time of the current window
    private var windowStartTime: TimeInterval {
        let halfWindow = windowDuration / 2
        let centered = currentTime - halfWindow
        return max(0, min(centered, (track.duration ?? 0) - windowDuration))
    }
    
    /// End time of the current window
    private var windowEndTime: TimeInterval {
        return min(windowStartTime + windowDuration, track.duration ?? 0)
    }
    
    /// Overall progress in the song
    private var progressValue: Double {
        guard let duration = track.duration, duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }
    
    /// Generate waveform data for the entire song
    private func generateFullWaveform() {
        guard let duration = track.duration, duration > 0 else {
            allWaveformBars = Array(repeating: 0.5, count: 100)
            return
        }
        
        // Generate more bars for longer songs (roughly 6 bars per second)
        let totalBars = Int(duration * 6)
        let seed = track.title.hashValue
        var bars: [CGFloat] = []
        
        for i in 0..<totalBars {
            let random = abs((seed + i * 31) % 100)
            let height = CGFloat(30 + random % 70) / 100.0
            bars.append(height)
        }
        
        allWaveformBars = bars
    }
    
    /// Get bar data for a display position in the sliding window
    private func getBarData(displayIndex: Int) -> (height: CGFloat, isPlayed: Bool, isCurrent: Bool) {
        guard let duration = track.duration, duration > 0, !allWaveformBars.isEmpty else {
            return (0.5, false, false)
        }
        
        // Calculate what time this bar represents
        let barTimeInWindow = (Double(displayIndex) / Double(displayBarCount)) * windowDuration
        let barTime = windowStartTime + barTimeInWindow
        
        // Map to the full waveform array
        let barIndex = Int((barTime / duration) * Double(allWaveformBars.count))
        let safeIndex = min(max(0, barIndex), allWaveformBars.count - 1)
        
        let height = allWaveformBars[safeIndex]
        let isPlayed = barTime <= currentTime
        
        // Mark the bar closest to current time
        let currentBarIndex = Int(((currentTime - windowStartTime) / windowDuration) * Double(displayBarCount))
        let isCurrent = displayIndex == currentBarIndex
        
        return (height, isPlayed, isCurrent)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/**
 * Individual waveform bar component.
 *
 * Renders a single vertical bar in the waveform visualization with
 * color coding based on playback state.
 *
 * ## Color Coding
 * - White: Current playback position
 * - Accent color: Already played portion
 * - Gray (30% opacity): Not yet played
 *
 * ## Properties
 * @property height - Normalized height (0.0 to 1.0)
 * @property isPlayed - Whether this bar has been played
 * @property isCurrent - Whether this is the current position bar
 * @property isPlaying - Whether audio is currently playing
 */
private struct WaveformBar: View {
    /// Normalized height of the bar (0.0 to 1.0)
    let height: CGFloat
    
    /// Whether this portion has been played
    let isPlayed: Bool
    
    /// Whether this is the current playback position
    let isCurrent: Bool
    
    /// Whether audio is currently playing
    let isPlaying: Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(barColor)
            .frame(width: 4, height: 200 * height)
            .animation(.easeInOut(duration: 0.1), value: isPlayed)
    }
    
    /// Determines bar color based on playback state
    private var barColor: Color {
        if isCurrent {
            return .white
        } else if isPlayed {
            return .accentColor
        } else {
            return .secondary.opacity(0.3)
        }
    }
}

/**
 * Lyrics display page with placeholder for missing lyrics.
 *
 * Shows the track's lyrics if available, or displays a centered
 * "No lyrics." placeholder message when lyrics are not present.
 *
 * ## Features
 * - Scrollable lyrics display when available
 * - Centered placeholder for missing lyrics
 * - Track info header with title and artist
 *
 * ## Properties
 * @property track - The audio track whose lyrics to display
 */
private struct LyricsPage: View {
    /// The audio track whose lyrics to display
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
    #if os(iOS)
    @State private var artworkImage: UIImage?
    @State private var isLoading = false
    #endif
    
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
            
            #if os(iOS)
            if let image = artworkImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(size > 100 ? 1.0 : 0.5)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.white.opacity(0.8))
            }
            #else
            Image(systemName: "music.note")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.white.opacity(0.8))
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.1))
        #if os(iOS)
        .onAppear {
            loadArtwork()
        }
        .onChange(of: track.id) { _ in
            artworkImage = nil
            loadArtwork()
        }
        #endif
    }
    
    #if os(iOS)
    private func loadArtwork() {
        // 1. Check if we already have the image
        if artworkImage != nil { return }
        
        // 2. Check saved artwork path in UserDefaults
        if let path = UserDefaults.standard.string(forKey: "artwork_\(track.id.uuidString)"),
           FileManager.default.fileExists(atPath: path),
           let data = FileManager.default.contents(atPath: path),
           let image = UIImage(data: data) {
            artworkImage = image
            return
        }
        
        // 3. Check track's artworkURL
        if let artworkURL = track.artworkURL {
            loadFromURL(artworkURL)
            return
        }
        
        // 4. Try to extract from audio file metadata
        extractEmbeddedArtwork()
    }
    
    private func loadFromURL(_ url: URL) {
        isLoading = true
        
        Task {
            do {
                if url.isFileURL {
                    // Local file
                    if let data = try? Data(contentsOf: url),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            self.artworkImage = image
                            self.isLoading = false
                        }
                        // Save for future use
                        saveArtwork(data)
                    }
                } else {
                    // Remote URL
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = UIImage(data: data) {
                        await MainActor.run {
                            self.artworkImage = image
                            self.isLoading = false
                        }
                        // Save for future use
                        saveArtwork(data)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func extractEmbeddedArtwork() {
        guard track.fileURL.isFileURL else { return }
        
        isLoading = true
        
        Task {
            let asset = AVURLAsset(url: track.fileURL)
            
            // Try to load artwork from common metadata
            do {
                let metadata = try await asset.load(.commonMetadata)
                
                for item in metadata {
                    if let key = item.commonKey, key == .commonKeyArtwork {
                        if let data = try? await item.load(.dataValue),
                           let image = UIImage(data: data) {
                            await MainActor.run {
                                self.artworkImage = image
                                self.isLoading = false
                            }
                            // Save for future use
                            saveArtwork(data)
                            return
                        }
                    }
                }
            } catch {
                // Metadata extraction failed
            }
            
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    private func saveArtwork(_ data: Data) {
        let artworkDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Artwork")
        
        do {
            try FileManager.default.createDirectory(at: artworkDir, withIntermediateDirectories: true)
            let filename = "\(track.id.uuidString).jpg"
            let artworkURL = artworkDir.appendingPathComponent(filename)
            try data.write(to: artworkURL)
            UserDefaults.standard.set(artworkURL.path, forKey: "artwork_\(track.id.uuidString)")
        } catch {
            // Failed to save, but we still have the image in memory
        }
    }
    #endif
    
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
                
                if isLoading {
                    Text("You can dismiss this sheet - download will continue in background")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isLoading ? "Minimize" : "Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium])
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

/**
 * Sheet for viewing all notes/thoughts for a specific track.
 *
 * Displays a list of user notes associated with a track in reverse
 * chronological order (newest first). Each note is expandable to show
 * full content and relative time.
 *
 * ## Features
 * - Reverse chronological ordering (newest first)
 * - Tap-to-expand note rows
 * - 2-line preview when collapsed, full content when expanded
 * - Relative time display ("2 days ago") when expanded
 * - Empty state with instructions for adding notes
 *
 * ## Properties
 * @property track - The track whose notes to display
 * @property thoughts - Array of MusicThought objects for this track
 * @property onDismiss - Callback when sheet is dismissed
 */
struct TrackNotesSheet: View {
    /// The track whose notes to display
    let track: AudioTrack
    
    /// Array of thoughts/notes for this track
    let thoughts: [MusicThought]
    
    /// Callback when the sheet is dismissed
    let onDismiss: () -> Void
    
    /// ID of the currently expanded note (nil if none expanded)
    @State private var expandedNoteId: UUID?
    
    /// Date formatter for displaying note timestamps
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

/**
 * Individual note row with tap-to-expand functionality.
 *
 * Displays a single note with date header, content preview, and
 * expansion indicator. Tapping toggles between collapsed (2-line
 * preview) and expanded (full content with relative time) states.
 *
 * ## Properties
 * @property thought - The MusicThought to display
 * @property isExpanded - Whether the row is currently expanded
 * @property dateFormatter - Formatter for displaying the note date
 * @property onTap - Callback when the row is tapped
 */
private struct NoteRow: View {
    /// The thought/note to display
    let thought: MusicThought
    
    /// Whether this row is currently expanded
    let isExpanded: Bool
    
    /// Formatter for displaying dates
    let dateFormatter: DateFormatter
    
    /// Callback when row is tapped
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
/**
 * Sheet for setting album art via multiple methods.
 *
 * Provides a comprehensive interface for selecting or capturing album artwork
 * with four input methods: Photo Library, Camera, iTunes Search, and URL input.
 *
 * ## Features
 * - Photo library picker for selecting existing images
 * - Camera capture for taking new photos
 * - iTunes API search for finding official album covers
 * - URL input for pasting image links
 * - Image preview with selection indicator
 * - High-quality image compression for storage
 *
 * ## Properties
 * @property track - The track to set album art for
 * @property onSave - Callback with image data when saved
 * @property onCancel - Callback when cancelled
 */
struct AlbumArtSheet: View {
    let track: AudioTrack
    let onSave: (Data) -> Void
    let onCancel: () -> Void
    
    /// Source selection tabs
    enum ArtSource: Int, CaseIterable {
        case photos = 0
        case camera = 1
        case search = 2
        case url = 3
        
        var title: String {
            switch self {
            case .photos: return "Photos"
            case .camera: return "Camera"
            case .search: return "Search"
            case .url: return "URL"
            }
        }
        
        var icon: String {
            switch self {
            case .photos: return "photo.on.rectangle"
            case .camera: return "camera"
            case .search: return "magnifyingglass"
            case .url: return "link"
            }
        }
    }
    
    @State private var selectedSource: ArtSource = .search
    @State private var searchQuery = ""
    @State private var searchResults: [CoverSearchResult] = []
    @State private var isSearching = false
    @State private var showingImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedImage: UIImage?
    @State private var imageURL = ""
    @State private var isLoadingURL = false
    @State private var urlError: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Track info header with preview
                trackHeader
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                
                // Source selector
                sourceSelector
                    .padding(.vertical, 12)
                
                Divider()
                
                // Content based on selected source
                Group {
                    switch selectedSource {
                    case .photos:
                        photosView
                    case .camera:
                        cameraView
                    case .search:
                        searchView
                    case .url:
                        urlView
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .navigationTitle("Set Album Art")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveImage()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedImage == nil)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $selectedImage, sourceType: imagePickerSource)
            }
        }
        .presentationDetents([.large])
        .onAppear {
            searchQuery = "\(track.artist ?? "") \(track.title)"
        }
    }
    
    // MARK: - Track Header
    
    private var trackHeader: some View {
        HStack(spacing: 16) {
            // Current/Selected art preview
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.accentColor, lineWidth: 3)
                        )
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(2)
                
                Text(track.artist ?? "Unknown Artist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                if let album = track.album {
                    Text(album)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if selectedImage != nil {
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text("Selected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Source Selector
    
    private var sourceSelector: some View {
        HStack(spacing: 8) {
            ForEach(ArtSource.allCases, id: \.rawValue) { source in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedSource = source
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: source.icon)
                            .font(.system(size: 18))
                        Text(source.title)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedSource == source ? Color.accentColor : Color.clear)
                    )
                    .foregroundStyle(selectedSource == source ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Photos View
    
    private var photosView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("Choose from Photo Library")
                    .font(.headline)
                
                Text("Select an existing photo to use as album artwork")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            
            Button {
                imagePickerSource = .photoLibrary
                showingImagePicker = true
            } label: {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 48)
            
            Spacer()
        }
    }
    
    // MARK: - Camera View
    
    private var cameraView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            if let image = selectedImage, imagePickerSource == .camera {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
                
                Button {
                    imagePickerSource = .camera
                    showingImagePicker = true
                } label: {
                    Label("Retake Photo", systemImage: "camera")
                }
                .buttonStyle(.bordered)
            } else {
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 8) {
                    Text("Take a Photo")
                        .font(.headline)
                    
                    Text("Capture album art with your camera")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Button {
                    imagePickerSource = .camera
                    showingImagePicker = true
                } label: {
                    Label("Open Camera", systemImage: "camera")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 48)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Search View
    
    private var searchView: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search iTunes for covers...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .submitLabel(.search)
                        .onSubmit {
                            Task { await searchCovers() }
                        }
                }
                .padding(10)
                .background(Color(UIColor.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                Button {
                    Task { await searchCovers() }
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                }
                .disabled(searchQuery.isEmpty || isSearching)
            }
            .padding(.horizontal)
            
            // Results
            if isSearching {
                Spacer()
                ProgressView("Searching iTunes...")
                Spacer()
            } else if searchResults.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Search for album artwork")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Results from iTunes Store")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(searchResults) { result in
                            CoverResultCell(
                                result: result,
                                isSelected: false,
                                onSelect: {
                                    Task { await selectCover(result) }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - URL View
    
    private var urlView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)
                
                Image(systemName: "link.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 8) {
                    Text("Paste Image URL")
                        .font(.headline)
                    
                    Text("Enter a direct link to an image file")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                VStack(spacing: 12) {
                    TextField("https://example.com/album-art.jpg", text: $imageURL)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 32)
                        .onSubmit {
                            Task { await loadImageFromURL() }
                        }
                
                if let error = urlError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                
                Button {
                    Task { await loadImageFromURL() }
                } label: {
                    if isLoadingURL {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    } else {
                        Label("Load Image", systemImage: "arrow.down.circle")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(imageURL.isEmpty || isLoadingURL)
                .padding(.horizontal, 48)
                }
                
                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }
    
    // MARK: - Actions
    
    private func searchCovers() async {
        isSearching = true
        defer { isSearching = false }
        
        let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchQuery
        let searchURL = "https://itunes.apple.com/search?term=\(encodedQuery)&media=music&entity=album&limit=21"
        
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
                    selectedImage = image
                }
            }
        } catch {
            print("Failed to download cover: \(error)")
        }
    }
    
    private func loadImageFromURL() async {
        urlError = nil
        isLoadingURL = true
        defer { isLoadingURL = false }
        
        guard let url = URL(string: imageURL) else {
            await MainActor.run { urlError = "Invalid URL format" }
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await MainActor.run { urlError = "Failed to load image" }
                return
            }
            
            guard let image = UIImage(data: data) else {
                await MainActor.run { urlError = "Invalid image format" }
                return
            }
            
            await MainActor.run {
                selectedImage = image
                urlError = nil
            }
        } catch {
            await MainActor.run { urlError = "Network error: \(error.localizedDescription)" }
        }
    }
    
    private func saveImage() {
        guard let image = selectedImage else { return }
        
        // Resize if needed and compress
        let maxSize: CGFloat = 600
        let resizedImage: UIImage
        
        if image.size.width > maxSize || image.size.height > maxSize {
            let scale = min(maxSize / image.size.width, maxSize / image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
        } else {
            resizedImage = image
        }
        
        if let data = resizedImage.jpegData(compressionQuality: 0.85) {
            onSave(data)
        }
    }
}

/// Cell for displaying a cover search result
private struct CoverResultCell: View {
    let result: CoverSearchResult
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isLoading = false
    
    var body: some View {
        AsyncImage(url: URL(string: result.thumbnailURL)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    .onTapGesture {
                        onSelect()
                    }
            case .failure:
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .overlay {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
            case .empty:
                RoundedRectangle(cornerRadius: 10)
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
