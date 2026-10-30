import SwiftUI
import GevunCore

struct DownloadedSongRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    let copy: OfflineSong
    let play: () -> Void
    private var isCurrent: Bool { interface.current?.id == copy.song.id }
    private var quality: String {
        copy.quality.format == .original ? copy.song.suffix?.uppercased() ?? "Original" : copy.quality.title
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if isCurrent { store.player.toggle() } else { play() }
            } label: {
                HStack(spacing: 12) {
                    ArtworkView(id: copy.song.coverArt, size: 192)
                        .overlay {
                            if isCurrent {
                                ZStack {
                                    Color.black.opacity(0.35)
                                    Image(systemName: interface.isPlaying ? "waveform" : "pause.fill")
                                        .font(.title3.weight(.semibold)).foregroundStyle(.white)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: Theme.artworkCornerRadius))
                            }
                        }
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(copy.song.title).font(.subheadline.weight(.semibold))
                            .foregroundStyle(isCurrent ? theme.accent : .white).lineLimit(2)
                        Text([copy.song.artistName, copy.song.album].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
                        Text(
                            quality + " · " + ByteCountFormatter.string(fromByteCount: copy.bytes, countStyle: .file)
                        )
                        .font(.caption2).foregroundStyle(theme.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHint(isCurrent ? "Toggle playback" : "Play downloaded song")
            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis").font(.body).foregroundStyle(theme.secondary)
                    .frame(width: 40, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Actions for \(copy.song.title)")
        }
        .contextMenu { actions }
        .swipeActions {
            Button("Remove", role: .destructive) { store.downloads.remove(copy.key) }
                .tint(.red)
        }
    }

    @ViewBuilder private var actions: some View {
        Section {
            Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                store.player.add(copy.song, next: true)
            }
            Button("Add to queue", systemImage: "text.badge.plus") { store.player.add(copy.song, next: false) }
        }
        Section {
            ServerShareButton(ids: [copy.song.id])
            SavedDownloadActions(copy: copy)
        }
    }
}

/// Network progress only invalidates this row, rather than sorting the entire saved library on every update.
struct DownloadProgressRow: View {
    @ScaledMetric(relativeTo: .body) private var artworkSize = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppStore.self) private var store
    let job: DownloadJob

    var body: some View {
        let downloads = store.downloads
        let progress = downloads.progress[job.id]
        HStack(spacing: 12) {
            ArtworkView(id: job.song.coverArt, size: 192)
                .frame(width: artworkSize, height: artworkSize).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(job.song.title).font(.body).foregroundStyle(.primary).lineLimit(1)
                Text(job.song.artistName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    if job.state == .validating || (job.state == .transferring && progress == nil) {
                        ProgressView().controlSize(.mini)
                    }
                    Text(status).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    if job.state == .transferring, let progress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit().foregroundStyle(.primary)
                    }
                }
                .font(.caption).foregroundStyle(job.state == .failed ? Color.red : Color.secondary)
                if job.state == .transferring, let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .animation(reduceMotion ? nil : .linear(duration: 0.2), value: progress)
                        .accessibilityLabel("Download progress")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                if job.state == .failed || job.state == .waiting {
                    Button("Retry", systemImage: "arrow.clockwise") { downloads.retry(job.id) }
                }
                Button("Cancel download", systemImage: "xmark.circle", role: .destructive) {
                    downloads.cancel(job.id)
                }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary)
                    .frame(width: 36, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Download actions for \(job.song.title)")
        }
        .padding(.vertical, 4)
    }

    private var status: String {
        if let error = job.error { return error }
        if job.state == .failed { return "Download failed" }
        if job.state == .validating { return "Finishing up" }
        if let waiting = store.downloads.waitingMessage { return waiting }
        switch job.state {
        case .queued: return "Queued"
        case .waiting: return "Waiting to retry"
        case .transferring: return "Downloading"
        default: return job.quality.title
        }
    }
}
