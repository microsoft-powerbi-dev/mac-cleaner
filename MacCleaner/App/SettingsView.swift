import AppKit
import SwiftUI

/// The ⌘, Settings window.
struct SettingsView: View {
    var body: some View {
        SettingsTabs()
            .frame(width: 600, height: 560)
    }
}

/// The sidebar "Settings" page.
struct SettingsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings").font(.title2.bold()).padding()
            Divider()
            SettingsTabs()
        }
    }
}

struct SettingsTabs: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general = "General", analyzer = "Disk Analyzer", uninstaller = "Uninstaller", ai = "AI"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .analyzer: return "chart.pie"
            case .uninstaller: return "trash.square"
            case .ai: return "sparkles"
            }
        }
    }

    @AppStorage("settings.tab") private var tab: Tab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsView().tabItem { Label(Tab.general.rawValue, systemImage: Tab.general.symbol) }.tag(Tab.general)
            AnalyzerSettingsView().tabItem { Label(Tab.analyzer.rawValue, systemImage: Tab.analyzer.symbol) }.tag(Tab.analyzer)
            UninstallerSettingsView().tabItem { Label(Tab.uninstaller.rawValue, systemImage: Tab.uninstaller.symbol) }.tag(Tab.uninstaller)
            AISettingsView().tabItem { Label(Tab.ai.rawValue, systemImage: Tab.ai.symbol) }.tag(Tab.ai)
        }
        .padding(.top, 8)
    }
}

// MARK: General

