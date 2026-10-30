import SwiftUI
import GevunCore

struct MusicSearchView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    private var player: PlayerStore { store.player }
    @Binding var query: String
    @State private var results = SearchResults()
    @State private var filter = SearchFilter.all
    @State private var loading = false
    @State private var message: String?
    @State private var revision = UUID()
    @State private var offsets = (albums: 0, artists: 0, songs: 0)
    @State private var hasMore = false
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private enum SearchFilter: String, CaseIterable {
        case all = "All", albums = "Albums", artists = "Artists", songs = "Tracks"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if term.isEmpty {
                    ContentUnavailableView(
                        "Search your library", systemImage: "magnifyingglass",
                        description: Text("Find albums, artists, and tracks.")
                    ).padding(.top, 24)
                } else {
                    Picker("Search filter", selection: $filter) {
                        ForEach(SearchFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if let message { ErrorCard(message: message) { Task { await search(more: false) } } }
                    if !results.isEmpty { resultContent }
                    if loading {
                        ProgressView().accessibilityLabel("Searching").frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else if message == nil && visibleResultsEmpty {
                        ContentUnavailableView.search(text: term)
                    }
                    if hasMore && message == nil {
                        ScrollPaginationTrigger(enabled: !loading) { await search(more: true) }
                            .id(
                                "\(term):\(filter.rawValue):\(results.albums.count):\(results.artists.count):\(results.songs.count)"
                            )
                    }
                }
            }.padding(16).readingWidth()
                .background { NativeScrollToTop().frame(width: 0, height: 0) }
        }
        .navigationTitle("Search").pageBackground()
        .task(id: term) {
            revision = UUID()
            results = SearchResults()
            message = nil
            offsets = (0, 0, 0)
            hasMore = false
            guard !term.isEmpty else {
                loading = false
                return
            }
            loading = true
            do {
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()
                await search(more: false)
            } catch { /* Superseded keystrokes are intentionally cancelled. */  }
        }
        .listeningLinkPresentation()
    }

    private var visibleResultsEmpty: Bool {
        switch filter {
        case .all: results.isEmpty
        case .albums: results.albums.isEmpty
        case .artists: results.artists.isEmpty
        case .songs: results.songs.isEmpty
        }
    }
    @ViewBuilder private var resultContent: some View {
        if (filter == .all || filter == .albums) && !results.albums.isEmpty {
            if filter == .all { SectionTitle(title: "Albums") }
            AlbumGrid(albums: results.albums)
        }
        if (filter == .all || filter == .artists) && !results.artists.isEmpty {
            if filter == .all { SectionTitle(title: "Artists") }
            LazyVStack(spacing: 0) {
                ForEach(results.artists) { artist in
                    NavigationLink {
                        ArtistDetailView(artist: artist)
                    } label: {
                        ArtistRow(artist: artist)
                    }.buttonStyle(.plain)
                }
            }
        }
        if (filter == .all || filter == .songs) && !results.songs.isEmpty {
            if filter == .all { SectionTitle(title: "Tracks") }
            LazyVStack(spacing: 0) {
                ForEach(Array(results.songs.enumerated()), id: \.element.id) { index, song in
                    VStack(spacing: 0) {
                        SongRow(song: song) { player.play(results.songs, at: index) }
                        Divider().overlay(theme.border)
                    }
                }
            }
        }
    }

    private func search(more: Bool) async {
        guard let api = store.api, !term.isEmpty else { return }
        if more && loading { return }
        let term = term
        let token = UUID()
        revision = token
        loading = true
        message = nil
        defer { if revision == token { loading = false } }
        let old = more ? results : SearchResults()
        let offset = more ? offsets : (0, 0, 0)
        do {
            let page = try await api.search(term, albumOffset: offset.0, artistOffset: offset.1, songOffset: offset.2)
            guard !Task.isCancelled, revision == token, self.term == term, store.api === api else { return }
            let albums = unique(old.albums + page.albums)
            let artists = unique(old.artists + page.artists)
            let songs = unique(old.songs + page.songs)
            results = SearchResults(album: albums, artist: artists, song: songs)
            offsets = (offset.0 + page.albums.count, offset.1 + page.artists.count, offset.2 + page.songs.count)
            hasMore =
                (page.albums.count == 30 || page.artists.count == 30 || page.songs.count == 30)
                && (albums.count + artists.count + songs.count > old.albums.count + old.artists.count + old.songs.count)
        } catch { if !Task.isCancelled, revision == token { message = friendlyError(error) } }
    }

    private func unique<T: Identifiable>(_ values: [T]) -> [T] where T.ID: Hashable {
        var ids = Set<T.ID>()
        return values.filter { ids.insert($0.id).inserted }
    }
}
