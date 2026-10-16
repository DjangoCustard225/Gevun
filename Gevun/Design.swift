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

    func panel(radius: CGFloat = 22) -> some View {
        modifier(PanelBackground(radius: radius))
    }

    func readingWidth() -> some View { frame(maxWidth: 1000).frame(maxWidth: .infinity) }
}

private struct PageBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(AppBackground()).scrollContentBackground(.hidden).scrollEdgeEffectStyle(.soft, for: .all)
            .toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
    }
}

private struct PanelBackground: ViewModifier {
    @Environment(\.appTheme) private var theme
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.background(theme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(theme.border, lineWidth: 1) }
    }
}

struct BrandMark: View {
    @Environment(\.appTheme) private var theme
    var size: CGFloat = 64
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28).fill(theme.accent.gradient)
            Image(systemName: "headphones")
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(theme.background)
        }.frame(width: size, height: size).accessibilityHidden(true)
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
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() } else { ArtworkPlaceholder() }
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

private struct ArtworkPlaceholder: View {
    @Environment(\.appTheme) private var theme
    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ZStack {
                LinearGradient(
                    colors: [theme.elevated, theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().stroke(Color.white.opacity(0.06), lineWidth: side * 0.10).frame(width: side * 0.72)
                Circle().stroke(Color.white.opacity(0.10), lineWidth: 1).frame(width: side * 0.54)
                Circle().fill(Color.black.opacity(0.35)).frame(width: side * 0.30)
                Image(systemName: "music.note").font(.system(size: side * 0.14, weight: .medium)).foregroundStyle(
                    .white.opacity(0.65))
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

struct AlbumCard: View {
    @Environment(\.appTheme) private var theme
    let album: Album
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ArtworkView(id: album.coverArt)
            Text(album.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
            Text(album.artistName).font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
    }
}

struct AlbumGrid: View {
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
                .contextMenu { AlbumActions(album: album, downloadedOnly: downloadedOnly) }
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
        Button("Download…", systemImage: "arrow.down.circle") { Task { await store.downloadAlbum(album) } }
    }

    private func play(shuffle: Bool) {
        if downloadedOnly, let namespace = store.downloadNamespace {
            let songs = store.downloads.savedSongs(albumID: album.id, namespace: namespace)
            store.player.play(songs, at: shuffle ? Int.random(in: 0..<max(1, songs.count)) : 0, shuffle: shuffle)
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

struct SongRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    private var player: PlayerStore { store.player }
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
                    DownloadedMark(songID: song.id)
                    Text(TimeLabel.clock(Double(song.duration ?? 0))).font(.caption).monospacedDigit().foregroundStyle(
                        theme.secondary)
                }.frame(minHeight: 44).contentShape(Rectangle()).padding(.vertical, 4)
            }.buttonStyle(.plain)
            Menu {
                Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    player.add(song, next: true)
                }
                Button("Add to queue", systemImage: "text.badge.plus") { player.add(song, next: false) }
                SongDownloadActions(song: song)
            } label: {
                Image(systemName: "ellipsis").font(.body).foregroundStyle(theme.secondary).frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }.accessibilityLabel("Actions for \(song.title)")
        }
    }
}

struct SectionTitle: View {
    let title: String
    var body: some View {
        Text(title).font(.title3.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ErrorCard: View {
    @Environment(\.appTheme) private var theme
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Couldn't load your music", systemImage: "wifi.exclamationmark").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(theme.secondary)
            Button("Try again", systemImage: "arrow.clockwise", action: retry).buttonStyle(.bordered)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panel()
    }
}
