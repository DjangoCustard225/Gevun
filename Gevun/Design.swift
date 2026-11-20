import SwiftUI
import GevunCore

enum Theme {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.05)
    static let surface = Color(red: 0.075, green: 0.09, blue: 0.10)
    static let elevated = Color(red: 0.115, green: 0.13, blue: 0.14)
    static let defaultAccent = Color.white
    static let secondary = Color(red: 0.59, green: 0.65, blue: 0.63)
    static let border = Color.white.opacity(0.08)
    static let artworkCornerRadius: CGFloat = 3
    static let playerArtworkCornerRadius: CGFloat = 8
}

extension View {
    func pageBackground() -> some View {
        modifier(PageBackground())
    }

    func readingWidth() -> some View { frame(maxWidth: 1000).frame(maxWidth: .infinity) }
}

private struct PageBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(AppBackground()).scrollContentBackground(.hidden).scrollEdgeEffectStyle(.soft, for: .all)
            .toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
            // Bars still shrink on scroll, but the page's insets stay put. Otherwise a swipe back that starts
            // with shrunk bars loops forever (iOS 27): new insets move the scroll offset, which resizes the bars.
            .toolbarMinimizationSafeAreaAdjustment(.disabled, for: .navigationBar)
            .toolbarMinimizationSafeAreaAdjustment(.disabled, for: .tabBar)
    }
}

/// The app icon, drawn in SwiftUI: an obsidian platter with a spindle hole and an orange tonearm
/// on alabaster. Proportions follow the 1024-point icon artwork.
struct BrandMark: View {
    var size: CGFloat = 64
    private let alabaster = Color(red: 0.961, green: 0.957, blue: 0.941)
    private let obsidian = Color(red: 0.078, green: 0.078, blue: 0.086)
    private let orange = Color(red: 1, green: 0.353, blue: 0.122)

    var body: some View {
        Canvas { context, canvas in
            let unit = canvas.width / 1024
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
            func circle(_ radius: CGFloat) -> Path {
                Path(
                    ellipseIn: CGRect(
                        x: (512 - radius) * unit, y: (512 - radius) * unit, width: radius * 2 * unit,
                        height: radius * 2 * unit))
            }
            context.fill(Path(CGRect(origin: .zero, size: canvas)), with: .color(alabaster))
            context.fill(circle(300), with: .color(obsidian))
            context.fill(circle(26), with: .color(alabaster))
            var arm = Path()
            arm.move(to: point(822, 206))
            arm.addLine(to: point(614, 636))
            context.stroke(
                arm, with: .color(orange), style: StrokeStyle(lineWidth: 42 * unit, lineCap: .round))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct ArtworkView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    let id: String?
    var size: Int = 600
    var cornerRadius: CGFloat = Theme.artworkCornerRadius
    @State private var image: UIImage?
    var body: some View {
        // A cached cover shows in the row's first frame, so scrolling back doesn't flash the placeholder.
        let shown =
            id.flatMap { id in store.api.flatMap { store.artwork.cachedImage(id: id, api: $0, size: size) } } ?? image
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let shown { Image(uiImage: shown).resizable().scaledToFill() } else { ArtworkPlaceholder() }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(
                    theme.border, lineWidth: 1)
            }
            .task(id: "\(store.activeID?.uuidString ?? ""):\(id ?? ""):\(size)") {
                guard let id, let api = store.api else {
                    image = nil
                    return
                }
                image = store.artwork.cachedImage(id: id, api: api, size: size)
                if image != nil { return }
                let result = await store.artwork.image(id: id, api: api, size: size)
                guard !Task.isCancelled else { return }
                image = result
            }
            .accessibilityHidden(true)
    }
}

/// Drawn in one pass (no view tree per cover), since many show at once while covers load.
private struct ArtworkPlaceholder: View {
    @Environment(\.appTheme) private var theme
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func circle(_ diameter: CGFloat) -> Path {
                Path(
                    ellipseIn: CGRect(
                        x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
            }
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [theme.elevated, theme.surface]), startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)))
            context.stroke(circle(side * 0.72), with: .color(.white.opacity(0.06)), lineWidth: side * 0.10)
            context.stroke(circle(side * 0.54), with: .color(.white.opacity(0.10)), lineWidth: 1)
            context.fill(circle(side * 0.30), with: .color(.black.opacity(0.35)))
            let note = context.resolve(
                Text(Image(systemName: "music.note")).font(.system(size: max(1, side * 0.14), weight: .medium))
                    .foregroundStyle(.white.opacity(0.65)))
            context.draw(note, at: center, anchor: .center)
        }
    }
}

