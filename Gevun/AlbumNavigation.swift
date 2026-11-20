import SwiftUI
import GevunCore

/// An album to open, and whether to show only its downloaded songs.
struct AlbumRoute: Hashable {
    let album: Album
    let downloadedOnly: Bool
}

extension EnvironmentValues {
    /// Pushes an album onto the surrounding `AlbumNavigationStack`, for menu items such as "Go to Album".
    @Entry var openAlbum: ((AlbumRoute) -> Void)? = nil
}

/// A navigation stack with one stable route for opening albums from menus.
struct AlbumNavigationStack<Root: View>: View {
    @State private var path = NavigationPath()
    @ViewBuilder var root: Root

    var body: some View {
        NavigationStack(path: $path) {
            root.navigationDestination(for: AlbumRoute.self) { route in
                AlbumDetailView(album: route.album, downloadedOnly: route.downloadedOnly)
            }
        }
        .environment(\.openAlbum) { path.append($0) }
    }
}

/// The long-press preview: a large cover with its details on a raised card, like the TV app.
struct AlbumPreview: View {
    @Environment(\.appTheme) private var theme
    let album: Album
    private var details: String {
        [album.year.map(String.init), album.genre].compactMap { $0 }.joined(separator: " · ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ArtworkView(id: album.coverArt, size: 600, cornerRadius: 10)
                .frame(width: 268, height: 268).padding(.bottom, 10)
            Text(album.name).font(.title3).foregroundStyle(.white).lineLimit(2)
            Text(album.artistName).font(.body).foregroundStyle(theme.secondary).lineLimit(1)
            if !details.isEmpty {
                Text(details).font(.subheadline).foregroundStyle(theme.secondary).lineLimit(1)
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(Color(white: 0.12))
        .environment(\.colorScheme, .dark)
    }
}
