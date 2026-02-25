import SwiftUI

/// Sheet for renaming a track's title and artist
struct RenameTrackSheet: View {
    let track: AudioTrack
    let onSave: (String, String?) -> Void
    let onCancel: () -> Void
    
    @State private var newTitle: String
    @State private var newArtist: String
    
    init(track: AudioTrack, onSave: @escaping (String, String?) -> Void, onCancel: @escaping () -> Void) {
        self.track = track
        self.onSave = onSave
        self.onCancel = onCancel
        self._newTitle = State(initialValue: track.title)
        self._newArtist = State(initialValue: track.artist ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Track Info") {
                    TextField("Title", text: $newTitle)
                        .textContentType(.none)
                        .autocorrectionDisabled()
                    
                    TextField("Artist", text: $newArtist)
                        .textContentType(.none)
                        .autocorrectionDisabled()
                }
                
                Section {
                    HStack {
                        Text("Original Title")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(track.title)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    if let artist = track.artist {
                        HStack {
                            Text("Original Artist")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(artist)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .navigationTitle("Rename Track")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let artist = newArtist.isEmpty ? nil : newArtist
                        onSave(newTitle, artist)
                    }
                    .disabled(newTitle.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    RenameTrackSheet(
        track: AudioTrack(
            title: "Sample Song",
            artist: "Sample Artist",
            fileURL: URL(fileURLWithPath: "/test.mp3"),
            sourceType: .local
        ),
        onSave: { title, artist in
            print("Saved: \(title), \(artist ?? "nil")")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}
