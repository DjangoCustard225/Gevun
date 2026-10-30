import SwiftUI
import GevunCore

struct DownloadOptionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let selection: DownloadSelection
    @State private var quality = DownloadQuality()
    @State private var supported: Set<DownloadFormat> = [.original]
    @State private var checking = true
    @State private var started = false

    private var status: DownloadBatchStatus {
        DownloadBatchStatus(
            library: store.downloads.library, songs: selection.songs,
            namespace: DownloadKey.namespace(for: selection.instance), quality: quality)
    }

    @ViewBuilder private var transferContent: some View {
        let status = status
        Section {
            LabeledContent {
                Text("\(status.savedCount) of \(status.totalCount)").monospacedDigit()
            } label: {
                Label(
                    status.isComplete ? "Ready offline" : "Saved",
                    systemImage: status.isComplete ? "checkmark.circle" : "arrow.down.circle")
            }
        }
        if !status.jobs.isEmpty {
            Section {
                ForEach(status.jobs) { job in
                    DownloadProgressRow(job: job)
                }
            } header: {
                Text("\(status.jobs.count) \(status.jobs.count == 1 ? "download" : "downloads")")
            } footer: {
                Text("Downloads continue when you close this sheet.")
            }
        } else if !status.isComplete {
            Section {
                Text("No active downloads").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var configurationContent: some View {
        Section {
            Picker(
                "Format",
                selection: Binding(
                    get: { quality.format },
                    set: {
                        quality = DownloadQuality(format: $0)
                    })
            ) {
                ForEach(DownloadFormat.allCases) { choice in
                    Text(choice.title).tag(choice).disabled(!supported.contains(choice))
                }
            }
            if quality.format != .original {
                Picker(
                    "Bitrate",
                    selection: Binding(
                        get: { quality.bitrate },
                        set: { quality = DownloadQuality(format: quality.format, bitrate: $0) })
                ) {
                    ForEach(quality.format.bitrates, id: \.self) { Text("\($0) kbps").tag($0) }
                }
            }
        } footer: {
            Text(
                quality.format == .original
                    ? "Save the original file without converting it."
                    : "Your server converts the audio before downloading. It needs an available \(quality.format.title) transcoder."
            )
        }
        Section {
            Label(
                "\(selection.songs.count) \(selection.songs.count == 1 ? "song" : "songs")",
                systemImage: "music.note")
            Label(
                store.downloads.wifiOnly ? "Downloads over Wi-Fi" : "Wi-Fi and cellular",
                systemImage: "wifi")
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
    }

    var body: some View {
        NavigationStack {
            Form {
                if started {
                    transferContent
                } else {
                    configurationContent
                }
                if let error = store.downloads.storageError { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(started ? "Downloads" : "Download").navigationBarTitleDisplayMode(.inline)
            .formStyle(.grouped)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .toolbar {
                if !started {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(started ? "Done" : "Download") {
                        if started {
                            dismiss()
                        } else {
                            store.downloads.enqueue(
                                selection.songs, instance: selection.instance,
                                quality: quality, album: selection.album)
                            started = true
                        }
                    }.disabled(
                        !started
                            && (checking || selection.songs.isEmpty || store.downloads.storageError != nil
                                || !supported.contains(quality.format))
                    )
                }
            }
            .onChange(of: started && store.downloads.storageError == nil && status.isComplete) { _, complete in
                if complete { dismiss() }
            }
            .task {
                let preference = store.downloads.quality(namespace: DownloadKey.namespace(for: selection.instance))
                supported = await NativeDownloadFormats.shared.supported()
                guard !Task.isCancelled else { return }
                checking = false
                if supported.contains(preference.format) {
                    quality = preference
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
