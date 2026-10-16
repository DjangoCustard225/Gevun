import SwiftUI
import GevunCore

struct AlbumDetailView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    private var player: PlayerStore { store.player }
    let album: Album
    var downloadedOnly = false
    @State private var detail: Album?
    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var message: String?
    @State private var revision = UUID()

    private var displayedAlbum: Album { detail ?? album }
    private var metadata: String {
        [
            (displayedAlbum.genre ?? album.genre)?.trimmingCharacters(in: .whitespacesAndNewlines),
            (displayedAlbum.year ?? album.year).map(String.init),
        ]
        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private var artist: Artist? {
        let credits = displayedAlbum.artists ?? album.artists ?? []
        let ids = [displayedAlbum.artistId, album.artistId] + credits.map(\.id)
        guard
            let id = ids.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty })
        else { return nil }
        return store.artists.first { $0.id == id }
            ?? Artist(id: id, name: credits.first { $0.id == id }?.name ?? displayedAlbum.artistName)
    }
    private var hasMultipleDiscs: Bool { songs.contains { ($0.discNumber ?? 1) > 1 } }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ArtworkHeaderView(id: displayedAlbum.coverArt ?? album.coverArt)
                VStack(spacing: 24) {
                    albumHeading
                    playButton
                    if let message { ErrorCard(message: message) { Task { await load() } } }
                    if loading {
                        ProgressView().accessibilityLabel("Loading album")
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else if detail != nil && songs.isEmpty {
                        ContentUnavailableView("No tracks available", systemImage: "music.note")
                    }
                    if !songs.isEmpty { trackList }
                }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 28)
            }.frame(maxWidth: 640).frame(maxWidth: .infinity)
                .background { NativeScrollToTop().frame(width: 0, height: 0) }
        }
        .ignoresSafeArea(.container, edges: .top)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .pageBackground()
        .modifier(ArtworkScrollEdges())
        .tint(.white)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: "\(displayedAlbum.name) — \(displayedAlbum.artistName)") {
                    Image(systemName: "square.and.arrow.up").foregroundStyle(.white)
                }.accessibilityLabel("Share album")
                Menu {
                    Button("Download…", systemImage: "arrow.down.circle") {
                        if let instance = store.api?.instance {
                            store.downloadSelection = DownloadSelection(
                                songs: songs, album: displayedAlbum, instance: instance)
                        }
                    }
                    Button("Play album", systemImage: "play.fill") { player.play(songs) }
                    Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                        if player.current == nil {
                            player.play(songs)
                        } else {
                            songs.reversed().forEach { player.add($0, next: true) }
                        }
                    }
                    Button("Add to queue", systemImage: "text.badge.plus") {
                        songs.forEach { player.add($0, next: false) }
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(.white)
                }
                .disabled(songs.isEmpty).accessibilityLabel("Album actions")
            }
        }
        .task(id: "\(store.sessionID):\(album.id)") { await load() }
        .onChange(of: store.downloads.savedKeys) { _, _ in
            if downloadedOnly, let namespace = store.downloadNamespace {
                songs = store.downloads.savedSongs(albumID: album.id, namespace: namespace)
            }
        }
    }

    private var albumHeading: some View {
        VStack(spacing: 8) {
            Text(displayedAlbum.name).font(.title2.weight(.bold)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            if let artist {
                NavigationLink {
                    ArtistDetailView(artist: artist)
                } label: {
                    Text(displayedAlbum.artistName).font(.title3).foregroundStyle(.white.opacity(0.9))
                        .frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityHint("Open artist page")
            } else {
                Text(displayedAlbum.artistName).font(.title3).foregroundStyle(.white.opacity(0.9))
            }
            if !metadata.isEmpty {
                Text(metadata).font(.subheadline.weight(.medium)).foregroundStyle(theme.secondary)
            }
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }

    private var playButton: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                player.play(songs)
            } label: {
                Image(systemName: "play.fill").font(.system(size: 24, weight: .semibold))
                    .offset(x: 2).frame(width: 44, height: 44)
            }.buttonStyle(.glass).controlSize(.large).buttonBorderShape(.circle)
                .foregroundStyle(.white).disabled(songs.isEmpty)
                .accessibilityLabel("Play album").accessibilityHint("Play songs in album order")
            Spacer(minLength: 0)
        }
    }

    private var trackList: some View {
        let multipleDiscs = hasMultipleDiscs
        let albumArtist = displayedAlbum.artistName
        return LazyVStack(alignment: .leading, spacing: 0) {
            Divider().overlay(theme.border)
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                VStack(alignment: .leading, spacing: 0) {
                    if multipleDiscs, index == 0 || songs[index - 1].discNumber != song.discNumber {
                        Text("DISC \(song.discNumber ?? 1)").font(.caption.weight(.semibold)).tracking(1.5)
                            .foregroundStyle(theme.secondary).padding(.top, 18).padding(.bottom, 8)
                    }
                    AlbumTrackRow(
                        song: song, number: song.track ?? index + 1,
                        showArtist: song.artistName != albumArtist
                    ) {
                        player.play(songs, at: index)
                    }
                    Divider().overlay(theme.border).padding(.leading, 34)
                }
            }
            Text(
                "\(songs.count) \(songs.count == 1 ? "song" : "songs") · \(TimeLabel.duration(songs.reduce(0) { $0 + ($1.duration ?? 0) }))"
            )
            .font(.caption).foregroundStyle(theme.secondary).padding(.top, 20)
        }
    }

    private func load() async {
        guard let api = store.api else { return }
        let token = UUID()
        revision = token
        loading = true
        message = nil
        defer { if revision == token { loading = false } }
        let namespace = DownloadKey.namespace(for: api.instance)
        let saved = store.downloads.savedSongs(albumID: album.id, namespace: namespace)
        if downloadedOnly || !store.downloads.connected {
            detail = store.downloads.savedAlbum(album.id, namespace: namespace) ?? album
            songs = saved
            if saved.isEmpty {
                message = "No songs from this album are downloaded. Connect to your server to load them."
            }
            return
        }
        do {
            let value = try await api.album(album.id)
            guard !Task.isCancelled, revision == token, store.api === api else { return }
            detail = value
            songs = value.songs
        } catch {
            if !Task.isCancelled, revision == token, store.api === api {
                if !saved.isEmpty {
                    detail = store.downloads.savedAlbum(album.id, namespace: namespace) ?? album
                    songs = saved
                } else {
                    message = friendlyError(error)
                }
            }
        }
    }
}

