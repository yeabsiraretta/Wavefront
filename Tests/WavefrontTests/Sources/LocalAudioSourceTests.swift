import XCTest
@testable import Wavefront

final class LocalAudioSourceTests: XCTestCase {
    
    var tempDirectory: URL!
    var source: LocalAudioSource!
    
    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WavefrontTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        source = LocalAudioSource(
            sourceId: "test-local",
            displayName: "Test Local",
            baseDirectory: tempDirectory
        )
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        source = nil
    }
    
    // MARK: - Initialization Tests
    
    func testInitWithDefaultDocumentsDirectory() throws {
        let defaultSource = try LocalAudioSource()
        
        XCTAssertEqual(defaultSource.sourceId, "local-storage")
        XCTAssertEqual(defaultSource.displayName, "Local Storage")
        XCTAssertEqual(defaultSource.sourceType, .local)
    }
    
    func testInitWithCustomDirectory() {
        XCTAssertEqual(source.sourceId, "test-local")
        XCTAssertEqual(source.displayName, "Test Local")
        XCTAssertEqual(source.sourceType, .local)
    }
    
    // MARK: - Availability Tests
    
    func testIsAvailableWithExistingDirectory() async {
        let available = await source.isAvailable
        XCTAssertTrue(available)
    }
    
    func testIsAvailableWithNonExistingDirectory() async {
        let nonExistentDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NonExistent-\(UUID().uuidString)")
        
        let unavailableSource = LocalAudioSource(
            sourceId: "unavailable",
            displayName: "Unavailable",
            baseDirectory: nonExistentDir
        )
        
        let available = await unavailableSource.isAvailable
        XCTAssertFalse(available)
    }
    
    // MARK: - Fetch Tracks Tests
    
    func testFetchTracksFromEmptyDirectory() async throws {
        let tracks = try await source.fetchTracks()
        XCTAssertEqual(tracks.count, 0)
    }
    
    func testFetchTracksFindsAudioFiles() async throws {
        // Create test audio files (empty files with audio extensions)
        let mp3URL = tempDirectory.appendingPathComponent("test.mp3")
        let m4aURL = tempDirectory.appendingPathComponent("test.m4a")
        
        try Data().write(to: mp3URL)
        try Data().write(to: m4aURL)
        
        let tracks = try await source.fetchTracks()
        
        XCTAssertEqual(tracks.count, 2)
        XCTAssertTrue(tracks.allSatisfy { $0.sourceType == .local })
    }
    
    func testFetchTracksIgnoresNonAudioFiles() async throws {
        let txtURL = tempDirectory.appendingPathComponent("readme.txt")
        let pdfURL = tempDirectory.appendingPathComponent("document.pdf")
        let mp3URL = tempDirectory.appendingPathComponent("song.mp3")
        
        try Data().write(to: txtURL)
        try Data().write(to: pdfURL)
        try Data().write(to: mp3URL)
        
        let tracks = try await source.fetchTracks()
        
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks.first?.title, "song")
    }
    
    func testFetchTracksRecursivelyScansSubdirectories() async throws {
        let subdir = tempDirectory.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        
        let rootMP3 = tempDirectory.appendingPathComponent("root.mp3")
        let subMP3 = subdir.appendingPathComponent("sub.mp3")
        
        try Data().write(to: rootMP3)
        try Data().write(to: subMP3)
        
        let tracks = try await source.fetchTracks()
        
        XCTAssertEqual(tracks.count, 2)
    }
    
    func testFetchTracksAtSpecificPath() async throws {
        let subdir = tempDirectory.appendingPathComponent("album")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        
        let rootMP3 = tempDirectory.appendingPathComponent("root.mp3")
        let albumMP3 = subdir.appendingPathComponent("track.mp3")
        
        try Data().write(to: rootMP3)
        try Data().write(to: albumMP3)
        
        let tracks = try await source.fetchTracks(at: "album")
        
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks.first?.title, "track")
    }
    
    func testFetchTracksAtInvalidPathThrowsError() async {
        do {
            _ = try await source.fetchTracks(at: "nonexistent")
            XCTFail("Should throw error for invalid path")
        } catch let error as AudioSourceError {
            if case .invalidPath = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    func testFetchTracksExtractsTitleFromFilename() async throws {
        let songURL = tempDirectory.appendingPathComponent("My Favorite Song.mp3")
        try Data().write(to: songURL)
        
        let tracks = try await source.fetchTracks()
        
        XCTAssertEqual(tracks.first?.title, "My Favorite Song")
    }
    
    // MARK: - Track Exists Tests
    
    func testTrackExistsReturnsTrueForExistingFile() async throws {
        let mp3URL = tempDirectory.appendingPathComponent("exists.mp3")
        try Data().write(to: mp3URL)
        
        let track = AudioTrack(title: "Exists", fileURL: mp3URL, sourceType: .local)
        
        let exists = await source.trackExists(track)
        XCTAssertTrue(exists)
    }
    
    func testTrackExistsReturnsFalseForNonExistingFile() async {
        let nonExistentURL = tempDirectory.appendingPathComponent("nonexistent.mp3")
        let track = AudioTrack(title: "Nonexistent", fileURL: nonExistentURL, sourceType: .local)
        
        let exists = await source.trackExists(track)
        XCTAssertFalse(exists)
    }
    
    func testTrackExistsReturnsFalseForSMBTrack() async throws {
        let smbURL = URL(string: "smb://192.168.1.1/share/song.mp3")!
        let track = AudioTrack(title: "SMB Song", fileURL: smbURL, sourceType: .smb)
        
        let exists = await source.trackExists(track)
        XCTAssertFalse(exists)
    }
    
    // MARK: - Get Playable URL Tests
    
    func testGetPlayableURLReturnsFileURL() async throws {
        let mp3URL = tempDirectory.appendingPathComponent("playable.mp3")
        try Data().write(to: mp3URL)
        
        let track = AudioTrack(title: "Playable", fileURL: mp3URL, sourceType: .local)
        
        let playableURL = try await source.getPlayableURL(for: track)
        XCTAssertEqual(playableURL, mp3URL)
    }
    
    func testGetPlayableURLThrowsForNonLocalTrack() async {
        let smbURL = URL(string: "smb://192.168.1.1/share/song.mp3")!
        let track = AudioTrack(title: "SMB Song", fileURL: smbURL, sourceType: .smb)
        
        do {
            _ = try await source.getPlayableURL(for: track)
            XCTFail("Should throw error for SMB track")
        } catch let error as AudioSourceError {
            if case .trackNotFound = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    func testGetPlayableURLThrowsForMissingFile() async {
        let nonExistentURL = tempDirectory.appendingPathComponent("missing.mp3")
        let track = AudioTrack(title: "Missing", fileURL: nonExistentURL, sourceType: .local)
        
        do {
            _ = try await source.getPlayableURL(for: track)
            XCTFail("Should throw error for missing file")
        } catch let error as AudioSourceError {
            if case .trackNotFound = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - All Audio Formats Tests
    
    func testFetchTracksRecognizesAllSupportedFormats() async throws {
        let formats = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "alac"]
        
        for format in formats {
            let url = tempDirectory.appendingPathComponent("test.\(format)")
            try Data().write(to: url)
        }
        
        let tracks = try await source.fetchTracks()
        
        XCTAssertEqual(tracks.count, formats.count)
    }
}
