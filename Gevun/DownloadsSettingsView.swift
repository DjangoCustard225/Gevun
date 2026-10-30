import SwiftUI
import GevunCore

struct DownloadsSettingsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @State private var sort = DownloadSort.title
    @State private var removingAll = false
    private var namespace: String { store.downloadNamespace ?? "" }

    var body: some View {
        @Bindable var downloads = store.downloads
        let copies = downloads.library.copies.filter { $0.key.namespace == namespace }
        let jobs = downloads.library.jobs.filter { $0.key.namespace == namespace }
        let sorted = copies.sorted(by: sort.precedes)

        List {
            if let error = downloads.storageError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.red)
                    Button("Try storage again", systemImage: "arrow.clockwise") { downloads.retryStorage() }
                }
                .listRowBackground(Color.clear)
            }
            if !jobs.isEmpty {
                Section("Transfers") {
                    ForEach(jobs) { job in
                        DownloadProgressRow(job: job)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12))
                            .listRowSeparatorTint(theme.border)
                    }
                }
                .listRowBackground(Color.clear)
            }
            Section {
                if copies.isEmpty {
                    ContentUnavailableView(
                        jobs.isEmpty ? "No downloaded music" : "Your music is on its way",
                        systemImage: "arrow.down.circle",
                        description: Text(
                            jobs.isEmpty
                                ? "Download songs or albums from their menus to listen offline."
                                : "Completed downloads will appear here.")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(sorted) { copy in
                        DownloadedSongRow(copy: copy) {
                            guard let index = sorted.firstIndex(where: { $0.key == copy.key }) else { return }
                            store.player.play(sorted.map(\.song), at: index)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12))
                        .listRowSeparatorTint(theme.border)
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .navigationTitle("Downloads").navigationBarTitleDisplayMode(.inline)
        .pageBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !sorted.isEmpty {
                        Section {
                            Button("Play all", systemImage: "play.fill") {
                                store.player.play(sorted.map(\.song))
                            }
                        }
                    }
                    if !copies.isEmpty {
                        Picker("Sort by", selection: $sort) {
                            ForEach(DownloadSort.allCases) { order in Text(order.rawValue).tag(order) }
                        }
                        Section { DownloadExportLink(copies: copies, title: "Export all downloads") }
                    }
                    Section {
                        Toggle("Wi-Fi only", isOn: $downloads.wifiOnly).tint(theme.switchTint)
                    }
                    if !copies.isEmpty || !jobs.isEmpty {
                        Section {
                            Button("Remove all downloads", systemImage: "trash", role: .destructive) {
                                removingAll = true
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort and manage downloads")
            }
        }
        .confirmationDialog(
            "Remove all downloads for this server?", isPresented: $removingAll, titleVisibility: .visible
        ) {
            Button("Remove downloads", role: .destructive) { downloads.removeNamespace(namespace) }
        }
        .onChange(of: store.sessionID) { _, _ in
            removingAll = false
        }
        .listeningLinkPresentation()
    }
}

private enum DownloadSort: String, CaseIterable, Identifiable {
    case title = "Title"
    case artist = "Artist"
    case album = "Album"
    case recent = "Recently downloaded"
    case size = "File size"
    var id: Self { self }

    func precedes(_ lhs: OfflineSong, _ rhs: OfflineSong) -> Bool {
        let comparison: ComparisonResult
        switch self {
        case .title: comparison = lhs.song.title.localizedStandardCompare(rhs.song.title)
        case .artist: comparison = lhs.song.artistName.localizedStandardCompare(rhs.song.artistName)
        case .album: comparison = (lhs.song.album ?? "").localizedStandardCompare(rhs.song.album ?? "")
        case .recent:
            if lhs.savedAt != rhs.savedAt { return lhs.savedAt > rhs.savedAt }
            comparison = .orderedSame
        case .size:
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            comparison = .orderedSame
        }
        if comparison != .orderedSame { return comparison == .orderedAscending }
        let title = lhs.song.title.localizedStandardCompare(rhs.song.title)
        return title == .orderedSame ? lhs.key.songID < rhs.key.songID : title == .orderedAscending
    }
}
