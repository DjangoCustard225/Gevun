import SwiftUI
import Observation
import GevunCore

@MainActor
@Observable
final class AppStore {
    private(set) var instances: [Instance] = []
    private(set) var activeID: UUID?
    private(set) var downloadNamespace: String?
    private(set) var api: NavidromeAPI?
    private(set) var sessionID = UUID()
    private(set) var albums: [Album] = []
    private(set) var artists: [Artist] = []
    private(set) var songs: [Song] = []
    /// The newest albums, for the shelf at the top of the library.
    private(set) var recentAlbums: [Album] = []
    private(set) var libraryLoading: Set<LibraryCategory> = []
    private(set) var libraryErrors: [LibraryCategory: String] = [:]
    private(set) var libraryLoaded: Set<LibraryCategory> = []
    private(set) var moreAlbums = true
    private(set) var moreSongs = true
    private(set) var playlists: [Playlist] = []
    private(set) var playlistsLoading = false
    private(set) var playlistsError: String?
    private(set) var playlistsLoaded = false
    /// Changes after any playlist edit so open playlist pages reload their songs.
    private(set) var playlistRevision = UUID()
    /// Songs waiting for the "New Playlist" name prompt.
    var newPlaylistRequest: [Song]?
    var albumOrder: AlbumOrder = .alphabeticalByName
    var notice: String?
    var showConnection = false
    var serverVersion = ""
    var downloadSelection: DownloadSelection?
    let player: PlayerStore
    let artwork: ArtworkCache
    let downloads: DownloadStore
    let appearance = ArtworkAppearance()
    @ObservationIgnored private var libraryRevisions: [LibraryCategory: UUID] = [:]
    @ObservationIgnored private var albumOffset = 0
    @ObservationIgnored private var songOffset = 0
    @ObservationIgnored private var loadedAlbumOrder: AlbumOrder?
    @ObservationIgnored private var playlistsToken = UUID()
    @ObservationIgnored private var recentAlbumsKey: String?

    init() {
        let downloads = DownloadStore()
        let artwork = ArtworkCache()
        self.downloads = downloads
        artwork.downloads = downloads
        self.artwork = artwork
        self.player = PlayerStore(artwork: artwork, downloads: downloads)
        UserDefaults.standard.removeObject(forKey: "streamBitRate")
        do {
            instances = try Credentials.read()
            let selected = UserDefaults.standard.string(forKey: "activeInstance").flatMap(UUID.init(uuidString:))
            let instance = instances.first { $0.id == selected } ?? instances.first
            activeID = instance?.id
            if let instance {
                downloadNamespace = DownloadKey.namespace(for: instance)
                api = NavidromeAPI(instance: instance)
                player.configure(api: api)
            }
        } catch { notice = error.localizedDescription }
        downloads.configure(instances: instances)
        DownloadAppDelegate.attach(downloads)
    }

    func connect(_ instance: Instance) async throws {
        let candidate = NavidromeAPI(instance: instance)
        let version = try await candidate.ping()
        try Task.checkCancellation()
        var saved = instances
        if let index = saved.firstIndex(where: { $0.id == instance.id }) {
            saved[index] = instance
        } else {
            saved.append(instance)
        }
        try Credentials.save(saved)
        instances = saved
        downloads.configure(instances: saved)
        activate(instance.id)
        serverVersion = version
    }

    func activate(_ id: UUID) {
        guard let instance = instances.first(where: { $0.id == id }) else { return }
        player.listening.checkpoint(urgent: true)
        player.stop()
        activeID = id
        downloadNamespace = DownloadKey.namespace(for: instance)
        api = NavidromeAPI(instance: instance)
        UserDefaults.standard.set(id.uuidString, forKey: "activeInstance")
        player.configure(api: api)
        clearLibrary()
    }

