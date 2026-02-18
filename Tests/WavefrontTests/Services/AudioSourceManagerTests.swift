import XCTest
@testable import Wavefront

final class AudioSourceManagerTests: XCTestCase {
    
    var manager: AudioSourceManager!
    var tempDirectory: URL!
    
    override func setUpWithError() throws {
        manager = AudioSourceManager()
        
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WavefrontManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        manager = nil
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    // MARK: - Registration Tests
    
    func testRegisterSource() async {
        let source = LocalAudioSource(
            sourceId: "test-source",
            displayName: "Test",
            baseDirectory: tempDirectory
        )
        
        await manager.register(source)
        
        let retrieved = await manager.source(for: "test-source")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.sourceId, "test-source")
    }
    
    func testRegisterMultipleSources() async {
        let source1 = LocalAudioSource(
            sourceId: "source-1",
            displayName: "Source 1",
            baseDirectory: tempDirectory
        )
        let source2 = LocalAudioSource(
            sourceId: "source-2",
            displayName: "Source 2",
            baseDirectory: tempDirectory
        )
        
        await manager.register(source1)
        await manager.register(source2)
        
        let allSources = await manager.allSources()
        XCTAssertEqual(allSources.count, 2)
    }
    
    func testRegisterOverwritesExistingSourceWithSameId() async {
        let source1 = LocalAudioSource(
            sourceId: "same-id",
            displayName: "Original",
            baseDirectory: tempDirectory
        )
        let source2 = LocalAudioSource(
            sourceId: "same-id",
            displayName: "Replacement",
            baseDirectory: tempDirectory
        )
        
        await manager.register(source1)
        await manager.register(source2)
        
        let allSources = await manager.allSources()
        XCTAssertEqual(allSources.count, 1)
        XCTAssertEqual(allSources.first?.displayName, "Replacement")
    }
    
    // MARK: - Unregistration Tests
    
    func testUnregisterSource() async {
        let source = LocalAudioSource(
            sourceId: "to-remove",
            displayName: "Test",
            baseDirectory: tempDirectory
        )
        
        await manager.register(source)
        await manager.unregister(sourceId: "to-remove")
        
        let retrieved = await manager.source(for: "to-remove")
        XCTAssertNil(retrieved)
    }
    
    func testUnregisterNonExistentSourceDoesNothing() async {
        await manager.unregister(sourceId: "nonexistent")
        // Should not crash
    }
    
    // MARK: - Source Retrieval Tests
    
    func testSourceForIdReturnsNilForUnknownId() async {
        let retrieved = await manager.source(for: "unknown")
        XCTAssertNil(retrieved)
    }
    
    func testAllSourcesReturnsEmptyArrayWhenNoSources() async {
        let sources = await manager.allSources()
        XCTAssertEqual(sources.count, 0)
    }
    
    // MARK: - Available Sources Tests
    
    func testAvailableSourcesReturnsOnlyAvailable() async {
        let existingDir = tempDirectory.appendingPathComponent("existing")
        try? FileManager.default.createDirectory(at: existingDir, withIntermediateDirectories: true)
        
        let availableSource = LocalAudioSource(
            sourceId: "available",
            displayName: "Available",
            baseDirectory: existingDir
        )
        
        let nonExistentDir = tempDirectory.appendingPathComponent("nonexistent-\(UUID().uuidString)")
        let unavailableSource = LocalAudioSource(
            sourceId: "unavailable",
            displayName: "Unavailable",
            baseDirectory: nonExistentDir
        )
        
        await manager.register(availableSource)
        await manager.register(unavailableSource)
        
        let available = await manager.availableSources()
        
        XCTAssertEqual(available.count, 1)
        XCTAssertEqual(available.first?.sourceId, "available")
    }
    
    // MARK: - Fetch All Tracks Tests
    
    func testFetchAllTracksFromMultipleSources() async throws {
        let dir1 = tempDirectory.appendingPathComponent("source1")
        let dir2 = tempDirectory.appendingPathComponent("source2")
        
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        
        try Data().write(to: dir1.appendingPathComponent("song1.mp3"))
        try Data().write(to: dir2.appendingPathComponent("song2.mp3"))
        
        let source1 = LocalAudioSource(sourceId: "s1", displayName: "S1", baseDirectory: dir1)
        let source2 = LocalAudioSource(sourceId: "s2", displayName: "S2", baseDirectory: dir2)
        
        await manager.register(source1)
        await manager.register(source2)
        
        let tracks = await manager.fetchAllTracks()
        
        XCTAssertEqual(tracks.count, 2)
    }
    
    func testFetchAllTracksReturnsEmptyWhenNoSources() async {
        let tracks = await manager.fetchAllTracks()
        XCTAssertEqual(tracks.count, 0)
    }
    
    func testFetchAllTracksContinuesOnSourceError() async throws {
        let validDir = tempDirectory.appendingPathComponent("valid")
        try FileManager.default.createDirectory(at: validDir, withIntermediateDirectories: true)
        try Data().write(to: validDir.appendingPathComponent("song.mp3"))
        
        let validSource = LocalAudioSource(sourceId: "valid", displayName: "Valid", baseDirectory: validDir)
        let invalidSource = LocalAudioSource(
            sourceId: "invalid",
            displayName: "Invalid",
            baseDirectory: tempDirectory.appendingPathComponent("nonexistent")
        )
        
        await manager.register(validSource)
        await manager.register(invalidSource)
        
        let tracks = await manager.fetchAllTracks()
        
        // Should still get tracks from valid source
        XCTAssertEqual(tracks.count, 1)
    }
    
    // MARK: - Fetch Tracks From Source Tests
    
    func testFetchTracksFromSpecificSource() async throws {
        let dir = tempDirectory.appendingPathComponent("specific")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent("song.mp3"))
        
        let source = LocalAudioSource(sourceId: "specific", displayName: "Specific", baseDirectory: dir)
        await manager.register(source)
        
        let tracks = try await manager.fetchTracks(from: "specific")
        
        XCTAssertEqual(tracks.count, 1)
    }
    
    func testFetchTracksFromNonExistentSourceThrowsError() async {
        do {
            _ = try await manager.fetchTracks(from: "nonexistent")
            XCTFail("Should throw error")
        } catch let error as AudioSourceError {
            XCTAssertEqual(error, AudioSourceError.sourceUnavailable)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Get Playable URL Tests
    
    func testGetPlayableURLForTrack() async throws {
        let dir = tempDirectory.appendingPathComponent("playable")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let fileURL = dir.appendingPathComponent("song.mp3")
        try Data().write(to: fileURL)
        
        let source = LocalAudioSource(sourceId: "play", displayName: "Play", baseDirectory: dir)
        await manager.register(source)
        
        let track = AudioTrack(title: "Song", fileURL: fileURL, sourceType: .local)
        
        let playableURL = try await manager.getPlayableURL(for: track)
        XCTAssertEqual(playableURL, fileURL)
    }
    
    func testGetPlayableURLThrowsForUnknownTrack() async throws {
        let unknownURL = tempDirectory.appendingPathComponent("unknown.mp3")
        let track = AudioTrack(title: "Unknown", fileURL: unknownURL, sourceType: .local)
        
        do {
            _ = try await manager.getPlayableURL(for: track)
            XCTFail("Should throw error")
        } catch let error as AudioSourceError {
            if case .trackNotFound = error {
                // Expected
            } else {
                XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
