import SwiftUI
import RecompSources

@MainActor
struct LibraryView: View {
    @State private var library = LibraryModel()
    @State private var editing: LibrarySource?
    @State private var showingNotices = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Your games, on Apple TV").font(.largeTitle.bold())
                    Text("Connect a server and import Ocarina of Time for Shipwright.")
                        .foregroundStyle(.secondary)
                    if !library.importedROMs.isEmpty {
                        Text(library.importedROMs.count == 1 ? "1 verified ROM saved locally" : "\(library.importedROMs.count) verified ROMs saved locally").font(.headline)
                    }
                    HStack(spacing: 24) {
                        Button("Add SMB share") { editing = LibrarySource(kind: .smb) }
                        Button("Add RomM") { editing = LibrarySource(kind: .romm) }
                        if !library.importedROMs.isEmpty {
                            Button("Clear ROM cache") { Task { await library.clearCache() } }
                        }
                    }
                    ForEach(library.sources) { source in
                        HStack(spacing: 24) {
                            NavigationLink {
                                SourceBrowserView(source: source, library: library)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(source.name, systemImage: source.kind == .smb ? "externaldrive.connected.to.line.below" : "server.rack")
                                    Text(source.address).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Button("Edit") { editing = source }
                                .accessibilityLabel("Edit \(source.name)")
                            Button("Remove") { library.remove(source) }
                                .accessibilityLabel("Remove \(source.name)")
                        }
                    }
                    Text("ROM import is available. Native gameplay and game asset preparation are still being integrated.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(library.importedROMs) { ROMResultView(rom: $0) }
                    Button("Third-party notices") { showingNotices = true }
                }
                .padding(48)
            }
            .sheet(item: $editing) { source in SourceEditorView(source: source, library: library) }
            .sheet(isPresented: $showingNotices) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Button("Done") { showingNotices = false }
                        Text(SourceNotices.license).font(.caption)
                    }.padding(64)
                }
            }
            .task { await library.restoreCache() }
            .alert("Library", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
                Button("OK") { library.error = nil }
            } message: { Text(library.error ?? "") }
        }
    }
}

