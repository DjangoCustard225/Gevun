import AVFoundation
import GevunCore
import SwiftUI

struct DownloadSelection: Identifiable {
    let id = UUID()
    let songs: [Song]
    let album: Album?
    let instance: Instance
}

struct DownloadOptionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let selection: DownloadSelection
    @State private var format = DownloadFormat.original
    @State private var bitrate = 0
    @State private var supported: Set<DownloadFormat> = [.original]
    @State private var checking = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(
                        "Format",
                        selection: Binding(
                            get: { format },
                            set: {
                                format = $0
                                bitrate = $0.defaultBitrate
                            })
                    ) {
                        ForEach(DownloadFormat.allCases) { choice in
                            Text(choice.title).tag(choice).disabled(!supported.contains(choice))
                        }
                    }
                    if format != .original {
                        Picker("Bitrate", selection: $bitrate) {
                            ForEach(format.bitrates, id: \.self) { Text("\($0) kbps").tag($0) }
                        }
                    }
                } footer: {
                    Text(
                        format == .original
                            ? "Save the original file without converting it."
                            : "Your server converts the audio before downloading. It needs an available \(format.title) transcoder."
                    )
                }
                Section {
                    Label(
                        "\(selection.songs.count) \(selection.songs.count == 1 ? "song" : "songs")",
                        systemImage: "music.note")
                    Label(store.downloads.wifiOnly ? "Downloads over Wi-Fi" : "Wi-Fi and cellular", systemImage: "wifi")
                } footer: {
                    Text(
                        "Downloaded music plays locally, even without a connection. A new format replaces the saved copy once it finishes."
                    )
                }
                if checking {
                    HStack {
                        ProgressView(); Text("Checking native format support…")
                    }
                } else if supported.count < DownloadFormat.allCases.count {
                    Text("Unavailable formats can't play through the native player on this device.").font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = store.downloads.storageError { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Download").navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Download") {
                        store.downloads.enqueue(
                            selection.songs, instance: selection.instance,
                            quality: DownloadQuality(format: format, bitrate: bitrate), album: selection.album)
                        dismiss()
                    }.disabled(
                        checking || selection.songs.isEmpty || store.downloads.storageError != nil
                            || !supported.contains(format))
                }
            }
            .task {
                let preference = store.downloads.quality(namespace: DownloadKey.namespace(for: selection.instance))
                supported = await NativeDownloadFormats.shared.supported()
                guard !Task.isCancelled else { return }
                checking = false
                if supported.contains(preference.format) {
                    format = preference.format
                    bitrate = preference.bitrate
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
        .presentationBackground(Color.black)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct SongDownloadActions: View {
    @Environment(AppStore.self) private var store
    let song: Song
    var body: some View {
        if let instance = store.api?.instance {
            let key = DownloadKey(namespace: DownloadKey.namespace(for: instance), songID: song.id)
            let job = store.downloads.library.jobs.first(where: { $0.key == key })
            Button("Download…", systemImage: "arrow.down.circle") {
                store.downloadSelection = DownloadSelection(songs: [song], album: nil, instance: instance)
            }.disabled(job != nil)
            if let job {
                if job.state == .failed || job.state == .waiting {
                    Button("Retry download", systemImage: "arrow.clockwise") { store.downloads.retry(job.id) }
                }
                Button("Cancel download", systemImage: "xmark.circle") { store.downloads.cancel(job.id) }
            }
            if store.downloads.savedKeys.contains(key) {
                Button("Remove download", systemImage: "trash", role: .destructive) { store.downloads.remove(key) }
            }
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

/// Probe actual local files, rather than inferring AVPlayer support from Safari's codec list.
private actor NativeDownloadFormats {
    static let shared = NativeDownloadFormats()
    private var cached: Set<DownloadFormat>?
    func supported() async -> Set<DownloadFormat> {
        if let cached { return cached }
        var result: Set<DownloadFormat> = [.original]
        guard let url = Bundle.main.url(forResource: "DownloadProbes", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let probes = try? PropertyListDecoder().decode([String: Data].self, from: data)
        else { return result }
        for format in DownloadFormat.allCases where format != .original {
            guard let bytes = probes[format.rawValue] else { continue }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(format.rawValue)
            do {
                try bytes.write(to: file)
                let asset = AVURLAsset(url: file)
                if try await asset.load(.isPlayable), try await asset.load(.duration).seconds > 0,
                    let track = try await asset.loadTracks(withMediaType: .audio).first
                {
                    let reader = try AVAssetReader(asset: asset)
                    let output = AVAssetReaderTrackOutput(
                        track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
                    if reader.canAdd(output) {
                        let provider = reader.outputProvider(for: output)
                        try reader.start()
                        if try await provider.next() != nil { result.insert(format) }
                        reader.cancelReading()
                    }
                }
            } catch { /* Unsupported native codecs remain disabled. */  }
            try? FileManager.default.removeItem(at: file)
        }
        cached = result
        return result
    }
}

extension View {
    func downloadPresentation(fromPlayer: Bool = false) -> some View {
        modifier(DownloadPresentation(fromPlayer: fromPlayer))
    }
}

private struct DownloadPresentation: ViewModifier {
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    let fromPlayer: Bool
    func body(content: Content) -> some View {
        content.sheet(
            item: Binding(
                get: { interface.expanded == fromPlayer ? store.downloadSelection : nil },
                set: { store.downloadSelection = $0 }
            )
        ) { selection in
            DownloadOptionsView(selection: selection).environment(store)
        }
    }
}
