import SwiftUI
import GevunCore

struct PlaylistDetailView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    private var player: PlayerStore { store.player }
    let playlist: Playlist
    @State private var songs: [Song] = []
    @State private var loaded = false
    @State private var loading = true
    @State private var message: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ArtworkView(id: playlist.coverArt, size: 1200)
                    .frame(maxWidth: 420).frame(maxWidth: .infinity).padding(.top, 6)
                    .shadow(color: .black.opacity(0.4), radius: 25, y: 15)
                VStack(alignment: .leading, spacing: 6) {
                    Text(playlist.name).font(.system(.title, design: .rounded).weight(.bold))
                    Text("Playlist · \(playlist.owner ?? "Your collection")").font(.headline).foregroundStyle(
                        theme.accent)
                    HStack(spacing: 8) {
                        if loaded {
                            Text("\(songs.count) tracks"); Text("·");
                            Text(TimeLabel.duration(songs.reduce(0) { $0 + ($1.duration ?? 0) }))
                        }
                    }.font(.caption).foregroundStyle(theme.secondary)
                }
                HStack(spacing: 8) {
                    Button {
                        player.play(songs)
                    } label: {
                        Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent).foregroundStyle(theme.background)
                    Button {
                        player.play(songs, at: Int.random(in: 0..<max(1, songs.count)), shuffle: true)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity).padding(.vertical, 5)
                    }.buttonStyle(.bordered)
                }.buttonBorderShape(.roundedRectangle(radius: 16)).disabled(songs.isEmpty)
                if let message { ErrorCard(message: message) { Task { await load() } } }
                if loading { ProgressView().frame(maxWidth: .infinity).padding(20) }
                if loaded && songs.isEmpty {
                    ContentUnavailableView(
                        "No tracks available", systemImage: "music.note",
                        description: Text("This collection has no playable tracks."))
                }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                        VStack(alignment: .leading, spacing: 0) {
                            SongRow(song: song) { player.play(songs, at: index) }
                            Divider().overlay(theme.border)
                        }
                    }
                }
            }.padding(.horizontal, 16).padding(.bottom, 20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .navigationTitle("Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .pageBackground()
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let api = store.api else { return }
        loading = true
        message = nil
        do {
            let tracks = try await api.playlist(playlist.id).songs
            guard !Task.isCancelled, store.api === api else { return }
            songs = tracks
            loaded = true
        } catch { if !Task.isCancelled { message = friendlyError(error) } }
        loading = false
    }
}
