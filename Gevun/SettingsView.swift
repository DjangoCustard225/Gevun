import SwiftUI
import GevunCore

struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @AppStorage("scrobbleEnabled") private var scrobble = false
    @AppStorage(PlaybackSettings.wifiQualityKey) private var wifiQuality = "original"
    @AppStorage(PlaybackSettings.cellularQualityKey) private var cellularQuality = "original"
    @State private var editing: Instance?
    @State private var deleting: Instance?
    @State private var testing = false

    var body: some View {
        List {
            Section("Servers") {
                ForEach(store.instances) { instance in
                    HStack(spacing: 8) {
                        Button {
                            if instance.id != store.activeID { store.activate(instance.id) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(
                                    systemName: instance.id == store.activeID ? "checkmark.circle.fill" : "server.rack"
                                )
                                .foregroundStyle(instance.id == store.activeID ? theme.accent : theme.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(instance.name).font(.headline).foregroundStyle(.white)
                                    Text(instance.url.host ?? "").font(.caption).foregroundStyle(theme.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(.plain).accessibilityHint(
                            instance.id == store.activeID ? "Active server" : "Switch to this server")
                        Menu {
                            Button("Edit", systemImage: "pencil") { editing = instance }
                            if instance.id == store.activeID {
                                Button("Test connection", systemImage: "network") { testConnection() }.disabled(testing)
                            }
                            Button("Remove", systemImage: "trash", role: .destructive) { deleting = instance }
                        } label: {
                            if testing && instance.id == store.activeID {
                                ProgressView().frame(width: 40, height: 44)
                            } else {
                                Image(systemName: "ellipsis").frame(width: 40, height: 44)
                            }
                        }.accessibilityLabel("Manage \(instance.name)")
                    }.padding(.vertical, 2)
                }
                Button("Add server", systemImage: "plus") { store.showConnection = true }
            }.listRowBackground(theme.surface)

            if store.api != nil {
                Section {
                    LibraryScanRow()
                } footer: {
                    Text("Asks Navidrome to look for new and changed music. Needs an admin account.")
                }
                .listRowBackground(theme.surface)
            }

            Section {
                qualityPicker("Wi-Fi", symbol: "wifi", selection: $wifiQuality)
                qualityPicker("Mobile data", symbol: "antenna.radiowaves.left.and.right", selection: $cellularQuality)
            } header: {
                Text("Streaming quality")
            } footer: {
                Text("Lower qualities are converted by your server. Downloads always play from the device.")
            }
            .listRowBackground(theme.surface)

            Section {
                NavigationLink {
                    LibrarySectionsView()
                } label: {
                    Label("Library", systemImage: "music.note.square.stack")
                }
                NavigationLink {
                    DownloadsSettingsView()
                } label: {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
                NavigationLink {
                    QueueSyncView()
                } label: {
                    Label("Listening queue", systemImage: "list.bullet")
                }
                Toggle(isOn: $scrobble) { Label("Listening history", systemImage: "clock.arrow.circlepath") }
                    .tint(theme.switchTint)
            } footer: {
                Text("Listening history reports plays to Navidrome and its scrobbling services.")
            }
            .listRowBackground(theme.surface)

            Section {
                NavigationLink {
                    AboutGevunView()
                } label: {
                    Label("About Gevun", systemImage: "info.circle")
                }
            }.listRowBackground(theme.surface)
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Settings").pageBackground()
        .sheet(item: $editing) { instance in ConnectionView(editing: instance).environment(store) }
        .confirmationDialog(
            "Remove \(deleting?.name ?? "server")?",
            isPresented: $deleting.isPresent(),
            titleVisibility: .visible
        ) {
            Button("Remove server", role: .destructive) {
                guard let deleting else { return }
                do { try store.remove(deleting.id) } catch { store.notice = error.localizedDescription }
                self.deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Its saved credentials and downloaded music will be removed from this device.")
        }
    }

    private func qualityPicker(_ title: String, symbol: String, selection: Binding<String>) -> some View {
        Picker(title, systemImage: symbol, selection: selection) {
            ForEach(DownloadQuality.streamingChoices, id: \.storageValue) { quality in
                Text(quality.title).tag(quality.storageValue)
            }
        }
    }

    private func testConnection() {
        guard !testing, let api = store.api else { return }
        testing = true
        Task {
            defer { testing = false }
            do {
                let version = try await api.ping()
                guard store.api === api else { return }
                store.serverVersion = version
                store.notice = "Connected to \(api.instance.name) · \(version)"
            } catch { if store.api === api { store.notice = friendlyError(error) } }
        }
    }
}

private struct AboutGevunView: View {
    @Environment(\.appTheme) private var theme
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    BrandMark(size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gevun").font(.title2.weight(.bold))
                        Text("Version \(appVersion) · iOS 27").font(.caption).foregroundStyle(theme.secondary)
                    }
                }.padding(.vertical, 4)
                Link(destination: URL(string: "https://www.navidrome.org")!) {
                    Label("Navidrome", systemImage: "arrow.up.right.square")
                }
            }.listRowBackground(theme.surface)
            Section("Listening history") {
                Text(
                    "Off by default. When enabled, listens are reported after half a track or four minutes of playback. Your server may forward them to its configured scrobbling services."
                )
            }.listRowBackground(theme.surface)
            Section("Privacy") {
                Text(
                    "Credentials are saved in Keychain. Music streams directly from your server. Gevun has no analytics or advertising."
                )
            }.listRowBackground(theme.surface)
        }.listSectionSpacing(.compact).navigationTitle("About Gevun").navigationBarTitleDisplayMode(.inline)
            .pageBackground()
    }
}
