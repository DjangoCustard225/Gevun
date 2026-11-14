import SwiftUI
import GevunCore

struct PlaylistsView: View {
    @Environment(AppStore.self) private var store
    @State private var renaming: Playlist?
    @State private var deleting: Playlist?

    var body: some View {
        Group {
            if store.playlists.isEmpty {
                ScrollView {
                    VStack(spacing: 16) {
                        if let message = store.playlistsError {
                            ErrorState(message: message) { Task { await store.loadPlaylists() } }
                        } else if store.playlistsLoading {
                            ProgressView().accessibilityLabel("Loading playlists").padding(.vertical, 24)
                        }
                    }.padding(16).readingWidth()
                }
                .overlay {
                    if store.playlistsLoaded && store.playlistsError == nil {
                        ContentUnavailableView {
                            Label("No playlists yet", systemImage: "music.note.list")
                        } description: {
                            Text("Create a playlist, then add songs from any song’s menu.")
                        } actions: {
                            Button("New Playlist", systemImage: "plus") { store.newPlaylistRequest = [] }
                                .buttonStyle(.glass).controlSize(.large)
                        }
                    }
                }
            } else {
                list
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Playlist", systemImage: "plus") { store.newPlaylistRequest = [] }
            }
        }
        .pageBackground()
        .refreshable { await store.loadPlaylists() }
        .task(id: store.sessionID) { await store.ensurePlaylists() }
        .playlistNameAlert(
            "Rename Playlist", item: $renaming, initialName: { $0.name }, confirmTitle: "Save"
        ) { playlist, name in
            Task { await store.renamePlaylist(playlist, to: name) }
        }
        .playlistDeleteConfirmation($deleting)
    }

    private var list: some View {
        List {
            if let message = store.playlistsError {
                ErrorState(message: message) { Task { await store.loadPlaylists() } }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(store.playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlist: playlist)
                } label: {
                    PlaylistRow(playlist: playlist)
                }
                .listRowBackground(Color.clear)
                .contextMenu {
                    Button("Play", systemImage: "play.fill") { Task { await store.playPlaylist(playlist) } }
                    Button("Shuffle", systemImage: "shuffle") {
                        Task { await store.playPlaylist(playlist, shuffle: true) }
                    }
                    if store.canEdit(playlist) {
                        Button("Rename", systemImage: "pencil") { renaming = playlist }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = playlist }
                    }
                }
                .swipeActions {
                    if store.canEdit(playlist) {
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = playlist }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct PlaylistRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    let playlist: Playlist
    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(id: playlist.coverArt, size: 192).frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                Text(playlist.summary(mine: store.canEdit(playlist)))
                    .font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

extension Playlist {
    /// Song count and length, plus the owner for playlists shared by someone else.
    func summary(mine: Bool) -> String {
        let count = songCount ?? 0
        let summary = count > 0 ? "\(count.counted("song")) · \(TimeLabel.duration(duration ?? 0))" : "Empty"
        guard !mine, let owner, !owner.isEmpty else { return summary }
        return "\(summary) · \(owner)"
    }
}

// MARK: Prompts

extension View {
    /// Asks for a playlist name while `item` is set; the field starts with `initialName(item)`.
    func playlistNameAlert<Item>(
        _ title: String, item: Binding<Item?>, initialName: @escaping (Item) -> String, confirmTitle: String,
        action: @escaping (Item, String) -> Void
    ) -> some View {
        modifier(
            PlaylistNameAlert(
                title: title, item: item, initialName: initialName, confirmTitle: confirmTitle, action: action))
    }

    /// Presents the "New Playlist" prompt for `AppStore.newPlaylistRequest`. Attach it once per
    /// presentation layer and pass `isActive: false` where another layer is on screen.
    func newPlaylistPrompt(isActive: Bool = true) -> some View {
        modifier(NewPlaylistPrompt(isActive: isActive))
    }

    /// Confirms deleting the playlist in `playlist`, then runs `deleted` once the server accepts it.
    func playlistDeleteConfirmation(_ playlist: Binding<Playlist?>, deleted: @escaping () -> Void = {}) -> some View {
        modifier(PlaylistDeleteConfirmation(playlist: playlist, deleted: deleted))
    }
}

private struct PlaylistNameAlert<Item>: ViewModifier {
    let title: String
    @Binding var item: Item?
    let initialName: (Item) -> String
    let confirmTitle: String
    let action: (Item, String) -> Void
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $item.isPresent()) {
                TextField("Playlist name", text: $name)
                Button("Cancel", role: .cancel) { item = nil }
                Button(confirmTitle) {
                    if let item { action(item, name) }
                    item = nil
                }
            }
            .onChange(of: item != nil, initial: true) { _, isSet in
                if isSet, let item { name = initialName(item) }
            }
    }
}

private struct NewPlaylistPrompt: ViewModifier {
    @Environment(AppStore.self) private var store
    let isActive: Bool

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.playlistNameAlert(
            "New Playlist", item: isActive ? $store.newPlaylistRequest : .constant(nil),
            initialName: { _ in "" }, confirmTitle: "Create"
        ) { songs, name in
            Task { await store.createPlaylist(name: name, songs: songs) }
        }
    }
}

private struct PlaylistDeleteConfirmation: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var playlist: Playlist?
    let deleted: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete “\(playlist?.name ?? "")”?",
            isPresented: $playlist.isPresent(),
            titleVisibility: .visible, presenting: playlist
        ) { playlist in
            Button("Delete Playlist", role: .destructive) {
                Task { if await store.deletePlaylist(playlist) { deleted() } }
            }
        } message: { _ in
            Text("The playlist is deleted from your server. The songs stay in your library.")
        }
    }
}
