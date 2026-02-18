import SwiftUI

/// App entry point - used when imported as library
/// For standalone app, use App/WavefrontApp.swift
public struct WavefrontAppView: View {
    public init() {}
    
    public var body: some View {
        MainTabView()
    }
}

/// Legacy single-view for backward compatibility
public struct MusicLibraryViewLegacy: View {
    public init() {}
    
    public var body: some View {
        MusicLibraryView()
    }
}
