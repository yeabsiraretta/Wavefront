import Foundation
#if os(iOS)
import UIKit
import BackgroundTasks

/// Helper class to configure app delegate functionality
/// Call these methods from your AppDelegate or SceneDelegate
public final class AppDelegateHelper {
    
    /// Configure background download handling
    /// Call this from application(_:didFinishLaunchingWithOptions:)
    public static func configureBackgroundDownloads() {
        BackgroundDownloadManager.shared.registerBackgroundTasks()
        Logger.info("Background downloads configured", category: .network)
    }
    
    /// Handle background URL session events
    /// Call this from application(_:handleEventsForBackgroundURLSession:completionHandler:)
    public static func handleBackgroundURLSession(
        identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundDownloadManager.shared.handleEventsForBackgroundURLSession(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }
    
    /// Request notification permissions for download complete alerts
    public static func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if granted {
                Logger.info("Notification permissions granted", category: .general)
            } else if let error = error {
                Logger.error("Notification permission error", error: error, category: .general)
            }
        }
    }
    
    /// Configure audio session for background playback
    public static func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            Logger.info("Audio session configured for background playback", category: .audio)
        } catch {
            Logger.error("Failed to configure audio session", error: error, category: .audio)
        }
    }
}

import AVFoundation
import UserNotifications
#endif
