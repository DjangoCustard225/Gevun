import SwiftUI
import GevunCore

private enum PlayerSheet: Equatable, Identifiable {
    case lyrics, queue
    case album(Album)
    case artist(Artist)
    var id: String {
        switch self {
        case .lyrics: "lyrics"
        case .queue: "queue"
        case .album(let album): "album:\(album.id)"
        case .artist(let artist): "artist:\(artist.id)"
        }
    }
}

struct NowPlayingView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    private var player: PlayerStore { store.player }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let safeAreaInsets: EdgeInsets
    let motion: PlayerDismissalMotion
    let onClose: (CGFloat) -> Void
    @ScaledMetric(relativeTo: .body) private var metadataHeight: CGFloat = 94
    @ScaledMetric(relativeTo: .caption) private var playbackErrorHeight: CGFloat = 76
    @State private var presentedSheet: PlayerSheet?
    @State private var openingArtist = false
    @State private var artistTask: Task<Void, Never>?
    @State private var artistError: String?

    var body: some View {
        GeometryReader { geometry in
            let bodyHeight = max(0, geometry.size.height - safeAreaInsets.top - safeAreaInsets.bottom - 80)
            let controlsHeight = metadataHeight + 44 + 72 + 36 + (interface.error == nil ? 0 : playbackErrorHeight + 12)
            let width = max(0, min(640, geometry.size.width - 24, bodyHeight - controlsHeight))
            ZStack(alignment: .bottom) {
                PlayerBackdrop()
                Group {
                    if let song = interface.current {
                        VStack(spacing: 12) {
                            ArtworkView(id: song.coverArt, size: 1200, cornerRadius: Theme.playerArtworkCornerRadius)
                                .frame(width: width, height: width)
                                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                            PlayerSeekView()
                            VStack(spacing: 4) {
                                Button {
                                    artistTask = Task { await openArtist(song) }
                                } label: {
                                    Text(song.artistName).font(.body).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                                }.buttonStyle(.plain).disabled(openingArtist).accessibilityHint("Open artist page")
                                Text(song.title).font(.headline.weight(.bold)).lineLimit(2)
                                if let albumName = song.album, !albumName.isEmpty {
                                    Button {
                                        artistTask?.cancel()
                                        if let destination = album(for: song) {
                                            presentedSheet = .album(destination)
                                        }
                                    } label: {
                                        Text(albumName).font(.body).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                                    }.buttonStyle(.plain).disabled(song.albumId == nil)
                                        .accessibilityHint("Open album page")
                                }
                            }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
                                .frame(height: metadataHeight)
                            transportControls
                            if let error = interface.error {
                                VStack(spacing: 6) {
                                    Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                                    Button("Retry playback", systemImage: "arrow.clockwise") { player.retry() }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }.frame(minHeight: bodyHeight, alignment: .top)
                            .padding(.horizontal, 12).padding(.top, safeAreaInsets.top + 4)
                            .padding(.bottom, safeAreaInsets.bottom + 76)
                            .frame(maxWidth: 664).frame(maxWidth: .infinity)
                    }
                }
                bottomControls
                    .padding(.horizontal, 20).frame(maxWidth: 664)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, safeAreaInsets.bottom + 12)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .modifier(PlayerSurfaceMotion(motion: motion, reduceMotion: reduceMotion))
            .onAppear { motion.resize(height: geometry.size.height) }
            .onChange(of: geometry.size.height) { _, height in motion.resize(height: height) }
        }
        .contentShape(Rectangle())
        .onChange(of: reduceMotion) { _, _ in motion.interrupt() }
        .onChange(of: presentedSheet) { _, sheet in
            if sheet != nil {
                artistTask?.cancel()
                motion.interrupt()
            }
        }
        .onChange(of: interface.current?.id) { _, _ in artistTask?.cancel() }
        .onChange(of: store.sessionID) { _, _ in
            artistTask?.cancel()
            presentedSheet = nil
            artistError = nil
        }
        .onDisappear {
            artistTask?.cancel()
            motion.stop()
        }
        .accessibilityAction(.escape) { close() }
        .accessibilityAction(named: Text("Close player")) { close() }
        .accessibilityAction(named: Text("Show lyrics")) { presentedSheet = .lyrics }
        .accessibilityAction(named: Text("Show queue")) { presentedSheet = .queue }
        .sheet(item: $presentedSheet) { sheet in
            Group {
                switch sheet {
                case .lyrics: LyricsView()
                case .queue: PlayerQueueSheet()
                case .album(let album): PlayerDetailSheet { AlbumDetailView(album: album) }
                case .artist(let artist): PlayerDetailSheet { ArtistDetailView(artist: artist) }
                }
            }.environment(store).environmentObject(player).presentationDragIndicator(.visible)
        }
        .alert(
            "Artist unavailable",
            isPresented: Binding(get: { artistError != nil }, set: { if !$0 { artistError = nil } })
        ) {
            Button("OK", role: .cancel) { artistError = nil }
        } message: {
            Text(artistError ?? "")
        }
    }

    private var transportControls: some View {
        HStack(spacing: 32) {
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 24)).frame(width: 56, height: 56)
            }.accessibilityLabel("Previous track")
            Button {
                player.toggle()
            } label: {
                ZStack {
                    Circle().fill(.black.opacity(0.32)).frame(width: 64, height: 64)
                    if interface.buffering {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: interface.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 25, weight: .semibold)).offset(x: interface.isPlaying ? 0 : 2)
                    }
                }.frame(width: 72, height: 72)
            }.accessibilityLabel(interface.isPlaying || interface.buffering ? "Pause" : "Play")
            Button {
                player.next()
            } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 24)).frame(width: 56, height: 56)
            }.accessibilityLabel("Next track")
        }.buttonStyle(.plain).foregroundStyle(.white).frame(maxWidth: .infinity)
    }

    private var bottomControls: some View {
        HStack(spacing: 24) {
            Button {
                presentedSheet = .lyrics
            } label: {
                Text("LYRICS")
                    .font(.caption.weight(.semibold)).tracking(2.4)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel("Lyrics").accessibilityHint("Open lyrics")
            Button {
                player.cycleRepeat()
            } label: {
                Image(systemName: interface.queue.repeatMode == .one ? "repeat.1" : "repeat").font(.title3)
                    .foregroundStyle(interface.queue.repeatMode == .off ? .white.opacity(0.7) : theme.accent)
                    .frame(width: 44, height: 44)
            }.accessibilityLabel("Repeat").accessibilityValue(interface.queue.repeatMode.rawValue)
            Button {
                presentedSheet = .queue
            } label: {
                Text("QUEUE")
                    .font(.caption.weight(.semibold)).tracking(2.4)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel("Queue").accessibilityHint("Open play queue")
        }.buttonStyle(.plain).frame(maxWidth: 300)
    }

    private func close() {
        artistTask?.cancel()
        onClose(0)
    }

    private func album(for song: Song) -> Album? {
        if let album = store.albums.first(where: { $0.id == song.albumId }) { return album }
        if let id = song.albumId, let namespace = store.downloadNamespace,
            let album = store.downloads.savedAlbum(id, namespace: namespace)
        {
            return album
        }
        return Album(song: song)
    }

    private func openArtist(_ song: Song) async {
        guard !openingArtist else { return }
        openingArtist = true
        defer { openingArtist = false }
        let session = store.sessionID
        let album = album(for: song)
        let known = store.artists.first { $0.name.localizedCaseInsensitiveCompare(song.artistName) == .orderedSame }
        var id = song.albumArtists?.compactMap(\.id).first ?? album?.artistId ?? known?.id
        var lookupError: String?
        if id == nil, let albumID = song.albumId, let api = store.api {
            do { id = try await api.album(albumID).artistId } catch { lookupError = friendlyError(error) }
        }
        if id == nil, song.artistName == song.artist { id = song.artistId }
        guard !Task.isCancelled, store.sessionID == session, interface.current?.id == song.id,
            interface.expanded, !motion.isDismissing, presentedSheet == nil
        else { return }
        guard let id, !id.isEmpty else {
            artistError = lookupError ?? "This song has no linked artist on your server."
            return
        }
        let artist = store.artists.first { $0.id == id } ?? Artist(id: id, name: song.artistName)
        presentedSheet = .artist(artist)
    }
}