private struct AlbumTrackRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    private var player: PlayerStore { store.player }
    let song: Song
    let number: Int
    let showArtist: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Group {
                        if interface.current?.id == song.id {
                            Image(systemName: "waveform").foregroundStyle(theme.accent)
                        } else {
                            Text(String(number)).foregroundStyle(theme.secondary).monospacedDigit()
                        }
                    }.font(.body).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title).font(.body.weight(.medium))
                            .foregroundStyle(interface.current?.id == song.id ? theme.accent : .white).lineLimit(2)
                        if showArtist {
                            Text(song.artistName).font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    DownloadedMark(songID: song.id)
                    Text(TimeLabel.clock(Double(song.duration ?? 0))).font(.caption).monospacedDigit()
                        .foregroundStyle(theme.secondary)
                }.frame(minHeight: 56).contentShape(Rectangle()).padding(.vertical, 4)
            }.buttonStyle(.plain)
            Menu {
                Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    player.add(song, next: true)
                }
                Button("Add to queue", systemImage: "text.badge.plus") { player.add(song, next: false) }
                SongDownloadActions(song: song)
            } label: {
                Image(systemName: "ellipsis").font(.body).foregroundStyle(theme.secondary)
                    .frame(width: 36, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("Actions for \(song.title)")
        }
    }
}
