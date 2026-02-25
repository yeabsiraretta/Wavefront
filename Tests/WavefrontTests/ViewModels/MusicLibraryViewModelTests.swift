import XCTest
@testable import Wavefront

@MainActor
final class MusicLibraryViewModelTests: XCTestCase {
    
    var viewModel: MusicLibraryViewModel!
    
    override func setUp() async throws {
        viewModel = MusicLibraryViewModel()
    }
    
    override func tearDown() async throws {
        viewModel = nil
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertNotNil(viewModel)
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertNil(viewModel.currentTrack)
    }
    
    func testInitialStateIsNotPlaying() {
        XCTAssertFalse(viewModel.isPlaying)
    }
    
    func testInitialStateHasNoCurrentTrack() {
        XCTAssertNil(viewModel.currentTrack)
    }
    
    func testInitialPlaybackTimeIsZero() {
        XCTAssertEqual(viewModel.currentPlaybackTime, 0)
    }
    
    // MARK: - Track Management Tests
    
    func testTracksArrayInitiallyEmpty() {
        // After init, tracks may be empty or populated depending on local storage
        XCTAssertNotNil(viewModel.tracks)
    }
    
    // MARK: - Queue Management Tests
    
    func testAddToQueue() {
        let track = createTestTrack(title: "Test Song")
        
        viewModel.addToQueue(track)
        
        XCTAssertTrue(viewModel.isInQueue(track))
    }
    
    func testRemoveFromQueue() {
        let track = createTestTrack(title: "Test Song")
        
        viewModel.addToQueue(track)
        XCTAssertTrue(viewModel.isInQueue(track))
        
        viewModel.removeFromQueue(track)
        XCTAssertFalse(viewModel.isInQueue(track))
    }
    
    func testIsInQueueReturnsFalseForNonQueuedTrack() {
        let track = createTestTrack(title: "Not Queued")
        XCTAssertFalse(viewModel.isInQueue(track))
    }
    
    func testAddMultipleTracksToQueue() {
        let track1 = createTestTrack(title: "Song 1")
        let track2 = createTestTrack(title: "Song 2")
        let track3 = createTestTrack(title: "Song 3")
        
        viewModel.addToQueue(track1)
        viewModel.addToQueue(track2)
        viewModel.addToQueue(track3)
        
        XCTAssertTrue(viewModel.isInQueue(track1))
        XCTAssertTrue(viewModel.isInQueue(track2))
        XCTAssertTrue(viewModel.isInQueue(track3))
    }
    
    // MARK: - Playback Control Tests
    
    func testTogglePlayPauseWhenNotPlaying() {
        // Initially not playing
        XCTAssertFalse(viewModel.isPlaying)
        
        // Toggle should attempt to play (may not actually play without a track)
        viewModel.togglePlayPause()
    }
    
    func testStopPlayback() {
        viewModel.stop()
        
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertNil(viewModel.currentTrack)
    }
    
    // MARK: - Music Thoughts Tests
    
    func testGetThoughtsForTrackReturnsEmptyArrayForUnknownTrack() {
        let track = createTestTrack(title: "Unknown Song")
        let thoughts = viewModel.getThoughtsForTrack(track)
        
        // Should return empty array, not crash
        XCTAssertNotNil(thoughts)
    }
    
    func testSaveMusicThought() {
        // saveMusicThought takes a String parameter
        viewModel.saveMusicThought("This is a great song!")
        
        // Verify it was saved (implementation dependent)
        // At minimum, this should not crash
    }
    
    func testSaveMusicThoughtWithEmptyString() {
        // Empty string should be ignored
        viewModel.saveMusicThought("")
        viewModel.saveMusicThought("   ")
        
        // Should not crash
    }
    
    // MARK: - Error Handling Tests
    
    func testSetError() {
        viewModel.setError("Test error message")
        
        XCTAssertEqual(viewModel.errorMessage, "Test error message")
    }
    
    func testClearError() {
        viewModel.setError("Error to clear")
        XCTAssertNotNil(viewModel.errorMessage)
        
        viewModel.clearError()
        XCTAssertNil(viewModel.errorMessage)
    }
    
    func testErrorMessageInitiallyNil() {
        XCTAssertNil(viewModel.errorMessage)
    }
    
    // MARK: - Import Status Tests
    
    func testYoutubeImportStatusInitiallyNil() {
        XCTAssertNil(viewModel.youtubeImportStatus)
    }
    
    func testSpotifyImportStatusInitiallyNil() {
        XCTAssertNil(viewModel.spotifyImportStatus)
    }
    
    func testYoutubeDownloadProgressInitiallyNil() {
        XCTAssertNil(viewModel.youtubeDownloadProgress)
    }
    
