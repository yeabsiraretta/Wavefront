import XCTest
@testable import Wavefront

final class AudioTrackTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitWithAllProperties() {
        let id = UUID()
        let date = Date()
        let url = URL(fileURLWithPath: "/test/song.mp3")
        
        let track = AudioTrack(
            id: id,
            title: "Test Song",
            artist: "Test Artist",
            album: "Test Album",
            duration: 180.0,
            fileURL: url,
            sourceType: .local,
            fileSize: 5_000_000,
            dateAdded: date
        )
        
        XCTAssertEqual(track.id, id)
        XCTAssertEqual(track.title, "Test Song")
        XCTAssertEqual(track.artist, "Test Artist")
        XCTAssertEqual(track.album, "Test Album")
        XCTAssertEqual(track.duration, 180.0)
        XCTAssertEqual(track.fileURL, url)
        XCTAssertEqual(track.sourceType, .local)
        XCTAssertEqual(track.fileSize, 5_000_000)
        XCTAssertEqual(track.dateAdded, date)
    }
    
    func testInitWithMinimalProperties() {
        let url = URL(fileURLWithPath: "/test/song.mp3")
        
        let track = AudioTrack(
            title: "Test Song",
            fileURL: url,
            sourceType: .local
        )
        
        XCTAssertNotEqual(track.id, UUID())  // Should have auto-generated ID
        XCTAssertEqual(track.title, "Test Song")
        XCTAssertNil(track.artist)
        XCTAssertNil(track.album)
        XCTAssertNil(track.duration)
        XCTAssertEqual(track.fileURL, url)
        XCTAssertEqual(track.sourceType, .local)
        XCTAssertNil(track.fileSize)
    }
    
    func testInitWithSMBSourceType() {
        let url = URL(string: "smb://192.168.1.1/music/song.mp3")!
        
        let track = AudioTrack(
            title: "SMB Song",
            fileURL: url,
            sourceType: .smb
        )
        
        XCTAssertEqual(track.sourceType, .smb)
        XCTAssertEqual(track.fileURL.scheme, "smb")
    }
    
    // MARK: - Equatable Tests
    
    func testEquality() {
        let id = UUID()
        let url = URL(fileURLWithPath: "/test/song.mp3")
        
        let track1 = AudioTrack(id: id, title: "Song", fileURL: url, sourceType: .local)
        let track2 = AudioTrack(id: id, title: "Song", fileURL: url, sourceType: .local)
        
        XCTAssertEqual(track1, track2)
    }
    
    func testInequalityWithDifferentIds() {
        let url = URL(fileURLWithPath: "/test/song.mp3")
        
        let track1 = AudioTrack(title: "Song", fileURL: url, sourceType: .local)
        let track2 = AudioTrack(title: "Song", fileURL: url, sourceType: .local)
        
        XCTAssertNotEqual(track1, track2)  // Different auto-generated IDs
    }
    
    // MARK: - Hashable Tests
    
    func testHashable() {
        let id = UUID()
        let url = URL(fileURLWithPath: "/test/song.mp3")
        
        let track1 = AudioTrack(id: id, title: "Song", fileURL: url, sourceType: .local)
        let track2 = AudioTrack(id: id, title: "Song", fileURL: url, sourceType: .local)
        
        var set = Set<AudioTrack>()
        set.insert(track1)
        set.insert(track2)
        
        XCTAssertEqual(set.count, 1)
    }
    
    func testHashableWithDifferentTracks() {
        let url1 = URL(fileURLWithPath: "/test/song1.mp3")
        let url2 = URL(fileURLWithPath: "/test/song2.mp3")
        
        let track1 = AudioTrack(title: "Song 1", fileURL: url1, sourceType: .local)
        let track2 = AudioTrack(title: "Song 2", fileURL: url2, sourceType: .local)
        
        var set = Set<AudioTrack>()
        set.insert(track1)
        set.insert(track2)
        
        XCTAssertEqual(set.count, 2)
    }
}