@MainActor
private struct SourceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: LibrarySource
    @State private var secret = ""
    @State private var connecting = false
    @State private var error: String?
    @State private var connection: Task<Void, Never>?
    @State private var loadedCredential = false
    let library: LibraryModel

    // A sheet owns a single editing draft; changes are committed only after successful access.
    init(source: LibrarySource, library: LibraryModel) {
        _source = State(initialValue: source); self.library = library
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Connect \(source.kind.title)").font(.title.bold())
                TextField("Connection name", text: $source.name)
                TextField(source.kind == .smb ? "smb://server/share/folder" : "https://romm.example.com", text: $source.address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if source.kind == .smb {
                    TextField("Username (empty for guest)", text: $source.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $secret)
                    TextField("Domain (optional)", text: $source.domain)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Require SMB3 encryption", isOn: $source.requireSMBEncryption)
                    Text("Use an account with read access. Include the share name in the address; folders are optional.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    SecureField("Client API token", text: $secret)
                    Toggle("Allow HTTP for this server", isOn: $source.allowHTTP)
                    Text("In RomM, create a Client API token with roms.read permission. HTTP sends the token without encryption; use it only on a trusted network.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.orange).font(.callout) }
                HStack(spacing: 24) {
                    Button(connecting ? "Connecting…" : "Connect and save") { connect() }
                        .disabled(connecting || !loadedCredential)
                    Button("Cancel") { connection?.cancel(); dismiss() }
                }
                if connecting { ProgressView() }
            }
            .padding(64)
            .frame(maxWidth: 1400)
        }
        .task {
            do { secret = try CredentialStore.load(source.id); loadedCredential = true }
            catch { self.error = error.localizedDescription }
        }
        .onDisappear { connection?.cancel(); secret = "" }
    }

    private func connect() {
        connection?.cancel(); error = nil; connecting = true
        let draft = source; let credential = secret
        connection = Task {
            defer { connecting = false }
            do {
                let provider = try ProviderFactory.make(source: draft, secret: credential)
                _ = try await provider.list(.root, search: "", offset: 0)
                try Task.checkCancellation()
                var saved = draft
                saved.address = saved.address.trimmingCharacters(in: .whitespacesAndNewlines)
                if saved.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { saved.name = saved.kind.title }
                try library.save(saved, secret: credential)
                dismiss()
            } catch { if !Task.isCancelled { self.error = userFacingNetworkError(error) } }
        }
    }
}

@MainActor
private struct SourceBrowserView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var browser: SourceBrowserModel
    @State private var showingBatchResults = false
    let library: LibraryModel

    init(source: LibrarySource, library: LibraryModel) {
        _browser = State(initialValue: SourceBrowserModel(source: source)); self.library = library
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Text(browser.title).font(.title.bold())
                if browser.isPlatformList {
                    Text("Choose a platform").font(.headline).foregroundStyle(.secondary)
                } else if browser.source.kind == .smb && browser.history.isEmpty {
                    Text("Open a platform folder, or import all ROMs from this folder.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
                    if !browser.history.isEmpty { Button("Up one level") { browser.back() } }
                    TextField(browser.searchPrompt, text: $browser.search)
                        .onSubmit { browser.refresh() }
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Search") { browser.refresh() }
                    Button("Refresh") { browser.refresh() }
                }
                .disabled(library.isImporting)
                if let location = browser.batchLocation {
                    HStack(spacing: 24) {
                        Button("Verify and import all ROMs") {
                            library.acquireAll(in: location, title: browser.title, source: browser.source)
                        }
                        .disabled(library.isImporting || browser.loading)
                        Text("Includes every page and subfolder, even when search is active.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Supported Ocarina of Time revisions are saved. Other games and compressed files appear in the results.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if library.isImporting {
                    HStack(spacing: 24) {
                        ProgressView(value: library.importFraction)
                            .frame(width: 300)
                        Text(library.importStatus).font(.callout)
                        Button("Cancel import") { library.cancelImport() }
                    }
                } else if !library.importStatus.isEmpty {
                    Text(library.importStatus).font(.callout)
                }
                if let report = library.batchReport {
                    HStack(spacing: 24) {
                        Text("\(report.results.count) of \(report.total) items processed").font(.callout)
                        Button("View import results") { showingBatchResults = true }
                    }
                    if let failure = report.failure { Text(failure).foregroundStyle(.orange) }
                } else if !browser.isPlatformList, !library.importStatus.isEmpty, let imported = library.imported {
                    ROMResultView(rom: imported)
                }
                if browser.loading { ProgressView("Loading library…") }
                ForEach(browser.entries) { entry in
                    Button {
                        if entry.folder != nil { browser.open(entry) }
                        else { library.acquire(entry, source: browser.source) }
                    } label: {
                        HStack(spacing: 20) {
                            Image(systemName: entry.folder != nil ? "folder" : "doc")
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.name)
                                Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let size = entry.size { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).font(.caption) }
                            Text(entry.folder != nil ? "Browse" : "Import and verify").font(.callout)
                        }
                    }
                    .disabled(library.isImporting || browser.loading || (entry.folder == nil && !entry.isROM))
                }
                if browser.entries.isEmpty && !browser.loading {
                    Text(browser.isPlatformList ? "No matching platforms." : "No matching ROMs in this platform or folder.")
                        .foregroundStyle(.secondary)
                }
                if browser.nextOffset != nil {
                    Button("Load more") { browser.refresh(more: true) }.disabled(browser.loading || library.isImporting)
                }
            }
            .padding(48)
        }
        .sheet(isPresented: $showingBatchResults) {
            BatchResultsView(library: library)
        }
        .onAppear { if !library.isImporting { browser.refresh() } }
        .onDisappear {
            if !showingBatchResults { browser.cancel(); if library.isImporting { library.cancelImport() } }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background { browser.cancel(); if library.isImporting { library.cancelImport() } }
        }
        .alert("Connection", isPresented: Binding(get: { browser.error != nil || library.error != nil }, set: {
            if !$0 { browser.error = nil; library.error = nil }
        })) {
            Button("OK") { browser.error = nil; library.error = nil }
        } message: { Text(browser.error ?? library.error ?? "") }
    }
}

@MainActor
private struct BatchResultsView: View {
    @Environment(\.dismiss) private var dismiss
    let library: LibraryModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Button("Done") { dismiss() }
                Text(library.batchTitle).font(.title.bold())
                if let report = library.batchReport {
                    Text(library.isImporting ? library.importStatus : report.summary).font(.headline)
                    if report.cancelled { Text("Completed imports were kept. Run the batch again to check the remaining files.") }
                    if let failure = report.failure { Text(failure).foregroundStyle(.orange) }
                    if report.results.isEmpty { Text(library.isImporting ? "Scanning for ROM files…" : "No files were processed.") }
                    ForEach(report.results) { result in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(result.name, systemImage: result.outcome == .imported ? "checkmark.seal" : "info.circle")
                                .font(.headline)
                            Text("\(result.outcome.rawValue.capitalized) · \(result.message)").font(.callout)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                        .focusable()
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(64)
        }
        .frame(minWidth: 1100, idealWidth: 1400, minHeight: 650, idealHeight: 850)
    }
}

private struct ROMResultView: View {
    let rom: ImportedROM
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(rom.recognized ? "Ocarina of Time ROM verified" : "ROM revision not supported",
                  systemImage: rom.recognized ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.headline)
            Text(rom.name).font(.callout)
            if let revision = rom.revision {
                Text("\(revision) · Native gameplay is not available in this build.")
            } else { Text("These bytes do not match Shipwright's accepted ROM revisions. The file was not cached.") }
            Text("SHA-1: \(rom.sha1)").font(.caption.monospaced())
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}
