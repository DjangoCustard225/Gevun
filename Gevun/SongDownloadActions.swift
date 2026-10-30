import SwiftUI
import GevunCore

struct SongDownloadActions: View {
    @Environment(AppStore.self) private var store
    let song: Song
    var body: some View {
        if let instance = store.api?.instance {
            let key = DownloadKey(namespace: DownloadKey.namespace(for: instance), songID: song.id)
            ServerShareButton(ids: [song.id])
            let job = store.downloads.library.jobs.first(where: { $0.key == key })
            Button("Download", systemImage: "arrow.down.circle") {
                store.downloadSelection = DownloadSelection(songs: [song], album: nil, instance: instance)
            }.disabled(job != nil)
            if let job {
                if job.state == .failed || job.state == .waiting {
                    Button("Retry download", systemImage: "arrow.clockwise") { store.downloads.retry(job.id) }
                }
                Button("Cancel download", systemImage: "xmark.circle") { store.downloads.cancel(job.id) }
            }
            if let copy = store.downloads.library.copies.first(where: { $0.key == key }) {
                SavedDownloadActions(copy: copy)
            }
        }
    }
}

struct SavedDownloadActions: View {
    @Environment(AppStore.self) private var store
    let copy: OfflineSong

    var body: some View {
        DownloadExportLink(copies: [copy])
        Button("Remove download", systemImage: "trash", role: .destructive) {
            store.downloads.remove(copy.key)
        }
    }
}

struct DownloadedMark: View {
    @Environment(AppStore.self) private var store
    let songID: String
    var body: some View {
        if let namespace = store.downloadNamespace,
            store.downloads.savedKeys.contains(DownloadKey(namespace: namespace, songID: songID))
        {
            Image(systemName: "arrow.down.circle.fill").font(.caption2).foregroundStyle(.secondary)
                .accessibilityLabel("Downloaded")
        }
    }
}
