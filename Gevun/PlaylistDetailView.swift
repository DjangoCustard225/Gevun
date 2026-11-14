import SwiftUI
import GevunCore

/// Laid out like `AlbumDetailView`: full-bleed cover, centered heading, play button, numbered tracks.
struct PlaylistDetailView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private var player: PlayerStore { store.player }
    let playlist: Playlist
    @State private var detail: Playlist?
    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var message: String?
    @State private var revision = UUID()
    @State private var renaming: Playlist?
    @State private var deleting: Playlist?
    @State private var addingSongs = false
    @State private var editing = false

    /// The latest listing wins over the copy this page was opened with, so renames show at once.
    private var shown: Playlist {
        detail ?? store.playlists.first { $0.id == playlist.id } ?? playlist
    }
    private var editable: Bool { store.canEdit(shown) }
    /// Whose playlist it is, when it isn't yours, and when it last changed.
    private var caption: String {
        var parts: [String] = []
        if shown.readonly == true {
            parts.append("Smart playlist")
        } else if !editable, let owner = shown.owner, !owner.isEmpty {
            parts.append("By \(owner)")
        }
        if let changed = shown.changedDate {
            parts.append("Updated \(changed.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ArtworkPage(coverArt: shown.coverArt) {
            VStack(spacing: 24) {
                heading
                PlayButton(kind: "playlist", songs: songs)
                if let message { ErrorState(message: message) { Task { await load() } } }
                if loading && detail == nil {
                    ProgressView().accessibilityLabel("Loading playlist")
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if detail != nil && songs.isEmpty {
                    emptyPlaylist
                }
                if !songs.isEmpty { trackList }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { actions }
        }
        // Reloads after edits, and once the network comes back.
        .task(id: "\(store.sessionID):\(playlist.id):\(store.playlistRevision):\(store.downloads.connected)") {
            await load()
        }
        .sheet(isPresented: $addingSongs) { PlaylistSongPicker(playlist: shown) }
        .sheet(isPresented: $editing) { PlaylistEditor(playlist: shown, songs: songs) }
        .playlistNameAlert(
            "Rename Playlist", item: $renaming, initialName: { $0.name }, confirmTitle: "Save"
        ) { playlist, name in
            Task { await store.renamePlaylist(playlist, to: name) }
        }
        .playlistDeleteConfirmation($deleting) { dismiss() }
        .listeningLinkPresentation()
    }

    private var heading: some View {
        VStack(spacing: 8) {
            Text(shown.name).font(.title2.weight(.bold)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            if !caption.isEmpty {
                Text(caption).font(.subheadline.weight(.medium)).foregroundStyle(theme.secondary)
            }
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }

    private var trackList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            Divider().overlay(theme.border)
            // A song can appear more than once, so rows are identified by position.
            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                VStack(alignment: .leading, spacing: 0) {
                    AlbumTrackRow(
                        song: song, number: index + 1, showArtist: true,
                        remove: editable
                            ? { Task { await store.removeFromPlaylist(shown, at: [index]) } } : nil
                    ) {
                        player.play(songs, at: index)
                    }
                    Divider().overlay(theme.border).padding(.leading, 34)
                }
            }
            Text(songs.summary).font(.caption).foregroundStyle(theme.secondary).padding(.top, 20)
        }
    }

    private var actions: some View {
        Menu {
            Section {
                Button("Play", systemImage: "play.fill") { player.play(songs) }
                Button("Shuffle", systemImage: "shuffle") { player.start(songs, shuffle: true) }
                QueueActions(songs: songs)
            }.disabled(songs.isEmpty)
            Section {
                ServerShareButton(ids: [shown.id])
                Button("Download", systemImage: "arrow.down.circle") {
                    if let instance = store.api?.instance {
                        store.downloadSelection = DownloadSelection(songs: songs, album: nil, instance: instance)
                    }
                }.disabled(songs.isEmpty)
            }
            if editable {
                Section {
                    Button("Add Songs", systemImage: "plus") { addingSongs = true }
                    Button("Edit Order", systemImage: "arrow.up.arrow.down") { editing = true }
                        .disabled(songs.isEmpty)
                    Button("Rename", systemImage: "pencil") { renaming = shown }
                    Button("Delete Playlist", systemImage: "trash", role: .destructive) { deleting = shown }
                }
            }
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(.white)
        }
        .accessibilityLabel("Playlist actions")
    }

    @ViewBuilder private var emptyPlaylist: some View {
        if editable {
            ContentUnavailableView {
                Label("No songs yet", systemImage: "music.note")
            } description: {
                Text("Add songs here, or choose Add to Playlist from any song’s menu.")
            } actions: {
                Button("Add Songs", systemImage: "plus") { addingSongs = true }
                    .buttonStyle(.glass).controlSize(.large)
            }
        } else {
            ContentUnavailableView("No songs yet", systemImage: "music.note")
        }
    }

    private func load() async {
        guard let api = store.api else { return }
        let token = UUID()
        revision = token
        loading = true
        message = nil
        defer { if revision == token { loading = false } }
        guard store.downloads.connected else {
            if detail == nil { message = "Connect to your server to load this playlist." }
            return
        }
        do {
            let value = try await api.playlist(playlist.id)
            guard !Task.isCancelled, revision == token, store.api === api else { return }
            detail = value
            songs = value.songs
        } catch {
            if !Task.isCancelled, revision == token, store.api === api { message = friendlyError(error) }
        }
    }
}

/// Reorders and removes playlist songs with list drag handles, then saves them in one request.
private struct PlaylistEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var entries: [Entry]
    @State private var saving = false

    private struct Entry: Identifiable {
        let id = UUID()
        let song: Song
    }

    init(playlist: Playlist, songs: [Song]) {
        self.playlist = playlist
        _entries = State(initialValue: songs.map { Entry(song: $0) })
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries) { entry in
                    CompactSongLabel(song: entry.song, artwork: 40).listRowBackground(Color.clear)
                }
                .onDelete { entries.remove(atOffsets: $0) }
                .onMove { entries.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .navigationTitle(playlist.name).navigationBarTitleDisplayMode(.inline)
            .pageBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            saving = true
                            Task {
                                await store.replacePlaylistSongs(playlist, songs: entries.map(\.song))
                                dismiss()
                            }
                        }
                    }
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }
}

