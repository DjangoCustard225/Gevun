import SwiftUI
import GevunCore

enum LibraryCategory: String, CaseIterable, Identifiable, Hashable {
    case albums, artists, songs
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

struct LibraryView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    private var player: PlayerStore { store.player }
    let category: LibraryCategory
    @State private var downloadedOnly = false
    private var namespace: String { store.api.map { DownloadKey.namespace(for: $0.instance) } ?? "" }
    private var albums: [Album] {
        downloadedOnly ? store.downloads.library.downloadedAlbums(namespace: namespace) : store.albums
    }
    private var songs: [Song] {
        downloadedOnly ? store.downloads.copies(namespace: namespace).map(\.song) : store.songs
    }
    private var loading: Bool { !downloadedOnly && store.libraryLoading.contains(category) }
    private var message: String? { downloadedOnly ? nil : store.libraryErrors[category] }
    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if downloadedOnly && (category == .albums ? albums.isEmpty : songs.isEmpty) {
                    ContentUnavailableView(
                        "No downloads yet", systemImage: "arrow.down.circle",
                        description: Text("Download songs or albums from their menus to listen offline."))
                }
                if let message {
                    ErrorCard(message: message) { Task { await store.loadLibrary(category) } }
                }
                content
                if loading {
                    ProgressView().accessibilityLabel("Loading \(category.title.lowercased())").frame(
                        maxWidth: .infinity
                    ).padding(16)
                }
            }.padding(.horizontal, 16).padding(.vertical, 12).readingWidth()
                .background { NativeScrollToTop().frame(width: 0, height: 0) }
        }
        .navigationTitle(category.title)
        .toolbar {
            if category == .albums || category == .songs {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Show") {
                            Picker("Library", selection: $downloadedOnly) {
                                Text("All").tag(false)
                                Text("Downloaded").tag(true)
                            }
                        }
                        if category == .albums && !downloadedOnly {
                            Section("Sort") {
                                Picker("Sort albums", selection: $store.albumOrder) {
                                    ForEach(AlbumOrder.allCases) { order in Text(order.title).tag(order) }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }.accessibilityLabel(category == .albums ? "Sort and filter albums" : "Filter songs")
                }
            }
        }
        .pageBackground()
        .refreshable { if !downloadedOnly { await store.loadLibrary(category) } }
        .task(
            id:
                "\(category.rawValue):\(category == .albums ? store.albumOrder.rawValue : ""):\(store.sessionID):\(downloadedOnly)"
        ) {
            if !downloadedOnly { await store.ensureLibrary(category) }
        }
        .listeningLinkPresentation()
    }

    @ViewBuilder private var content: some View {
        switch category {
        case .albums:
            if !albums.isEmpty {
                AlbumGrid(albums: albums, downloadedOnly: downloadedOnly)
                if !downloadedOnly && store.moreAlbums && message == nil {
                    ScrollPaginationTrigger(enabled: !loading) { await store.loadLibrary(.albums, more: true) }
                        .id("\(store.sessionID):\(store.albumOrder.rawValue):\(store.albums.count)")
                }
            } else if !downloadedOnly {
                empty(
                    "No albums yet", symbol: "square.stack",
                    message: "Albums in your server's music library will appear here.")
            }
        case .artists:
            if store.artists.isEmpty {
                empty("No artists yet", symbol: "person.2", message: "Your library's artists will appear here.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(store.artists) { artist in
                        VStack(spacing: 0) {
                            NavigationLink {
                                ArtistDetailView(artist: artist)
                            } label: {
                                ArtistRow(artist: artist)
                            }.buttonStyle(.plain)
                            Divider().overlay(theme.border).padding(.leading, 74)
                        }
                    }
                }
            }
        case .songs:
            if downloadedOnly {
                let copies = store.downloads.copies(namespace: namespace)
                LazyVStack(spacing: 0) {
                    ForEach(Array(copies.enumerated()), id: \.element.key) { index, copy in
                        VStack(spacing: 0) {
                            DownloadedSongRow(copy: copy) { player.play(copies.map(\.song), at: index) }
                            Divider().overlay(theme.border).padding(.leading, 68)
                        }
                    }
                }
            } else if songs.isEmpty {
                empty(
                    "No songs yet", symbol: "music.note",
                    message: "Songs in your server's music library will appear here.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        VStack(spacing: 0) {
                            SongRow(song: song) { player.play(songs, at: index) }
                            Divider().overlay(theme.border).padding(.leading, 66)
                        }
                    }
                }
                if !downloadedOnly && store.moreSongs && message == nil {
                    ScrollPaginationTrigger(enabled: !loading) { await store.loadLibrary(.songs, more: true) }
                        .id("\(store.sessionID):\(store.songs.count)")
                }
            }

        }
    }

    @ViewBuilder private func empty(_ title: String, symbol: String, message: String) -> some View {
        if !loading && self.message == nil {
            ContentUnavailableView(title, systemImage: symbol, description: Text(message)).padding(.vertical, 24)
        }
    }
}

struct ArtistRow: View {
    @Environment(\.appTheme) private var theme
    let artist: Artist
    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(id: artist.coverArt, size: 192, cornerRadius: 32)
                .frame(width: 64, height: 64).clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(artist.name).font(.headline).foregroundStyle(.white)
                if let count = artist.albumCount {
                    Text("\(count) \(count == 1 ? "album" : "albums")").font(.caption).foregroundStyle(theme.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.secondary)
        }.padding(.vertical, 4).contentShape(Rectangle())
    }
}