struct GeneralSettingsView: View {
    @Bindable private var menuBar = MenuBarSetting.shared
    @State private var hasFullDiskAccess = Permissions.hasFullDiskAccess
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Menu bar") {
                Toggle("Show CPU and memory monitor in the menu bar", isOn: $menuBar.isShown)
            }
            Section("Permissions") {
                HStack {
                    Label(hasFullDiskAccess ? "Full Disk Access is on" : "Full Disk Access is off",
                          systemImage: hasFullDiskAccess ? "checkmark.shield" : "lock.trianglebadge.exclamationmark")
                        .foregroundStyle(hasFullDiskAccess ? .green : .orange)
                    Spacer()
                    Button("Open System Settings") { Permissions.openFullDiskAccessSettings() }
                    Button("Check Again") { hasFullDiskAccess = Permissions.hasFullDiskAccess }
                }
                Text("Without it, MacCleaner can't see some caches, Mail downloads or the Trash. After rebuilding the app you may need to remove and re-add it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Safety") {
                Label("Cleaning, uninstalling and deduplicating move items to the Trash.", systemImage: "trash")
                Label("Moving to other storage copies and verifies before trashing the original.", systemImage: "checkmark.seal")
                Label("System folders, iCloud, Keychains, Mail, Messages and Photos are always protected.", systemImage: "lock.shield")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Section {
                HStack {
                    Spacer()
                    Button("Reset All Settings…") { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings to their defaults?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                Prefs.resetAll()
                menuBar.reload()
            }
        } message: {
            Text("AI API keys in the Keychain and your usage history are kept.")
        }
    }
}

// MARK: Disk Analyzer

struct AnalyzerSettingsView: View {
    @AppStorage(Prefs.defaultScanPath) private var defaultScanPath = ""
    @AppStorage(Prefs.hogMinSize) private var hogMinSize = 1_000_000_000
    @AppStorage(Prefs.oldFileDays) private var oldFileDays = 365
    @AppStorage(Prefs.largestMinSize) private var largestMinSize = Int(FileFilter.MinSize.hundredMB.rawValue)
    @AppStorage(Prefs.duplicateMinSize) private var duplicateMinSize = 1_000_000
    @AppStorage(Prefs.recordDailyHistory) private var recordDailyHistory = true
    @AppStorage(Prefs.historyLimit) private var historyLimit = 365
    @State private var confirmClear = false
    @State private var historyCount = UsageHistoryStore.standard.load().count

    var body: some View {
        Form {
            Section("Scanning") {
                LabeledContent("Default folder") {
                    HStack {
                        Text(defaultScanPath.isEmpty ? "Home folder" : (defaultScanPath as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Choose…", action: chooseFolder)
                        if !defaultScanPath.isEmpty {
                            Button("Use Home") { defaultScanPath = "" }
                        }
                    }
                }
                Picker("Space hog minimum", selection: $hogMinSize) {
                    ForEach([500_000_000, 1_000_000_000, 5_000_000_000, 10_000_000_000], id: \.self) {
                        Text(Format.bytes(Int64($0))).tag($0)
                    }
                }
                Picker("Largest tab starts at", selection: $largestMinSize) {
                    ForEach(FileFilter.MinSize.allCases) { Text($0.title).tag(Int($0.rawValue)) }
                }
                Picker("Old files: not opened for", selection: $oldFileDays) {
                    Text("3 months").tag(90)
                    Text("6 months").tag(182)
                    Text("1 year").tag(365)
                    Text("2 years").tag(730)
                    Text("3 years").tag(1095)
                }
                Picker("Duplicates: ignore files under", selection: $duplicateMinSize) {
                    Text("1 MB").tag(1_000_000)
                    Text("10 MB").tag(10_000_000)
                    Text("100 MB").tag(100_000_000)
                }
                Text("Changes apply to the next scan or the next time you open the tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Usage history") {
                Toggle("Record disk usage once a day when the app opens", isOn: $recordDailyHistory)
                Picker("Keep the last", selection: $historyLimit) {
                    Text("90 snapshots").tag(90)
                    Text("180 snapshots").tag(180)
                    Text("365 snapshots").tag(365)
                    Text("1,000 snapshots").tag(1000)
                }
                HStack {
                    Text("\(historyCount) snapshots saved").foregroundStyle(.secondary)
                    Spacer()
                    Button("Show File") {
                        NSWorkspace.shared.activateFileViewerSelecting([UsageHistoryStore.standard.fileURL])
                    }
                    .disabled(historyCount == 0)
                    Button("Clear History…") { confirmClear = true }.disabled(historyCount == 0)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all saved usage history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) {
                UsageHistoryStore.standard.clear()
                historyCount = 0
            }
        }
        .onAppear { historyCount = UsageHistoryStore.standard.load().count }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Prefs.defaultScanURL
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url { defaultScanPath = url.path }
    }
}

// MARK: Uninstaller

struct UninstallerSettingsView: View {
    @AppStorage(Prefs.uninstallerSort) private var sort: AppSort = .name
    @AppStorage(Prefs.uninstallerAscending) private var ascending = true
    @AppStorage(Prefs.showAppleApps) private var showAppleApps = true

    var body: some View {
        Form {
            Section("App list") {
                Picker("Sort by", selection: $sort) {
                    ForEach(AppSort.allCases) { Text($0.title).tag($0) }
                }
                Picker("Order", selection: $ascending) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
                .pickerStyle(.segmented)
                Toggle("Show Apple apps (they can't be uninstalled)", isOn: $showAppleApps)
            }
            Section {
                Label("Leftovers matched only by a related identifier, shared group or app name start unchecked.", systemImage: "info.circle")
                Label("\"Last Used\" comes from Spotlight. Apps you've never opened, or on volumes Spotlight doesn't index, show as never used.", systemImage: "magnifyingglass")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

// MARK: AI

/// Choose the AI provider for the Disk Analyzer and enter its endpoint, model and key.
struct AISettingsView: View {
    @State private var settings = AISettings.load()
    @State private var config = LLMProviderConfig()
    @State private var apiKey = ""
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, running, ok(String), failed(String)
    }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(LLMProviderKind.allCases) { Text($0.title).tag($0) }
                }
                Text(settings.provider.setupHint).font(.caption).foregroundStyle(.secondary)
            }

            if settings.provider == .onDevice {
                Section {
                    if let reason = DiskAdvisor.onDeviceUnavailableReason {
                        Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text("Until it's available, MacCleaner uses its built-in rules.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Label("Ready. Nothing leaves this Mac.", systemImage: "checkmark.circle").foregroundStyle(.green)
                    }
                }
            } else {
                Section("Connection") {
                    TextField("Endpoint", text: $config.endpoint, prompt: Text(settings.provider.defaultConfig.endpoint))
                        .textContentType(.URL)
                    if settings.provider.usesDeployment {
                        TextField("Deployment", text: $config.deployment, prompt: Text("e.g. gpt-4o-mini"))
                        TextField("API version", text: $config.apiVersion, prompt: Text("2024-10-21"))
                    } else {
                        TextField("Model", text: $config.model, prompt: Text(settings.provider.defaultConfig.model.isEmpty ? "model name" : settings.provider.defaultConfig.model))
                    }
                    SecureField(settings.provider.needsAPIKey ? "API key" : "API key (optional)", text: $apiKey)
                    Text("The key is stored in your login Keychain.").font(.caption).foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Toggle("Send only the last two folders of each path", isOn: $settings.shortenPaths)
                    Label {
                        Text(settings.provider.isCloud
                             ? "When you use Explain with AI or Analyze Results, file paths, names, sizes, dates and categories are sent to \(settings.provider.title). File contents are never sent. Nothing is sent until you ask."
                             : "Requests go to the endpoint above, which may be this Mac or a machine on your network. File contents are never sent.")
                    } icon: {
                        Image(systemName: settings.provider.isCloud ? "network" : "house")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Button("Test Connection") { Task { await test() } }
                            .disabled(testState == .running)
                        switch testState {
                        case .idle: EmptyView()
                        case .running: ProgressView().controlSize(.small)
                        case .ok(let message): Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failed(let message): Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(3)
                        }
                        Spacer()
                        Button("Reset to Defaults") {
                            config = settings.provider.defaultConfig
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadProvider(settings.provider) }
        .onChange(of: settings.provider) { old, new in
            storeProvider(old)
            loadProvider(new)
            settings.save()
        }
        .onChange(of: config) { storeProvider(settings.provider); settings.save() }
        .onChange(of: settings.shortenPaths) { settings.save() }
        .onChange(of: apiKey) { AISettings.setAPIKey(apiKey, for: settings.provider) }
        .onDisappear { storeProvider(settings.provider); settings.save() }
    }

    private func loadProvider(_ kind: LLMProviderKind) {
        config = settings.config(for: kind)
        apiKey = AISettings.apiKey(for: kind) ?? ""
        testState = .idle
    }

    private func storeProvider(_ kind: LLMProviderKind) {
        guard kind != .onDevice else { return }
        settings.configs[kind] = config
    }

    private func test() async {
        storeProvider(settings.provider)
        settings.save()
        let client = RemoteLLMClient(kind: settings.provider, config: config, apiKey: apiKey, timeout: 30, maxTokens: 50)
        if let problem = client.configurationProblem {
            testState = .failed("Please \(problem).")
            return
        }
        testState = .running
        do {
            let reply = try await client.complete(system: "Reply with a JSON object only.", user: #"Return {"ok": true}"#)
            testState = .ok("Connected · \(reply.prefix(40))")
        } catch {
            testState = .failed(error.localizedDescription)
        }
    }
}
