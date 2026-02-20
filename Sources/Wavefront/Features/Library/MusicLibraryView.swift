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
                onImport: {
                    Task {
                        do {
                            try await viewModel.importFromYouTube(urlString: youtubeURL)
                            youtubeURL = ""
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
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

/// Now playing bar at bottom
struct NowPlayingBar: View {
    let track: AudioTrack?
    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onStop: () -> Void
    
    var body: some View {
        if let track = track {
            HStack(spacing: 16) {
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
                HStack(spacing: 20) {
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
        }
    }
}

/// Sheet for importing from YouTube
struct YouTubeImportSheet: View {
    @Binding var url: String
    let isLoading: Bool
    let onImport: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.red)
                
                Text("Import from YouTube")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Paste a YouTube URL to import the audio track.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                TextField("https://youtube.com/watch?v=...", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                
                if isLoading {
                    ProgressView("Downloading...")
                } else {
                    Button(action: onImport) {
                        Text("Import")
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
                }
            }
        }
        .presentationDetents([.medium])
    }
}
