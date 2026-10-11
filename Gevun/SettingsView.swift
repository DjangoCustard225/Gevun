import SwiftUI
import GevunCore

struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @AppStorage("scrobbleEnabled") private var scrobble = false
    @State private var editing: Instance?
    @State private var deleting: Instance?
    @State private var testing = false

    var body: some View {
        List {
            Section("Instances") {
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
                            instance.id == store.activeID ? "Active instance" : "Switch to this instance")
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
                        .swipeActions {
                            Button("Remove", role: .destructive) { deleting = instance }
                            Button("Edit") { editing = instance }.tint(theme.accent)
                        }
                }
                Button("Add instance", systemImage: "plus") { store.showConnection = true }
            }.listRowBackground(theme.surface)

            Section {
                Toggle("Listening history", isOn: $scrobble)
            } footer: {
                Text("Report plays to Navidrome and its configured scrobbling services.")
            }
            .listRowBackground(theme.surface)

            Section {
                NavigationLink("About Gevun") { AboutGevunView() }
            }.listRowBackground(theme.surface)
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Settings").pageBackground()
        .sheet(item: $editing) { instance in NavigationStack { ConnectionView(editing: instance) }.environment(store) }
        .confirmationDialog(
            "Remove \(deleting?.name ?? "instance")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove instance", role: .destructive) {
                guard let deleting else { return }
                do { try store.remove(deleting.id) } catch { store.notice = error.localizedDescription }
                self.deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Its saved credentials will be removed from this device.")
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
    @Environment(AppStore.self) private var store
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
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
                Button("Clear artwork cache", systemImage: "trash") {
                    store.artwork.clear(); store.notice = "Artwork memory cache cleared."
                }
            }.listRowBackground(theme.surface)
        }.listSectionSpacing(.compact).navigationTitle("About Gevun").navigationBarTitleDisplayMode(.inline)
            .pageBackground()
    }
}