/// Finds songs on the server and appends them to a playlist, in the order they were tapped.
private struct PlaylistSongPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var query = ""
    @State private var results: [Song] = []
    @State private var selected: [Song] = []
    @State private var loading = false
    @State private var message: String?
    @State private var saving = false
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Group {
                if let message {
                    ScrollView { ErrorState(message: message) { Task { await search() } }.padding(16) }
                } else if loading && results.isEmpty {
                    ProgressView().accessibilityLabel("Searching")
                } else if results.isEmpty {
                    if term.isEmpty {
                        ContentUnavailableView(
                            "Find songs", systemImage: "magnifyingglass",
                            description: Text("Search for songs, artists or albums to add."))
                    } else {
                        ContentUnavailableView.search(text: term)
                    }
                } else {
                    List(results) { song in row(song) }.listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
            .searchable(
                text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Songs, artists, albums"
            )
            .navigationTitle("Add to “\(playlist.name)”").navigationBarTitleDisplayMode(.inline)
            .pageBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button(selected.isEmpty ? "Add" : "Add \(selected.count)") {
                            saving = true
                            Task {
                                await store.addToPlaylist(selected, playlist)
                                dismiss()
                            }
                        }
                        .disabled(selected.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(saving || !selected.isEmpty)
            .task(id: term) {
                if !term.isEmpty {
                    do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                }
                await search()
            }
        }
    }

    private func search() async {
        guard let api = store.api else { return }
        let term = term
        loading = true
        message = nil
        defer { if self.term == term { loading = false } }
        do {
            let songs =
                term.isEmpty
                ? try await api.songs(offset: 0, size: 100)
                : try await api.search(term).songs
            guard !Task.isCancelled, self.term == term else { return }
            results = songs
        } catch {
            if !Task.isCancelled, self.term == term { message = friendlyError(error) }
        }
    }

    private func row(_ song: Song) -> some View {
        let isSelected = selected.contains { $0.id == song.id }
        return Button {
            if isSelected { selected.removeAll { $0.id == song.id } } else { selected.append(song) }
        } label: {
            HStack(spacing: 10) {
                CompactSongLabel(song: song)
                Spacer(minLength: 4)
                SelectionMark(isSelected: isSelected)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
