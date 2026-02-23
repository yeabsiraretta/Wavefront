import SwiftUI
import MultipeerConnectivity

// MARK: - Shared Play View

/**
 * Main view for managing shared local play sessions.
 *
 * Provides UI for hosting a session, browsing for nearby sessions,
 * viewing connected peers, and managing the shared queue.
 */
struct SharedPlayView: View {
    @StateObject private var sharedPlayService = SharedPlayService()
    @ObservedObject var viewModel: MusicLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Session status header
                sessionStatusHeader
                
                Divider()
                
                // Main content based on state
                switch sharedPlayService.sessionState {
                case .notConnected:
                    notConnectedView
                case .browsing:
                    browsingView
                case .hosting:
                    hostingView
                case .connected:
                    connectedView
                }
            }
            .navigationTitle("Shared Play")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                setupCallbacks()
            }
            .onDisappear {
                // Don't disconnect on dismiss - keep session alive
            }
        }
    }
    
    // MARK: - Session Status Header
    
    private var sessionStatusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title2)
                .foregroundStyle(statusColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.headline)
                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if case .connected(let count) = sharedPlayService.sessionState {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                    Text("\(count)")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
    }
    
    private var statusIcon: String {
        switch sharedPlayService.sessionState {
        case .notConnected: return "wifi.slash"
        case .browsing: return "magnifyingglass"
        case .hosting: return "antenna.radiowaves.left.and.right"
        case .connected: return "wifi"
        }
    }
    
    private var statusColor: Color {
        switch sharedPlayService.sessionState {
        case .notConnected: return .secondary
        case .browsing: return .orange
        case .hosting: return .blue
        case .connected: return .green
        }
    }
    
    private var statusTitle: String {
        switch sharedPlayService.sessionState {
        case .notConnected: return "Not Connected"
        case .browsing: return "Searching..."
        case .hosting: return "Hosting Session"
        case .connected(let count): return "Connected (\(count) peer\(count == 1 ? "" : "s"))"
        }
    }
    
    private var statusSubtitle: String {
        switch sharedPlayService.sessionState {
        case .notConnected: return "Start or join a shared play session"
        case .browsing: return "Looking for nearby sessions"
        case .hosting: return "Waiting for others to join"
        case .connected: return "Sharing music together"
        }
    }
    
    // MARK: - Not Connected View
    
    private var notConnectedView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "airplayaudio")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Share Music Together")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Connect with nearby devices to share a music queue and listen together.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                Button {
                    sharedPlayService.startHosting()
                } label: {
                    Label("Host a Session", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    sharedPlayService.startBrowsing()
                } label: {
                    Label("Join a Session", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Browsing View
    
    private var browsingView: some View {
        VStack {
            if sharedPlayService.availableSessions.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Searching for nearby sessions...")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List {
                    Section("Available Sessions") {
                        ForEach(sharedPlayService.availableSessions, id: \.displayName) { peer in
                            Button {
                                sharedPlayService.joinSession(peer)
                            } label: {
                                HStack {
                                    Image(systemName: "iphone.radiowaves.left.and.right")
                                        .foregroundStyle(.blue)
                                    Text(peer.displayName)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
            }
            
            Button {
                sharedPlayService.stopAll()
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding()
        }
    }
    
    // MARK: - Hosting View
    
    private var hostingView: some View {
        VStack {
            VStack(spacing: 16) {
                Spacer()
                
                ProgressView()
                    .scaleEffect(1.5)
                
                Text("Waiting for others to join...")
                    .font(.headline)
                
                Text("Other devices can find your session by tapping 'Join a Session'")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
            }
            
            // Show queue if there are tracks
            if !sharedPlayService.sharedQueue.isEmpty {
                sharedQueueSection
            }
            
            Button {
                sharedPlayService.stopAll()
            } label: {
                Text("Stop Hosting")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .padding()
        }
    }
    
    // MARK: - Connected View
    
    private var connectedView: some View {
        VStack(spacing: 0) {
            // Connected peers section
            List {
                Section("Connected Peers") {
                    ForEach(sharedPlayService.connectedPeers, id: \.displayName) { peer in
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundStyle(.green)
                            Text(peer.displayName)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                
                Section("Shared Queue") {
                    if sharedPlayService.sharedQueue.isEmpty {
                        Text("Queue is empty")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sharedPlayService.sharedQueue) { track in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(track.title)
                                        .font(.body)
                                    if let artist = track.artist {
                                        Text(artist)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }
                
                Section("Add from Library") {
                    ForEach(viewModel.tracks.prefix(10)) { track in
                        Button {
                            let trackInfo = SharedTrackInfo(
                                id: track.id.uuidString,
                                title: track.title,
                                artist: track.artist,
                                duration: track.duration
                            )
                            sharedPlayService.broadcastQueueTrack(trackInfo)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(track.title)
                                        .foregroundStyle(.primary)
                                    Text(track.artist ?? "Unknown Artist")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            
            // Disconnect button
            Button {
                sharedPlayService.stopAll()
            } label: {
                Text("Disconnect")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .padding()
        }
    }
    
    // MARK: - Shared Queue Section
    
    private var sharedQueueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shared Queue")
                .font(.headline)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(sharedPlayService.sharedQueue) { track in
                        VStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 60, height: 60)
                                .overlay {
                                    Image(systemName: "music.note")
                                        .foregroundStyle(.secondary)
                                }
                            
                            Text(track.title)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(width: 60)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
    
    // MARK: - Setup
    
    private func setupCallbacks() {
        sharedPlayService.onQueueTrack = { trackInfo in
            // Find matching track in library and add to queue
            if let track = viewModel.tracks.first(where: { $0.id.uuidString == trackInfo.id }) {
                viewModel.addToQueue(track)
            }
        }
        
        sharedPlayService.onRemoveFromQueue = { trackId in
            if let track = viewModel.tracks.first(where: { $0.id.uuidString == trackId }) {
                viewModel.removeFromQueue(track)
            }
        }
        
        sharedPlayService.onPlayTrack = { trackId in
            if let track = viewModel.tracks.first(where: { $0.id.uuidString == trackId }) {
                viewModel.play(track)
            }
        }
        
        sharedPlayService.onPausePlayback = {
            if viewModel.isPlaying {
                viewModel.togglePlayPause()
            }
        }
        
        sharedPlayService.onResumePlayback = {
            if !viewModel.isPlaying {
                viewModel.togglePlayPause()
            }
        }
    }
}