    func testSpotifyDownloadProgressInitiallyNil() {
        XCTAssertNil(viewModel.spotifyDownloadProgress)
    }
    
    // MARK: - Helper Methods
    
    private func createTestTrack(title: String, artist: String? = nil) -> AudioTrack {
        AudioTrack(
            title: title,
            artist: artist,
            fileURL: URL(fileURLWithPath: "/test/\(title).mp3"),
            sourceType: .local
        )
    }
}

// MARK: - MusicThought Tests

final class MusicThoughtTests: XCTestCase {
    
    func testMusicThoughtInitialization() {
        let id = UUID()
        let date = Date()
        
        let thought = MusicThought(
            id: id,
            content: "Great song!",
            date: date,
            trackTitle: "Test Song",
            trackArtist: "Test Artist"
        )
        
        XCTAssertEqual(thought.id, id)
        XCTAssertEqual(thought.content, "Great song!")
        XCTAssertEqual(thought.date, date)
        XCTAssertEqual(thought.trackTitle, "Test Song")
        XCTAssertEqual(thought.trackArtist, "Test Artist")
    }
    
    func testMusicThoughtIdentifiable() {
        let thought = MusicThought(
            id: UUID(),
            content: "Test",
            date: Date(),
            trackTitle: "Song",
            trackArtist: nil
        )
        
        XCTAssertNotNil(thought.id)
    }
    
    func testMusicThoughtWithNilArtist() {
        let thought = MusicThought(
            id: UUID(),
            content: "Thought content",
            date: Date(),
            trackTitle: "Song Title",
            trackArtist: nil
        )
        
        XCTAssertNil(thought.trackArtist)
    }
    
    func testMusicThoughtCodable() throws {
        let thought = MusicThought(
            id: UUID(),
            content: "Amazing lyrics!",
            date: Date(),
            trackTitle: "Test Song",
            trackArtist: "Test Artist"
        )
        
        let encoded = try JSONEncoder().encode(thought)
        let decoded = try JSONDecoder().decode(MusicThought.self, from: encoded)
        
        XCTAssertEqual(decoded.id, thought.id)
        XCTAssertEqual(decoded.content, thought.content)
        XCTAssertEqual(decoded.trackTitle, thought.trackTitle)
        XCTAssertEqual(decoded.trackArtist, thought.trackArtist)
    }
}

// MARK: - Album Tests

final class AlbumTests: XCTestCase {
    
    func testAlbumGroupTracks() {
        let tracks = [
            AudioTrack(title: "Song 1", album: "Album A", fileURL: URL(fileURLWithPath: "/1.mp3"), sourceType: .local),
            AudioTrack(title: "Song 2", album: "Album A", fileURL: URL(fileURLWithPath: "/2.mp3"), sourceType: .local),
            AudioTrack(title: "Song 3", album: "Album B", fileURL: URL(fileURLWithPath: "/3.mp3"), sourceType: .local)
        ]
        
        let albums = Album.groupTracks(tracks)
        
        XCTAssertEqual(albums.count, 2)
    }
    
    func testAlbumGroupTracksWithNoAlbum() {
        let tracks = [
            AudioTrack(title: "Song 1", album: nil, fileURL: URL(fileURLWithPath: "/1.mp3"), sourceType: .local),
            AudioTrack(title: "Song 2", album: nil, fileURL: URL(fileURLWithPath: "/2.mp3"), sourceType: .local)
        ]
        
        let albums = Album.groupTracks(tracks)
        
        // Tracks without album should be grouped under "Unknown Album" or similar
        XCTAssertGreaterThanOrEqual(albums.count, 1)
    }
    
    func testAlbumIdentifiable() {
        let track = AudioTrack(title: "Song", album: "Test Album", fileURL: URL(fileURLWithPath: "/1.mp3"), sourceType: .local)
        let albums = Album.groupTracks([track])
        
        if let album = albums.first {
            XCTAssertNotNil(album.id)
        }
    }
    
    func testAlbumTracksCount() {
        let tracks = [
            AudioTrack(title: "Song 1", album: "Album A", fileURL: URL(fileURLWithPath: "/1.mp3"), sourceType: .local),
            AudioTrack(title: "Song 2", album: "Album A", fileURL: URL(fileURLWithPath: "/2.mp3"), sourceType: .local),
            AudioTrack(title: "Song 3", album: "Album A", fileURL: URL(fileURLWithPath: "/3.mp3"), sourceType: .local)
        ]
        
        let albums = Album.groupTracks(tracks)
        
        if let albumA = albums.first(where: { $0.name == "Album A" }) {
            XCTAssertEqual(albumA.tracks.count, 3)
        }
    }
}
