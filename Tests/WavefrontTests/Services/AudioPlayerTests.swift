import XCTest
import AVFoundation
@testable import Wavefront

final class AudioPlayerTests: XCTestCase {
    
    var manager: AudioSourceManager!
    var player: AudioPlayer!
    var mockDelegate: MockAudioPlayerDelegate!
    
    override func setUpWithError() throws {
        manager = AudioSourceManager()
        player = AudioPlayer(sourceManager: manager)
        mockDelegate = MockAudioPlayerDelegate()
        player.delegate = mockDelegate
    }
    
    override func tearDownWithError() throws {
        player.stop()
        player = nil
        manager = nil
        mockDelegate = nil
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        XCTAssertEqual(player.state, .idle)
        XCTAssertNil(player.currentTrack)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTime, 0)
    }
    
    func testInitialVolume() {
        // Volume should default to 1.0 (100%)
        XCTAssertEqual(player.volume, 1.0, accuracy: 0.01)
    }
    
    // MARK: - Playback Control Tests
    
    func testPauseWhenNotPlaying() {
        player.pause()
        XCTAssertEqual(player.state, .idle)
    }
    
    func testResumeWhenNotPaused() {
        player.resume()
        XCTAssertEqual(player.state, .idle)
    }
    
    func testStopResetsState() {
        player.stop()
        XCTAssertEqual(player.state, .stopped)
    }
    
    func testTogglePlayPauseFromIdle() {
        player.togglePlayPause()
        // Should remain idle since nothing is playing
        XCTAssertEqual(player.state, .idle)
    }
    
    // MARK: - Volume Tests
    
    func testSetVolume() {
        player.volume = 0.5
        XCTAssertEqual(player.volume, 0.5, accuracy: 0.01)
    }
    
    // MARK: - Seek Tests
    
    func testSeekForwardCalculation() {
        // Just verifying the seek methods don't crash when nothing is playing
        player.seekForward(by: 15)
        XCTAssertEqual(player.currentTime, 0)
    }
    
    func testSeekBackwardCalculation() {
        player.seekBackward(by: 15)
        XCTAssertEqual(player.currentTime, 0)
    }
    
    // MARK: - Delegate Tests
    
    func testDelegateCalledOnStateChange() {
        player.stop()
        
        // Give a moment for state change to propagate
        let expectation = XCTestExpectation(description: "State change")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.mockDelegate.stateChanges.contains(.stopped))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Play State Tests
    
    func testIsPlayingReturnsFalseWhenIdle() {
        XCTAssertFalse(player.isPlaying)
    }
    
    func testIsPlayingReturnsFalseWhenStopped() {
        player.stop()
        XCTAssertFalse(player.isPlaying)
    }
}

// MARK: - Mock Delegate

final class MockAudioPlayerDelegate: AudioPlayerDelegate, @unchecked Sendable {
    var stateChanges: [PlaybackState] = []
    var progressUpdates: [(current: TimeInterval, duration: TimeInterval)] = []
    var finishedTracks: [AudioTrack] = []
    var errors: [Error] = []
    
    func audioPlayer(_ player: AudioPlayer, didChangeState state: PlaybackState) {
        stateChanges.append(state)
    }
    
    func audioPlayer(_ player: AudioPlayer, didUpdateProgress currentTime: TimeInterval, duration: TimeInterval) {
        progressUpdates.append((currentTime, duration))
    }
    
    func audioPlayer(_ player: AudioPlayer, didFinishPlaying track: AudioTrack) {
        finishedTracks.append(track)
    }
    
    func audioPlayer(_ player: AudioPlayer, didFailWithError error: Error) {
        errors.append(error)
    }
    
    func reset() {
        stateChanges = []
        progressUpdates = []
        finishedTracks = []
        errors = []
    }
}
