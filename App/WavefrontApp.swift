import SwiftUI
import Wavefront
#if os(iOS)
import AVFoundation
#endif

@main
struct WavefrontApp: App {
    init() {
        setupAudioSession()
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
    
    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
        #endif
    }
}
