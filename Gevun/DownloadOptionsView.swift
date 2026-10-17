import SwiftUI
import GevunCore

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
