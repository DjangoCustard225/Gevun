import SwiftUI
import GevunCore

struct DownloadsSettingsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @State private var removingAll = false
    private var namespace: String { store.api.map { DownloadKey.namespace(for: $0.instance) } ?? "" }
    private var jobs: [DownloadJob] { store.downloads.library.jobs.filter { $0.key.namespace == namespace } }
    private var copies: [OfflineSong] { store.downloads.copies(namespace: namespace) }

    var body: some View {
        @Bindable var downloads = store.downloads
        List {
            Section {
                Toggle("Wi-Fi only", isOn: $downloads.wifiOnly)
                    .tint(theme.switchTint)
                LabeledContent(
                    "Storage used",
                    value: ByteCountFormatter.string(
                        fromByteCount: copies.reduce(0) { $0 + $1.bytes }, countStyle: .file))
            } footer: {
                Text("Downloads belong to this server. Music stays saved until you remove it.")
            }
            if let error = downloads.storageError {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("Try storage again", systemImage: "arrow.clockwise") { downloads.retryStorage() }
                }
            }
            if !jobs.isEmpty {
                Section("Downloads") {
                    ForEach(jobs) { job in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(job.song.title).font(.subheadline.weight(.medium))
                                    Text(job.quality.title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if job.state == .failed || job.state == .waiting {
                                    Button {
                                        downloads.retry(job.id)
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .accessibilityLabel("Retry \(job.song.title)")
                                }
                                Button {
                                    downloads.cancel(job.id)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .accessibilityLabel("Cancel \(job.song.title)")
                            }.buttonStyle(.borderless)
                            if job.state == .transferring {
                                if let value = downloads.progress[job.id] {
                                    ProgressView(value: value)
                                } else {
                                    ProgressView()
                                }
                            }
                            Text(
                                job.error
                                    ?? (job.state == .validating
                                        ? "Checking audio…"
                                        : downloads.waitingMessage
                                            ?? (job.state == .queued
                                                ? "Queued"
                                                : job.state == .waiting ? "Waiting to retry" : "Downloading…"))
                            )
                            .font(.caption).foregroundStyle(job.state == .failed ? .red : .secondary)
                        }.padding(.vertical, 4)
                    }
                }
            }
            Section("Saved music") {
                if copies.isEmpty { Text("No downloaded songs yet").foregroundStyle(.secondary) }
                ForEach(copies) { copy in
                    HStack(spacing: 10) {
                        ArtworkView(id: copy.song.coverArt, size: 192).frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(copy.song.title).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(
                                copy.quality.title + " · "
                                    + ByteCountFormatter.string(fromByteCount: copy.bytes, countStyle: .file)
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions { Button("Remove", role: .destructive) { downloads.remove(copy.key) } }
                }
            }
            if !copies.isEmpty || !jobs.isEmpty {
                Section { Button("Remove all downloads", role: .destructive) { removingAll = true } }
            }
        }
        .listSectionSpacing(.compact).navigationTitle("Downloads").pageBackground()
        .confirmationDialog(
            "Remove all downloads for this server?", isPresented: $removingAll, titleVisibility: .visible
        ) {
            Button("Remove downloads", role: .destructive) { downloads.removeNamespace(namespace) }
        }
    }
}
