import SwiftUI
import GevunCore

struct QueueSyncView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        @Bindable var sync = store.player.listening
        Form {
            Section {
                Toggle("Automatic queue sync", isOn: $sync.automatic).tint(theme.switchTint)
            } footer: {
                Text("Restore your queue paused when Gevun starts. A copy stays on this device for offline listening.")
            }
            Section {
                Button("Save current queue", systemImage: "icloud.and.arrow.up") {
                    Task { await transfer(restoring: false) }
                }.disabled(interface.current == nil || busy)
                Button("Resume saved queue", systemImage: "icloud.and.arrow.down") {
                    Task { await transfer(restoring: true) }
                }.disabled(busy)
            } footer: {
                Text(
                    "Save your queue and playback position to Navidrome, then resume it on another compatible device. Resuming replaces your current queue and starts playback."
                )
            }
            if let status = sync.status { Text(status).foregroundStyle(.secondary) }
            if busy { ProgressView() }
            if let message { Text(message).foregroundStyle(.secondary) }
        }
        .navigationTitle("Listening queue").pageBackground()
    }

    private func transfer(restoring: Bool) async {
        guard !busy, let api = store.api else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            if restoring {
                let playbackID = store.player.playbackID
                guard let saved = try await api.savedQueue(), !saved.songs.isEmpty else {
                    message = "No queue has been saved on this server."; return
                }
                guard store.api === api, store.player.playbackID == playbackID else { return }
                store.player.restore(saved)
                message = "Resumed saved queue."
            } else {
                await store.player.listening.saveManually()
            }
        } catch { message = friendlyError(error) }
    }
}
