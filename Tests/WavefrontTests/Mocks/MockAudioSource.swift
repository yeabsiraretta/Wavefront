import Foundation
@testable import Wavefront

/// Mock audio source for testing
final class MockAudioSource: AudioSource, @unchecked Sendable {
    let sourceId: String
    let displayName: String
    let sourceType: AudioSourceType
    
    var mockIsAvailable: Bool = true
    var mockTracks: [AudioTrack] = []
    var mockError: AudioSourceError?
    var fetchTracksCallCount = 0
    var getPlayableURLCallCount = 0
    
    var isAvailable: Bool {
        get async { mockIsAvailable }
    }
    
    init(
        sourceId: String = "mock-source",
        displayName: String = "Mock Source",
        sourceType: AudioSourceType = .local
    ) {
        self.sourceId = sourceId
        self.displayName = displayName
        self.sourceType = sourceType
    }
    
    func fetchTracks() async throws -> [AudioTrack] {
        fetchTracksCallCount += 1
        if let error = mockError {
            throw error
        }
        return mockTracks
    }
    
    func fetchTracks(at path: String) async throws -> [AudioTrack] {
        fetchTracksCallCount += 1
        if let error = mockError {
            throw error
        }
        return mockTracks.filter { $0.fileURL.path.contains(path) }
    }
    
    func getPlayableURL(for track: AudioTrack) async throws -> URL {
        getPlayableURLCallCount += 1
        if let error = mockError {
            throw error
        }
        return track.fileURL
    }
    
    func trackExists(_ track: AudioTrack) async -> Bool {
        mockTracks.contains { $0.id == track.id }
    }
    
    // MARK: - Test Helpers
    
    func addMockTrack(
        title: String,
        artist: String? = nil,
        path: String = "/mock/path/song.mp3"
    ) {
        let url = URL(fileURLWithPath: path)
        let track = AudioTrack(
            title: title,
            artist: artist,
            fileURL: url,
            sourceType: sourceType
        )
        mockTracks.append(track)
    }
    
    func reset() {
        mockIsAvailable = true
        mockTracks = []
        mockError = nil
        fetchTracksCallCount = 0
        getPlayableURLCallCount = 0
    }
}
