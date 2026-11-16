import SwiftUI
import GevunCore

enum LibraryCategory: String, CaseIterable, Identifiable, Hashable {
    case albums, artists, songs
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

/// The parts of the Library page, each of which can be hidden in Settings.
enum LibrarySection: String, CaseIterable, Identifiable {
    case albums, artists, songs, genres, playlists, favorites, downloaded, recentlyAdded
    static let hiddenKey = "hiddenLibrarySections"
    var id: Self { self }
    var title: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        default: rawValue.capitalized
        }
    }
    var symbol: String {
        switch self {
        case .albums: "square.stack"
        case .artists: "person.2"
        case .songs: "music.note"
        case .genres: "guitars"
        case .playlists: "music.note.list"
        case .favorites: "heart"
        case .downloaded: "arrow.down.circle"
        case .recentlyAdded: "clock"
        }
    }

    /// Hidden sections, stored as a comma-separated list so new sections start visible.
    static func hidden(in stored: String) -> Set<Self> {
        Set(stored.split(separator: ",").compactMap { Self(rawValue: String($0)) })
    }
    static func storage(for hidden: Set<Self>) -> String {
        allCases.filter(hidden.contains).map(\.rawValue).joined(separator: ",")
    }
}

/// The Library tab: links into the library, then the newest albums.
struct LibraryHomeView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @AppStorage(LibrarySection.hiddenKey) private var hiddenSections = ""

    var body: some View {
        let hidden = LibrarySection.hidden(in: hiddenSections)
        let links = LibrarySection.allCases.filter { $0 != .recentlyAdded && !hidden.contains($0) }
        let showsRecent = !hidden.contains(.recentlyAdded)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(links) { section in
                    link(section)
                    Divider().overlay(theme.border).padding(.leading, section == links.last ? 0 : 48)
                }
                if showsRecent {
                    Text("Recently Added").font(.title2.weight(.bold)).foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, links.isEmpty ? 0 : 28).padding(.bottom, 14)
                    AlbumGrid(albums: store.recentAlbums)
                }
                if links.isEmpty && !showsRecent {
                    ContentUnavailableView(
                        "Library is hidden", systemImage: "eye.slash",
                        description: Text("Choose what to show in Settings > Library."))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12).readingWidth()
            .background { NativeScrollToTop().frame(width: 0, height: 0) }
        }
        .navigationTitle("Library")
        .pageBackground()
        .refreshable { if showsRecent { await store.loadRecentAlbums(force: true) } }
        .task(id: "\(store.sessionID):\(store.downloads.connected):\(showsRecent)") {
            if showsRecent { await store.loadRecentAlbums() }
        }
        .listeningLinkPresentation()
    }

    @ViewBuilder private func destination(_ section: LibrarySection) -> some View {
        switch section {
        case .albums: LibraryView(category: .albums)
        case .artists: LibraryView(category: .artists)
        case .songs: LibraryView(category: .songs)
        case .genres: GenresView()
        case .playlists: PlaylistsView()
        case .favorites: FavoritesView()
        case .downloaded: DownloadedView()
        case .recentlyAdded: EmptyView()
        }
    }

    private func link(_ section: LibrarySection) -> some View {
        NavigationLink {
            destination(section)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: section.symbol).font(.title3).foregroundStyle(theme.secondary).frame(width: 32)
                Text(section.title).font(.title3).foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(theme.secondary)
            }
            .padding(.vertical, 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Settings > Library: which sections the Library page shows.
struct LibrarySectionsView: View {
    @Environment(\.appTheme) private var theme
    @AppStorage(LibrarySection.hiddenKey) private var hiddenSections = ""

    var body: some View {
        List {
            Section {
                ForEach(LibrarySection.allCases) { section in
                    Toggle(isOn: binding(section)) { Label(section.title, systemImage: section.symbol) }
                }
            } footer: {
                Text("Hiding a section only removes it from the Library page. Nothing is deleted.")
            }
            .tint(theme.switchTint)
            .listRowBackground(theme.surface)
        }
        .navigationTitle("Library").navigationBarTitleDisplayMode(.inline)
        .pageBackground()
    }

    private func binding(_ section: LibrarySection) -> Binding<Bool> {
        Binding {
            !LibrarySection.hidden(in: hiddenSections).contains(section)
        } set: { shown in
            var hidden = LibrarySection.hidden(in: hiddenSections)
            if shown { hidden.remove(section) } else { hidden.insert(section) }
            hiddenSections = LibrarySection.storage(for: hidden)
        }
    }
}

/// The full list of albums, artists or songs, opened from the Library tab.
struct LibraryView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    private var player: PlayerStore { store.player }
    let category: LibraryCategory
    @State private var downloadedOnly = false
    private var namespace: String { store.downloadNamespace ?? "" }
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
                    ErrorState(message: message) { Task { await store.loadLibrary(category) } }
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
            if category != .artists {
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
                        Image(systemName: category == .albums ? "arrow.up.arrow.down" : "line.3.horizontal.decrease")
                    }.accessibilityLabel("\(category.title) options")
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
    let artist: Artist
    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(id: artist.coverArt, size: 192, cornerRadius: 32)
                .frame(width: 64, height: 64).clipShape(Circle())
            Text(artist.name).font(.headline).foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 4).contentShape(Rectangle())
    }
}