struct AlbumCard: View {
    @Environment(\.appTheme) private var theme
    let album: Album
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ArtworkView(id: album.coverArt)
            Text(album.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
            Text(album.artistName).font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
    }
}

struct AlbumGrid: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @Environment(\.openAlbum) private var openAlbum
    let albums: [Album]
    var downloadedOnly = false
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160, maximum: 280), spacing: 12, alignment: .top)],
            alignment: .leading, spacing: 16
        ) {
            ForEach(albums) { album in
                NavigationLink {
                    AlbumDetailView(album: album, downloadedOnly: downloadedOnly)
                } label: {
                    AlbumCard(album: album)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    // Tapping a custom preview only closes the menu, so this opens the album instead.
                    if let openAlbum {
                        Button("Go to Album", systemImage: "info.circle") {
                            openAlbum(AlbumRoute(album: album, downloadedOnly: downloadedOnly))
                        }
                    }
                    AlbumActions(album: album, downloadedOnly: downloadedOnly)
                } preview: {
                    // Previews are drawn outside this view, so hand them what the artwork needs.
                    AlbumPreview(album: album).environment(store).environment(\.appTheme, theme)
                }
            }
        }
    }
}

struct AlbumActions: View {
    @Environment(AppStore.self) private var store
    let album: Album
    var downloadedOnly = false
    var body: some View {
        Button("Play", systemImage: "play.fill") { play(shuffle: false) }
        Button("Shuffle", systemImage: "shuffle") { play(shuffle: true) }
        Button("Download", systemImage: "arrow.down.circle") { Task { await store.downloadAlbum(album) } }
        FavoriteButton(id: album.id, starred: album.starred, kind: .album)
        ServerShareButton(ids: [album.id])
    }

    private func play(shuffle: Bool) {
        if downloadedOnly, let namespace = store.downloadNamespace {
            store.player.start(store.downloads.savedSongs(albumID: album.id, namespace: namespace), shuffle: shuffle)
        } else {
            Task { await store.playAlbum(album, shuffle: shuffle) }
        }
    }
}

struct ScrollPaginationTrigger: View {
    let enabled: Bool
    let load: () async -> Void
    @State private var visible = false
    @State private var request: Task<Void, Never>?
    @State private var revision = UUID()

    var body: some View {
        Color.clear.frame(height: 1)
            .accessibilityHidden(true)
            .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }
            .onChange(of: enabled && visible, initial: true) { _, ready in
                guard ready, request == nil else { return }
                let token = UUID()
                revision = token
                request = Task {
                    await load()
                    if revision == token { request = nil }
                }
            }
            .onDisappear {
                revision = UUID()
                request?.cancel()
                request = nil
                visible = false
            }
    }
}

/// Marks the song that's playing. The bars animate while audio plays and rest while paused.
struct PlayingIndicator: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var interface: PlaybackInterfaceState
    var body: some View {
        Image(systemName: "waveform")
            .symbolEffect(
                .variableColor.iterative.dimInactiveLayers.nonReversing,
                isActive: interface.isPlaying && !reduceMotion
            )
            .foregroundStyle(theme.accent)
            .accessibilityLabel(interface.isPlaying ? "Now playing" : "Paused")
    }
}

struct SongRow: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var interface: PlaybackInterfaceState
    let song: Song
    var action: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 10) {
                    ArtworkView(id: song.coverArt, size: 192).frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title).font(.subheadline.weight(.medium)).foregroundStyle(
                            interface.current?.id == song.id ? theme.accent : .white
                        ).lineLimit(2)
                        Text(song.artistName).font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if interface.current?.id == song.id {
                        // The accent is white like every title, so mark the playing song with a symbol.
                        PlayingIndicator().font(.caption)
                    }
                    DownloadedMark(songID: song.id)
                }.frame(minHeight: 44).contentShape(Rectangle()).padding(.vertical, 4)
            }.buttonStyle(.plain)
            Menu {
                SongActions(song: song)
            } label: {
                Image(systemName: "ellipsis").font(.body).foregroundStyle(theme.secondary).frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }.accessibilityLabel("Actions for \(song.title)")
        }
    }
}

/// "Play next" and "Add to queue" for one song or a whole album or playlist.
struct QueueActions: View {
    @Environment(AppStore.self) private var store
    let songs: [Song]
    var body: some View {
        Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            store.player.add(songs, next: true)
        }
        Button("Add to queue", systemImage: "text.badge.plus") { store.player.add(songs, next: false) }
    }
}

