import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Row view for displaying an artist in a list
struct ArtistRow: View {
    let artist: Artist
    #if os(iOS)
    @State private var previewImage: UIImage?
    #endif
    
    var body: some View {
        HStack(spacing: 12) {
            // Artist preview image
            artistPreviewImage
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text("\(artist.trackCount) \(artist.trackCount == 1 ? "song" : "songs")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if !artist.albums.isEmpty {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("\(artist.albums.count) \(artist.albums.count == 1 ? "album" : "albums")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        #if os(iOS)
        .onAppear {
            loadPreviewImage()
        }
        #endif
    }
    
    @ViewBuilder
    private var artistPreviewImage: some View {
        ZStack {
            // Gradient background
            Circle()
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            #if os(iOS)
            if let image = previewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            #else
            Image(systemName: "person.fill")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.8))
            #endif
        }
    }
    
    private var gradientColors: [Color] {
        let hash = abs(artist.name.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = Double((hash / 360) % 360) / 360.0
        return [
            Color(hue: hue1, saturation: 0.6, brightness: 0.7),
            Color(hue: hue2, saturation: 0.7, brightness: 0.5)
        ]
    }
    
    #if os(iOS)
    private func loadPreviewImage() {
        // Try to load album art from one of the artist's tracks
        for track in artist.tracks {
            let key = "artwork_\(track.id.uuidString)"
            if let path = UserDefaults.standard.string(forKey: key),
               FileManager.default.fileExists(atPath: path),
               let data = FileManager.default.contents(atPath: path),
               let image = UIImage(data: data) {
                previewImage = image
                return
            }
        }
    }
    #endif
}

/// Detail view for an artist showing all their tracks
struct ArtistDetailView: View {
    let artist: Artist
    @ObservedObject var viewModel: MusicLibraryViewModel
    @StateObject private var userLibrary = UserLibrary.shared
    #if os(iOS)
    @State private var headerImage: UIImage?
    #endif
    
    var body: some View {
        List {
            // Artist header
            Section {
                VStack(spacing: 12) {
                    artistHeaderImage
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    
                    Text(artist.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack(spacing: 16) {
                        Label("\(artist.trackCount) songs", systemImage: "music.note")
                        if !artist.albums.isEmpty {
                            Label("\(artist.albums.count) albums", systemImage: "square.stack")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    // Play all button
                    Button {
                        if let firstTrack = artist.tracks.first {
                            viewModel.play(firstTrack)
                            // Queue remaining tracks
                            for track in artist.tracks.dropFirst() {
                                viewModel.addToQueue(track)
                            }
                        }
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
            .listRowBackground(Color.clear)
            
            // Tracks section
            Section("Songs") {
                ForEach(artist.tracks) { track in
                    TrackRow(
                        track: track,
                        isPlaying: viewModel.currentTrack?.id == track.id,
                        isLiked: userLibrary.isLiked(track),
                        onLike: { userLibrary.toggleLike(track) },
                        onDelete: { viewModel.deleteTrack(track) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.play(track)
                    }
                    .contextMenu {
                        Button {
                            viewModel.addToQueue(track)
                        } label: {
                            Label("Add to Queue", systemImage: "text.badge.plus")
                        }
                        
                        Button {
                            userLibrary.toggleLike(track)
                        } label: {
                            Label(
                                userLibrary.isLiked(track) ? "Unlike" : "Like",
                                systemImage: userLibrary.isLiked(track) ? "heart.slash" : "heart"
                            )
                        }
                    }
                }
            }
            
            // Albums section if artist has multiple albums
            if artist.albums.count > 1 {
                Section("Albums") {
                    ForEach(artist.albums, id: \.self) { albumName in
                        let albumTracks = artist.tracks.filter { $0.album == albumName }
                        HStack {
                            Image(systemName: "square.stack")
                                .foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading) {
                                Text(albumName)
                                    .font(.body)
                                Text("\(albumTracks.count) songs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadHeaderImage()
        }
        #endif
        .navigationTitle(artist.name)
    }
    
    @ViewBuilder
    private var artistHeaderImage: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: headerGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            #if os(iOS)
            if let image = headerImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.white.opacity(0.8))
            }
            #else
            Image(systemName: "person.fill")
                .font(.system(size: 50))
                .foregroundStyle(.white.opacity(0.8))
            #endif
        }
    }
    
    private var headerGradientColors: [Color] {
        let hash = abs(artist.name.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = Double((hash / 360) % 360) / 360.0
        return [
            Color(hue: hue1, saturation: 0.6, brightness: 0.7),
            Color(hue: hue2, saturation: 0.7, brightness: 0.5)
        ]
    }
    
    #if os(iOS)
    private func loadHeaderImage() {
        for track in artist.tracks {
            let key = "artwork_\(track.id.uuidString)"
            if let path = UserDefaults.standard.string(forKey: key),
               FileManager.default.fileExists(atPath: path),
               let data = FileManager.default.contents(atPath: path),
               let image = UIImage(data: data) {
                headerImage = image
                return
            }
        }
    }
    #endif
}

#Preview {
    NavigationStack {
        ArtistDetailView(
            artist: Artist(
                name: "Sample Artist",
                tracks: [
                    AudioTrack(
                        title: "Song 1",
                        artist: "Sample Artist",
                        album: "Album 1",
                        fileURL: URL(fileURLWithPath: "/test.mp3"),
                        sourceType: .local
                    ),
                    AudioTrack(
                        title: "Song 2",
                        artist: "Sample Artist",
                        album: "Album 1",
                        fileURL: URL(fileURLWithPath: "/test2.mp3"),
                        sourceType: .local
                    )
                ]
            ),
            viewModel: MusicLibraryViewModel()
        )
    }
}
