import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import GevunCore

struct DownloadExportLink: View {
    @Environment(AppStore.self) private var store
    let copies: [OfflineSong]
    var title: LocalizedStringKey = "Export download"

    var body: some View {
        let names = DownloadExportNames.filenames(for: copies)
        let files = zip(copies, names).map { copy, name in
            DownloadedAudio(source: store.downloads.exportSource(for: copy), filename: name)
        }
        ShareLink(items: files) { file in
            SharePreview(file.source.copy.song.title, image: Image(systemName: "music.note"))
        } label: {
            Label(title, systemImage: "square.and.arrow.up")
        }
        .disabled(files.isEmpty)
    }
}

private struct DownloadedAudio: Transferable {
    let source: DownloadExportSource
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .audio) { file in
            let url = try await DownloadAudioExport.prepare(file.source, filename: file.filename)
            // The share destination receives a copy and cannot change the offline library.
            return SentTransferredFile(url, allowAccessingOriginalFile: false)
        }
        .suggestedFileName { $0.filename }
    }
}