    func remove(_ id: UUID) throws {
        let saved = instances.filter { $0.id != id }
        try Credentials.save(saved)
        let removed = instances.first(where: { $0.id == id })
        instances = saved
        downloads.configure(instances: saved)
        if activeID == id {
            if let first = saved.first {
                activate(first.id)
            } else {
                player.stop()
                player.configure(api: nil)
                api = nil
                activeID = nil
                downloadNamespace = nil
                UserDefaults.standard.removeObject(forKey: "activeInstance")
                clearLibrary()
            }
        }
        if let removed { player.listening.remove(instance: removed) }
    }

    private func clearLibrary() {
        sessionID = UUID()
        libraryRevisions = [:]
        albums = []
        artists = []
        songs = []
        recentAlbums = []
        libraryErrors = [:]
        libraryLoading = []
        libraryLoaded = []
        albumOffset = 0
        songOffset = 0
        moreAlbums = true
        moreSongs = true
        loadedAlbumOrder = nil
        playlists = []
        playlistsLoading = false
        playlistsError = nil
        playlistsLoaded = false
        playlistsToken = UUID()
        playlistRevision = UUID()
        newPlaylistRequest = nil
        serverVersion = ""
        artwork.clear()
    }

    func ensureLibrary(_ category: LibraryCategory) async {
        if libraryLoaded.contains(category), category != .albums || loadedAlbumOrder == albumOrder { return }
        await loadLibrary(category)
    }

    func loadLibrary(_ category: LibraryCategory, more: Bool = false) async {
        guard let api else { return }
        if more && libraryLoading.contains(category) { return }
        if more && category == .albums && loadedAlbumOrder != albumOrder {
            await loadLibrary(.albums)
            return
        }
        let revision = UUID()
        libraryRevisions[category] = revision
        libraryLoading.insert(category)
        libraryErrors[category] = nil
        let order = albumOrder
        defer {
            if libraryRevisions[category] == revision { libraryLoading.remove(category) }
        }
        do {
            switch category {
            case .albums:
                let offset = more ? albumOffset : 0
                let page = try await api.albums(type: order.rawValue, offset: offset)
                guard libraryRevisions[category] == revision, self.api === api, !Task.isCancelled else { return }
                let merged = ((more ? albums : []) + page).uniqued()
                // A full page that adds nothing new means the server has no more to give.
                moreAlbums = page.count == 60 && (!more || merged.count > albums.count)
                albums = merged
                albumOffset = offset + page.count
                loadedAlbumOrder = order
            case .artists:
                let values = try await api.artists()
                guard libraryRevisions[category] == revision, self.api === api, !Task.isCancelled else { return }
                artists = values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            case .songs:
                let offset = more ? songOffset : 0
                let page = try await api.songs(offset: offset)
                guard libraryRevisions[category] == revision, self.api === api, !Task.isCancelled else { return }
                let merged = ((more ? songs : []) + page).uniqued()
                moreSongs = page.count == 100 && (!more || merged.count > songs.count)
                songs = merged
                songOffset = offset + page.count
            }
            libraryLoaded.insert(category)
        } catch {
            if libraryRevisions[category] == revision, self.api === api, !Task.isCancelled {
                libraryErrors[category] = friendlyError(error)
            }
        }
    }

    /// Refreshes the "Recently added" shelf. It stays as it was when the server can't be reached.
    /// Fetches once per server session (and again after reconnecting) unless `force` is set.
    func loadRecentAlbums(force: Bool = false) async {
        guard let api, downloads.connected else { return }
        let key = "\(sessionID)"
        if !force && recentAlbumsKey == key { return }
        guard let page = try? await api.albums(type: AlbumOrder.newest.rawValue, size: 40),
            self.api === api, !Task.isCancelled
        else { return }
        recentAlbums = page
        recentAlbumsKey = key
    }

    func playAlbum(_ album: Album, shuffle: Bool = false) async {
        guard let api else { return }
        let session = sessionID
        let saved = downloads.savedSongs(albumID: album.id, namespace: DownloadKey.namespace(for: api.instance))
        var tracks = saved
        var failure: String?
        if downloads.connected {
            // Downloaded songs stand in when the server can't be reached.
            do { tracks = try await api.album(album.id).songs } catch { failure = friendlyError(error) }
            guard sessionID == session, !Task.isCancelled else { return }
        }
        if failure != nil, saved.isEmpty {
            notice = failure
        } else if tracks.isEmpty {
            notice = "This album has no available tracks."
        } else {
            player.start(tracks, shuffle: shuffle)
        }
    }

