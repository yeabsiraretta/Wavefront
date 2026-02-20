import SwiftUI

/// Sheet for configuring SMB server connections
struct SMBConfigurationSheet: View {
    @Binding var isPresented: Bool
    let onSave: (SMBConfiguration) -> Void
    
    @State private var serverAddress = ""
    @State private var shareName = ""
    @State private var username = "guest"
    @State private var password = ""
    @State private var basePath = "/"
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server Address", text: $serverAddress)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        #endif
                    
                    TextField("Share Name", text: $shareName)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("Server")
                } footer: {
                    Text("Example: 192.168.1.100 or nas.local")
                }
                
                Section("Authentication") {
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .textContentType(.username)
                    
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                
                Section {
                    TextField("Base Path", text: $basePath)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("Options")
                } footer: {
                    Text("Starting folder path (e.g., /Music)")
                }
                
                Section {
                    Button(action: saveConfiguration) {
                        HStack {
                            Spacer()
                            Text("Connect")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!isValid)
                }
            }
            .navigationTitle("Add SMB Share")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var isValid: Bool {
        !serverAddress.isEmpty && !shareName.isEmpty
    }
    
    private func saveConfiguration() {
        // Build the server URL
        let cleanAddress = serverAddress
            .replacingOccurrences(of: "smb://", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        guard let serverURL = URL(string: "smb://\(cleanAddress)") else {
            errorMessage = "Invalid server address"
            showingError = true
            return
        }
        
        let config = SMBConfiguration(
            serverURL: serverURL,
            shareName: shareName.trimmingCharacters(in: .whitespaces),
            username: username.isEmpty ? "guest" : username,
            password: password,
            basePath: basePath.isEmpty ? "/" : basePath
        )
        
        onSave(config)
        isPresented = false
    }
}

/// Row displaying an SMB source in settings
struct SMBSourceRow: View {
    let source: any AudioSource
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "server.rack")
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading) {
                Text(source.displayName)
                    .font(.body)
                Text(source.sourceId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Settings view for managing sources
struct SourcesSettingsView: View {
    @ObservedObject var viewModel: MusicLibraryViewModel
    @State private var showingAddSMB = false
    @State private var showingFolderPicker = false
    @State private var isConnecting = false
    @State private var connectionError: String?
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Default Documents folder
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text("Documents")
                                .font(.body)
                            Text("Default app storage")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    
                    // User-added local folders
                    ForEach(viewModel.localSources, id: \.sourceId) { source in
                        LocalSourceRow(source: source) {
                            Task {
                                await viewModel.removeLocalSource(sourceId: source.sourceId)
                                await viewModel.refreshTracks()
                            }
                        }
                    }
                    
                    Button {
                        showingFolderPicker = true
                    } label: {
                        Label("Add Folder", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Local Storage")
                } footer: {
                    Text("Add folders from your device to include in your music library.")
                }
                
                Section {
                    ForEach(viewModel.smbSources, id: \.sourceId) { source in
                        SMBSourceRow(source: source) {
                            Task {
                                await viewModel.removeSMBSource(sourceId: source.sourceId)
                                await viewModel.refreshTracks()
                            }
                        }
                    }
                    
                    Button {
                        showingAddSMB = true
                    } label: {
                        Label("Add SMB Share", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Network Shares")
                } footer: {
                    Text("Connect to SMB/CIFS network shares to stream music from your NAS or computer.")
                }
            }
            .navigationTitle("Sources")
            .sheet(isPresented: $showingAddSMB) {
                SMBConfigurationSheet(isPresented: $showingAddSMB) { config in
                    Task {
                        isConnecting = true
                        do {
                            try await viewModel.addSMBSource(configuration: config)
                            await viewModel.refreshTracks()
                        } catch {
                            connectionError = error.localizedDescription
                        }
                        isConnecting = false
                    }
                }
            }
            .sheet(isPresented: $showingFolderPicker) {
                FolderPickerView { url, bookmark in
                    Task {
                        do {
                            try await viewModel.addLocalSource(url: url, bookmark: bookmark)
                            await viewModel.refreshTracks()
                        } catch {
                            connectionError = error.localizedDescription
                        }
                    }
                    showingFolderPicker = false
                } onCancel: {
                    showingFolderPicker = false
                }
            }
            .overlay {
                if isConnecting {
                    ZStack {
                        Color.black.opacity(0.3)
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Connecting...")
                                .font(.subheadline)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .ignoresSafeArea()
                }
            }
            .alert("Error", isPresented: .init(
                get: { connectionError != nil },
                set: { if !$0 { connectionError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(connectionError ?? "")
            }
        }
    }
}

/// Row displaying a local source
struct LocalSourceRow: View {
    let source: LocalAudioSource
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading) {
                Text(source.displayName)
                    .font(.body)
                Text(source.baseDirectory.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Folder picker using document picker
#if os(iOS)
import UIKit

struct FolderPickerView: UIViewControllerRepresentable {
    let onSelect: (URL, Data?) -> Void
    let onCancel: () -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onCancel: onCancel)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL, Data?) -> Void
        let onCancel: () -> Void
        
        init(onSelect: @escaping (URL, Data?) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancel()
                return
            }
            
            // Create security-scoped bookmark
            var bookmark: Data?
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                bookmark = try? url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            }
            
            onSelect(url, bookmark)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
#else
// macOS version using NSOpenPanel
import AppKit

struct FolderPickerView: View {
    let onSelect: (URL, Data?) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        Color.clear
            .onAppear {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = false
                
                if panel.runModal() == .OK, let url = panel.url {
                    let bookmark = try? url.bookmarkData(
                        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    onSelect(url, bookmark)
                } else {
                    onCancel()
                }
            }
    }
}
#endif