/// The menu shared by every song row. `remove` adds "Remove from Playlist".
struct SongActions: View {
    let song: Song
    var remove: (() -> Void)? = nil
    var body: some View {
        QueueActions(songs: [song])
        AddToPlaylistMenu(songs: [song])
        FavoriteButton(id: song.id, starred: song.starred, kind: .song)
        if let remove {
            Button("Remove from Playlist", systemImage: "minus.circle", role: .destructive, action: remove)
        }
        SongDownloadActions(song: song)
    }
}

/// Adds or removes a song, album or artist from the server's favourites.
struct FavoriteButton: View {
    @Environment(AppStore.self) private var store
    let id: String
    let starred: String?
    let kind: FavoriteKind
    var body: some View {
        let favorite = store.isFavorite(id, starred: starred)
        Button(
            favorite ? "Remove from Favorites" : "Add to Favorites", systemImage: favorite ? "heart.slash" : "heart"
        ) {
            Task { await store.setFavorite(!favorite, id: id, kind: kind) }
        }
    }
}

/// Streaming quality from Settings, chosen separately for Wi-Fi and mobile data.
enum PlaybackSettings {
    static let wifiQualityKey = "streamQualityWiFi"
    static let cellularQualityKey = "streamQualityCellular"

    static func streamingQuality(onWiFi: Bool) -> DownloadQuality {
        let key = onWiFi ? wifiQualityKey : cellularQualityKey
        return DownloadQuality(storageValue: UserDefaults.standard.string(forKey: key) ?? "original")
    }

}

/// The round glass play button under an album or playlist heading.
struct PlayButton: View {
    /// "album" or "playlist", for VoiceOver.
    let kind: String
    let songs: [Song]
    @Environment(AppStore.self) private var store
    var body: some View {
        Button {
            store.player.play(songs)
        } label: {
            Image(systemName: "play.fill").font(.system(size: 24, weight: .semibold))
                .offset(x: 2).frame(width: 44, height: 44)
        }.buttonStyle(.glass).controlSize(.large).buttonBorderShape(.circle)
            .foregroundStyle(.white).disabled(songs.isEmpty)
            .accessibilityLabel("Play \(kind)").accessibilityHint("Play songs in \(kind) order")
            .frame(maxWidth: .infinity)
    }
}

/// A tick for rows that can be selected, such as tabs and songs to add.
struct SelectionMark: View {
    @Environment(\.appTheme) private var theme
    let isSelected: Bool
    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3).foregroundStyle(isSelected ? theme.accent : theme.secondary)
    }
}

/// Small cover with a one-line title and artist, for lists that pick or reorder songs.
struct CompactSongLabel: View {
    @Environment(\.appTheme) private var theme
    let song: Song
    var artwork: CGFloat = 44
    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(id: song.coverArt, size: 192).frame(width: artwork, height: artwork)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                Text(song.artistName).font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
            }
        }
    }
}

extension Int {
    /// "1 song", "3 songs".
    func counted(_ noun: String) -> String { "\(self) \(self == 1 ? noun : noun + "s")" }
}

extension [Song] {
    /// "12 songs · 48 min".
    var summary: String {
        "\(count.counted("song")) · \(TimeLabel.duration(reduce(0) { $0 + ($1.duration ?? 0) }))"
    }
}

extension Binding {
    /// True while the optional holds a value; setting false clears it. For alerts and dialogs.
    func isPresent<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(get: { wrappedValue != nil }, set: { if !$0 { wrappedValue = nil } })
    }
}

/// "Add to Playlist" submenu: the user's own playlists, most recently changed first, plus a new one.
struct AddToPlaylistMenu: View {
    @Environment(AppStore.self) private var store
    let songs: [Song]
    var body: some View {
        Menu {
            Button("New Playlist…", systemImage: "plus") { store.newPlaylistRequest = songs }
            let playlists = store.editablePlaylists
            if !playlists.isEmpty {
                Section {
                    ForEach(playlists) { playlist in
                        Button(playlist.name, systemImage: "music.note.list") {
                            Task { await store.addToPlaylist(songs, playlist) }
                        }
                    }
                }
            }
        } label: {
            Label("Add to Playlist", systemImage: "music.note.list")
        }
        .disabled(songs.isEmpty)
    }
}

struct SectionTitle: View {
    let title: String
    var body: some View {
        Text(title).font(.title3.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A load failure in the same centred style as the empty states, with a way to retry.
struct ErrorState: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t load your music", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: retry).buttonStyle(.glass)
        }
    }
}
