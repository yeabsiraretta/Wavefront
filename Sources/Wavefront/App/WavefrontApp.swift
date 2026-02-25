import SwiftUI

#if os(iOS)
import UIKit
#endif

/// App struct for use by consuming apps
/// Usage in your app target:
/// ```swift
/// @main
/// struct MyApp: App {
///     @UIApplicationDelegateAdaptor(WavefrontAppDelegate.self) var appDelegate
///     var body: some Scene {
///         WindowGroup { WavefrontAppView() }
///     }
/// }
/// ```
public struct WavefrontApp {
    /// Configure the app delegate adaptor for background downloads
    /// Call this from your app's init if not using WavefrontAppDelegate directly
    public static func configure() {
        #if os(iOS)
        // Configuration is handled by WavefrontAppDelegate
        Logger.info("Wavefront configured", category: .general)
        #endif
    }
}

/// App entry point with splash screen animation
/// Shows particle scatter animation before revealing main content
public struct WavefrontAppView: View {
    @State private var splashFinished = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Main app content
            MainTabView()
                .opacity(splashFinished ? 1 : 0)
            
            // Splash screen overlay
            if !splashFinished {
                SplashScreenView(isFinished: $splashFinished)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: splashFinished)
    }
}

/// Legacy single-view for backward compatibility
public struct MusicLibraryViewLegacy: View {
    public init() {}
    
    public var body: some View {
        MusicLibraryView()
    }
}
