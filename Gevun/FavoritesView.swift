import SwiftUI
import GevunCore

/// Songs, albums and artists the user has favourited on the server, one kind at a time.
struct FavoritesView: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case songs = "Songs", albums = "Albums", artists = "Artists"
        var id: Self { self }
    }

    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @State private var favorites: Favorites?
    @State private var message: String?
    @State private var loading = true
    @State private var kind = Kind.songs

    // Items unfavourited from this page disappear straight away.
    private var songs: [Song] { (favorites?.song ?? []).filter { store.isFavorite($0.id, starred: $0.starred) } }
    private var albums: [Album] { (favorites?.album ?? []).filter { store.isFavorite($0.id, starred: $0.starred) } }
    private var artists: [Artist] {
        (favorites?.artist ?? []).filter { store.isFavorite($0.id, starred: $0.starred) }
    }
    private var isEmpty: Bool {
        switch kind {
        case .songs: songs.isEmpty
        case .albums: albums.isEmpty
        case .artists: artists.isEmpty
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Favorites", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if let message {
                    ErrorState(message: message) { Task { await load() } }
                } else if loading && favorites == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(16)
                } else if isEmpty {
                    ContentUnavailableView(
                        "No favorite \(kind.rawValue.lowercased())", systemImage: "heart",
                        description: Text("Use Add to Favorites in a menu to keep them here."))
                } else {
                    switch kind {
                    case .songs: songList
                    case .albums: AlbumGrid(albums: albums)
                    case .artists: artistList
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12).readingWidth()
            .background { NativeScrollToTop().frame(width: 0, height: 0) }
        }
        .navigationTitle("Favorites")
        .toolbar {
            if kind == .songs && !songs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Play", systemImage: "play.fill") { store.player.play(songs) }
                        Button("Shuffle", systemImage: "shuffle") { store.player.start(songs, shuffle: true) }
                    } label: {
                        Image(systemName: "ellipsis")
                    }.accessibilityLabel("Favorite songs actions")
                }
            }
        }
        .pageBackground()
        .refreshable { await load() }
        .task(id: store.sessionID) { await load() }
        .listeningLinkPresentation()
    }

    private var songList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song) { store.player.play(songs, at: index) }
                Divider().overlay(theme.border).padding(.leading, 66)
            }
        }
    }

    private var artistList: some View {
        LazyVStack(spacing: 0) {
            ForEach(artists) { artist in
                NavigationLink {
                    ArtistDetailView(artist: artist)
                } label: {
                    ArtistRow(artist: artist)
                }.buttonStyle(.plain)
                Divider().overlay(theme.border).padding(.leading, 74)
            }
        }
    }

    private func load() async {
        guard let api = store.api else { return }
        loading = true
        defer { loading = false }
        do {
            let value = try await api.favorites()
            guard store.api === api, !Task.isCancelled else { return }
            favorites = value
            message = nil
        } catch {
            guard store.api === api, !Task.isCancelled else { return }
            if favorites == nil { message = friendlyError(error) }
        }
    }
}

/// Music saved on this device for the current server, songs or albums at a time.
struct DownloadedView: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case songs = "Songs", albums = "Albums"
        var id: Self { self }
    }

    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @State private var kind = Kind.songs
    private var namespace: String { store.downloadNamespace ?? "" }

    var body: some View {
        let copies = store.downloads.copies(namespace: namespace)
        let albums = store.downloads.library.downloadedAlbums(namespace: namespace)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Downloaded", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if kind == .songs ? copies.isEmpty : albums.isEmpty {
                    ContentUnavailableView(
                        "No downloaded \(kind.rawValue.lowercased())", systemImage: "arrow.down.circle",
                        description: Text("Download songs or albums from their menus to listen offline."))
                } else if kind == .songs {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(copies.enumerated()), id: \.element.key) { index, copy in
                            DownloadedSongRow(copy: copy) { store.player.play(copies.map(\.song), at: index) }
                            Divider().overlay(theme.border).padding(.leading, 68)
                        }
                    }
                } else {
                    AlbumGrid(albums: albums, downloadedOnly: true)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12).readingWidth()
            .background { NativeScrollToTop().frame(width: 0, height: 0) }
        }
        .navigationTitle("Downloaded")
        .toolbar {
            if kind == .songs && !copies.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Play", systemImage: "play.fill") { store.player.play(copies.map(\.song)) }
                        Button("Shuffle", systemImage: "shuffle") {
                            store.player.start(copies.map(\.song), shuffle: true)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }.accessibilityLabel("Downloaded songs actions")
                }
            }
        }
        .pageBackground()
        .listeningLinkPresentation()
    }
}

/// Every genre on the server, with how many albums each has.
struct GenresView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @State private var genres: [Genre] = []
    @State private var message: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let message {
                    ErrorState(message: message) { Task { await load() } }
                } else if loading && genres.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(16)
                } else if genres.isEmpty {
                    ContentUnavailableView("No genres", systemImage: "guitars")
                }
                ForEach(genres) { genre in
                    NavigationLink {
                        GenreAlbumsView(genre: genre.value)
                    } label: {
                        HStack {
                            Text(genre.value).font(.body).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            if let count = genre.albumCount {
                                Text(count.counted("album")).font(.subheadline).foregroundStyle(theme.secondary)
                            }
                        }
                        .padding(.vertical, 14).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Divider().overlay(theme.border)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12).readingWidth()
            .background { NativeScrollToTop().frame(width: 0, height: 0) }
        }
        .navigationTitle("Genres")
        .pageBackground()
        .refreshable { await load() }
        .task(id: store.sessionID) { await load() }
    }

    private func load() async {
        guard let api = store.api else { return }
        loading = true
        defer { loading = false }
        do {
            let value = try await api.genres()
            guard store.api === api, !Task.isCancelled else { return }
            genres = value.sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
            message = nil
        } catch {
            guard store.api === api, !Task.isCancelled else { return }
            if genres.isEmpty { message = friendlyError(error) }
        }
    }
}

/// Albums in one genre, loaded a page at a time.
struct GenreAlbumsView: View {
    @Environment(AppStore.self) private var store
    let genre: String
    @State private var albums: [Album] = []
    @State private var more = true
    @State private var loading = false
    @State private var message: String?
    private let pageSize = 60

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let message { ErrorState(message: message) { Task { await load(more: false) } } }
                AlbumGrid(albums: albums)
                if more && message == nil {
                    ScrollPaginationTrigger(enabled: !loading) { await load(more: !albums.isEmpty) }
                        .id("\(store.sessionID):\(albums.count)")
                }
                if loading { ProgressView().frame(maxWidth: .infinity).padding(16) }
                if !loading && !more && albums.isEmpty && message == nil {
                    ContentUnavailableView("No albums in \(genre)", systemImage: "square.stack")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12).readingWidth()
            .background { NativeScrollToTop().frame(width: 0, height: 0) }
        }
        .navigationTitle(genre)
        .pageBackground()
        .listeningLinkPresentation()
    }

    private func load(more next: Bool) async {
        guard let api = store.api, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await api.albums(
                type: "byGenre", genre: genre, offset: next ? albums.count : 0, size: pageSize)
            guard store.api === api, !Task.isCancelled else { return }
            let merged = ((next ? albums : []) + page).uniqued()
            more = page.count == pageSize && merged.count > (next ? albums.count : 0)
            albums = merged
            message = nil
        } catch {
            guard store.api === api, !Task.isCancelled else { return }
            message = friendlyError(error)
        }
    }
}
