import SwiftUI
import GevunCore

struct LibraryView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    private var player: PlayerStore { store.player }
    let category: LibraryCategory
    private var loading: Bool { store.libraryLoading.contains(category) }
    private var message: String? { store.libraryErrors[category] }
    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
            if category == .albums {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort albums", selection: $store.albumOrder) {
                            ForEach(AlbumOrder.allCases) { order in Text(order.title).tag(order) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }.accessibilityLabel("Sort albums")
                }
            }
        }
        .pageBackground()
        .refreshable { await store.loadLibrary(category) }
        .task(id: "\(category.rawValue):\(category == .albums ? store.albumOrder.rawValue : ""):\(store.sessionID)") {
            await store.ensureLibrary(category)
        }
    }

    @ViewBuilder private var content: some View {
        switch category {
        case .albums:
            if !store.albums.isEmpty {
                AlbumGrid(albums: store.albums)
                if store.moreAlbums && message == nil {
                    ScrollPaginationTrigger(enabled: !loading) { await store.loadLibrary(.albums, more: true) }
                        .id("\(store.sessionID):\(store.albumOrder.rawValue):\(store.albums.count)")
                }
            } else {
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
            if store.songs.isEmpty {
                empty(
                    "No songs yet", symbol: "music.note",
                    message: "Songs in your server's music library will appear here.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.songs.enumerated()), id: \.element.id) { index, song in
                        VStack(spacing: 0) {
                            SongRow(song: song) { player.play(store.songs, at: index) }
                            Divider().overlay(theme.border).padding(.leading, 66)
                        }
                    }
                }
                if store.moreSongs && message == nil {
                    ScrollPaginationTrigger(enabled: !loading) { await store.loadLibrary(.songs, more: true) }
                        .id("\(store.sessionID):\(store.songs.count)")
                }
            }
        case .playlists:
            if store.playlists.isEmpty {
                empty(
                    "Make a mix", symbol: "music.note.list",
                    message: "Create playlists in Navidrome and they'll be waiting here.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(store.playlists) { playlist in
                        VStack(spacing: 0) {
                            NavigationLink {
                                PlaylistDetailView(playlist: playlist)
                            } label: {
                                HStack(spacing: 10) {
                                    ArtworkView(id: playlist.coverArt, size: 192).frame(width: 64, height: 64)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(playlist.name).font(.headline).foregroundStyle(.white)
                                        Text(
                                            "\(playlist.songCount ?? 0) tracks · \(TimeLabel.duration(playlist.duration ?? 0))"
                                        )
                                        .font(.caption).foregroundStyle(theme.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.secondary)
                                }.padding(.vertical, 4).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider().overlay(theme.border).padding(.leading, 74)
                        }
                    }
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
