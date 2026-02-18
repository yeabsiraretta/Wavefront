import XCTest
@testable import Wavefront

final class UserLibraryTests: XCTestCase {
    
    var userLibrary: UserLibrary!
    
    override func setUp() {
        super.setUp()
        userLibrary = UserLibrary.shared
        // Clear any existing data for clean tests
        userLibrary.clearHistory()
    }
    
    // MARK: - Liked Songs Tests
    
    func testLikeSong() {
        let track = createTestTrack(id: UUID(), title: "Test Song")
        
        XCTAssertFalse(userLibrary.isLiked(track))
        
        userLibrary.like(track)
        
        XCTAssertTrue(userLibrary.isLiked(track))
    }
    
    func testUnlikeSong() {
        let track = createTestTrack(id: UUID(), title: "Test Song")
        
        userLibrary.like(track)
        XCTAssertTrue(userLibrary.isLiked(track))
        
        userLibrary.unlike(track)
        XCTAssertFalse(userLibrary.isLiked(track))
    }
    
    func testToggleLike() {
        let track = createTestTrack(id: UUID(), title: "Test Song")
        
        XCTAssertFalse(userLibrary.isLiked(track))
        
        userLibrary.toggleLike(track)
        XCTAssertTrue(userLibrary.isLiked(track))
        
        userLibrary.toggleLike(track)
        XCTAssertFalse(userLibrary.isLiked(track))
    }
    
    func testGetLikedTracks() {
        let track1 = createTestTrack(id: UUID(), title: "Song 1")
        let track2 = createTestTrack(id: UUID(), title: "Song 2")
        let track3 = createTestTrack(id: UUID(), title: "Song 3")
        
        userLibrary.like(track1)
        userLibrary.like(track3)
        
        let allTracks = [track1, track2, track3]
        let likedTracks = userLibrary.getLikedTracks(from: allTracks)
        
        XCTAssertEqual(likedTracks.count, 2)
        XCTAssertTrue(likedTracks.contains(where: { $0.id == track1.id }))
        XCTAssertTrue(likedTracks.contains(where: { $0.id == track3.id }))
        XCTAssertFalse(likedTracks.contains(where: { $0.id == track2.id }))
    }
    
    // MARK: - Listening History Tests
    
    func testRecordPlay() {
        let track = createTestTrack(id: UUID(), title: "Test Song")
        
        XCTAssertTrue(userLibrary.listeningHistory.isEmpty)
        
        userLibrary.recordPlay(track)
        
        XCTAssertEqual(userLibrary.listeningHistory.count, 1)
        XCTAssertEqual(userLibrary.listeningHistory.first?.trackID, track.id)
        XCTAssertEqual(userLibrary.listeningHistory.first?.trackTitle, track.title)
    }
    
    func testHistoryOrder() {
        let track1 = createTestTrack(id: UUID(), title: "Song 1")
        let track2 = createTestTrack(id: UUID(), title: "Song 2")
        
        userLibrary.recordPlay(track1)
        userLibrary.recordPlay(track2)
        
        // Most recent should be first
        XCTAssertEqual(userLibrary.listeningHistory.first?.trackID, track2.id)
        XCTAssertEqual(userLibrary.listeningHistory.last?.trackID, track1.id)
    }
    
    func testClearHistory() {
        let track = createTestTrack(id: UUID(), title: "Test Song")
        
        userLibrary.recordPlay(track)
        XCTAssertFalse(userLibrary.listeningHistory.isEmpty)
        
        userLibrary.clearHistory()
        XCTAssertTrue(userLibrary.listeningHistory.isEmpty)
    }
    
    func testGetRecentTracks() {
        let track1 = createTestTrack(id: UUID(), title: "Song 1")
        let track2 = createTestTrack(id: UUID(), title: "Song 2")
        let track3 = createTestTrack(id: UUID(), title: "Song 3")
        
        userLibrary.recordPlay(track1)
        userLibrary.recordPlay(track2)
        userLibrary.recordPlay(track3)
        
        let allTracks = [track1, track2, track3]
        let recentTracks = userLibrary.getRecentTracks(from: allTracks, limit: 2)
        
        // Should return most recent first, limited to 2
        XCTAssertEqual(recentTracks.count, 2)
        XCTAssertEqual(recentTracks.first?.id, track3.id)
    }
    
    // MARK: - Album Grouping Tests
    
    func testAlbumGrouping() {
        let track1 = createTestTrack(id: UUID(), title: "Song 1", album: "Album A")
        let track2 = createTestTrack(id: UUID(), title: "Song 2", album: "Album A")
        let track3 = createTestTrack(id: UUID(), title: "Song 3", album: "Album B")
        
        let albums = Album.groupTracks([track1, track2, track3])
        
        XCTAssertEqual(albums.count, 2)
        
        let albumA = albums.first(where: { $0.name == "Album A" })
        XCTAssertNotNil(albumA)
        XCTAssertEqual(albumA?.tracks.count, 2)
        
        let albumB = albums.first(where: { $0.name == "Album B" })
        XCTAssertNotNil(albumB)
        XCTAssertEqual(albumB?.tracks.count, 1)
    }
    
    func testAlbumGroupingWithUnknownAlbum() {
        let track1 = createTestTrack(id: UUID(), title: "Song 1", album: nil)
        let track2 = createTestTrack(id: UUID(), title: "Song 2", album: nil)
        
        let albums = Album.groupTracks([track1, track2])
        
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums.first?.name, "Unknown Album")
        XCTAssertEqual(albums.first?.tracks.count, 2)
    }
    
    // MARK: - ListeningHistoryEntry Tests
    
    func testListeningHistoryEntryInit() {
        let trackID = UUID()
        let entry = ListeningHistoryEntry(
            trackID: trackID,
            trackTitle: "Test Song",
            artist: "Test Artist",
            album: "Test Album",
            playedAt: Date()
        )
        
        XCTAssertEqual(entry.trackID, trackID)
        XCTAssertEqual(entry.trackTitle, "Test Song")
        XCTAssertEqual(entry.artist, "Test Artist")
        XCTAssertEqual(entry.album, "Test Album")
    }
    
    // MARK: - Helpers
    
    private func createTestTrack(
        id: UUID,
        title: String,
        artist: String? = "Test Artist",
        album: String? = "Test Album"
    ) -> AudioTrack {
        AudioTrack(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: 180,
            fileURL: URL(fileURLWithPath: "/test/\(title).mp3"),
            sourceType: .local
        )
    }
}
