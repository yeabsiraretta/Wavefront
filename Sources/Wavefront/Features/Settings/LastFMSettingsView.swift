import SwiftUI

/// Settings view for Last.fm integration
struct LastFMSettingsView: View {
    @ObservedObject private var lastFMService = LastFMService.shared
    
    @State private var username = ""
    @State private var password = ""
    @State private var apiKey = ""
    @State private var apiSecret = ""
    @State private var isAuthenticating = false
    @State private var showingAPISetup = false
    @State private var errorMessage: String?
    
    @State private var recommendations: [RecommendedTrack] = []
    @State private var isLoadingRecommendations = false
    
    var body: some View {
        List {
            // Account Section
            Section {
                if lastFMService.isAuthenticated {
                    authenticatedView
                } else {
                    loginView
                }
            } header: {
                Label("Account", systemImage: "person.circle")
            }
            
            // Scrobbling Settings
            if lastFMService.isAuthenticated {
                Section {
                    Toggle("Enable Scrobbling", isOn: Binding(
                        get: { lastFMService.isScrobblingEnabled },
                        set: { lastFMService.setScrobblingEnabled($0) }
                    ))
                    
                    HStack {
                        Text("Tracks Scrobbled")
                        Spacer()
                        Text("\(lastFMService.scrobbleCount)")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Scrobbling", systemImage: "music.note.list")
                } footer: {
                    Text("Tracks are scrobbled after playing for 30 seconds or 50% of the track length.")
                }
                
                // Recommendations Section
                Section {
                    if isLoadingRecommendations {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if recommendations.isEmpty {
                        Button("Load Recommendations") {
                            loadRecommendations()
                        }
                    } else {
                        ForEach(recommendations) { track in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title)
                                    .font(.body)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        
                        Button("Refresh") {
                            loadRecommendations()
                        }
                    }
                } header: {
                    Label("Recommendations", systemImage: "sparkles")
                } footer: {
                    Text("Personalized recommendations based on your listening history.")
                }
            }
            
            // API Setup Section
            Section {
                Button {
                    showingAPISetup = true
                } label: {
                    HStack {
                        Text("Configure API Keys")
                        Spacer()
                        Image(systemName: "key")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("Advanced", systemImage: "gearshape")
            } footer: {
                Text("Get your API key from last.fm/api/account/create")
            }
        }
        .navigationTitle("Last.fm")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showingAPISetup) {
            apiSetupSheet
        }
    }
    
    // MARK: - Authenticated View
    
    private var authenticatedView: some View {
        Group {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text("Signed in as")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lastFMService.username ?? "Unknown")
                        .font(.headline)
                }
            }
            
            Button("Sign Out", role: .destructive) {
                lastFMService.logout()
            }
        }
    }
    
    // MARK: - Login View
    
    private var loginView: some View {
        Group {
            TextField("Username", text: $username)
                .textContentType(.username)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            
            SecureField("Password", text: $password)
                .textContentType(.password)
            
            Button {
                authenticate()
            } label: {
                if isAuthenticating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(username.isEmpty || password.isEmpty || isAuthenticating)
        }
    }
    
    // MARK: - API Setup Sheet
    
    private var apiSetupSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("API Key", text: $apiKey)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    
                    SecureField("API Secret", text: $apiSecret)
                } footer: {
                    Text("Create an API account at last.fm/api/account/create to get your keys.")
                }
            }
            .navigationTitle("API Configuration")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAPISetup = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        lastFMService.setCredentials(apiKey: apiKey, apiSecret: apiSecret)
                        showingAPISetup = false
                    }
                    .disabled(apiKey.isEmpty || apiSecret.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Actions
    
    private func authenticate() {
        isAuthenticating = true
        errorMessage = nil
        
        Task {
            do {
                try await lastFMService.authenticate(username: username, password: password)
                await MainActor.run {
                    isAuthenticating = false
                    username = ""
                    password = ""
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func loadRecommendations() {
        isLoadingRecommendations = true
        
        Task {
            do {
                let recs = try await lastFMService.getRecommendations(limit: 10)
                await MainActor.run {
                    recommendations = recs
                    isLoadingRecommendations = false
                }
            } catch {
                await MainActor.run {
                    isLoadingRecommendations = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LastFMSettingsView()
    }
}