    func downloadAlbum(_ album: Album) async {
        guard let api else { return }
        do {
            let detail = try await api.album(album.id)
            guard self.api === api, !Task.isCancelled else { return }
            downloadSelection = DownloadSelection(songs: detail.songs, album: detail, instance: api.instance)
        } catch { if self.api === api { notice = friendlyError(error) } }
    }

    // MARK: Playlists

    /// Playlists the signed-in user can add songs to, most recently changed first.
    var editablePlaylists: [Playlist] { playlists.filter(canEdit) }

    func canEdit(_ playlist: Playlist) -> Bool {
        api.map { playlist.isEditable(by: $0.instance.username) } ?? false
    }

    func ensurePlaylists() async {
        if !playlistsLoaded { await loadPlaylists() }
    }

    func loadPlaylists() async {
        guard let api else { return }
        let token = UUID()
        playlistsToken = token
        playlistsLoading = true
        playlistsError = nil
        defer { if playlistsToken == token { playlistsLoading = false } }
        do {
            let values = try await api.playlists()
            guard playlistsToken == token, self.api === api, !Task.isCancelled else { return }
            playlists = values.sorted { ($0.changedDate ?? .distantPast) > ($1.changedDate ?? .distantPast) }
            playlistsLoaded = true
        } catch {
            guard playlistsToken == token, self.api === api, !Task.isCancelled else { return }
            playlistsError = friendlyError(error)
        }
    }

    func createPlaylist(name: String, songs: [Song] = []) async {
        await changePlaylists { try await $0.createPlaylist(name: name, songIDs: songs.map(\.id)) }
    }

    func addToPlaylist(_ songs: [Song], _ playlist: Playlist) async {
        guard !songs.isEmpty else { return }
        await changePlaylists { try await $0.updatePlaylist(playlist.id, adding: songs.map(\.id)) }
    }

    func renamePlaylist(_ playlist: Playlist, to name: String) async {
        await changePlaylists { try await $0.updatePlaylist(playlist.id, name: name) }
    }

    /// Removes entries by position, so a song added twice loses only the chosen copy.
    func removeFromPlaylist(_ playlist: Playlist, at positions: [Int]) async {
        guard !positions.isEmpty else { return }
        await changePlaylists { try await $0.updatePlaylist(playlist.id, removingIndexes: positions) }
    }

    /// Saves a reordered or trimmed song list in one request.
    func replacePlaylistSongs(_ playlist: Playlist, songs: [Song]) async {
        await changePlaylists { try await $0.replacePlaylistSongs(playlist.id, songIDs: songs.map(\.id)) }
    }

    @discardableResult
    func deletePlaylist(_ playlist: Playlist) async -> Bool {
        await changePlaylists { try await $0.deletePlaylist(playlist.id) }
    }

    func playPlaylist(_ playlist: Playlist, shuffle: Bool = false) async {
        guard let api else { return }
        let session = sessionID
        do {
            let tracks = try await api.playlist(playlist.id).songs
            guard sessionID == session, !Task.isCancelled else { return }
            guard !tracks.isEmpty else {
                notice = "This playlist has no songs."
                return
            }
            player.start(tracks, shuffle: shuffle)
        } catch {
            if sessionID == session, !Task.isCancelled { notice = friendlyError(error) }
        }
    }

    /// Runs a playlist change on the server, then refreshes the list and any open playlist page.
    @discardableResult
    private func changePlaylists(_ change: (NavidromeAPI) async throws -> Void) async -> Bool {
        guard let api else { return false }
        guard downloads.connected else {
            notice = "Connect to your server to change playlists."
            return false
        }
        do {
            try await change(api)
            guard self.api === api else { return false }
            playlistRevision = UUID()
            await loadPlaylists()
            return true
        } catch {
            if self.api === api { notice = friendlyError(error) }
            return false
        }
    }
}
