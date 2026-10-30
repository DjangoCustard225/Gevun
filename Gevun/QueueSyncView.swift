import SwiftUI
import GevunCore

struct QueueSyncView: View {
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Form {
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
                try await api.saveQueue(
                    songs: store.player.queue.songs, index: store.player.queue.index, position: store.player.elapsed)
                message = "Queue saved to Navidrome."
            }
        } catch { message = friendlyError(error) }
    }
}
