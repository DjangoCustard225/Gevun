import SwiftUI
import Observation
import GevunCore

enum PlayerDestination {
    case album(Album)
    case artist(Artist)
}

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
    private(set) var playlists: [Playlist] = []
    private(set) var libraryLoading: Set<LibraryCategory> = []
    private(set) var libraryErrors: [LibraryCategory: String] = [:]
    private(set) var libraryLoaded: Set<LibraryCategory> = []
    private(set) var moreAlbums = true
    private(set) var moreSongs = true
    var albumOrder: AlbumOrder = .alphabeticalByName
    var notice: String?
    var showConnection = false
    var serverVersion = ""
    var downloadSelection: DownloadSelection?
    var playerDestination: PlayerDestination?
    let player: PlayerStore
    let artwork: ArtworkCache
    let downloads: DownloadStore
    let appearance = ArtworkAppearance()
    @ObservationIgnored private var libraryRevisions: [LibraryCategory: UUID] = [:]
    @ObservationIgnored private var albumOffset = 0
    @ObservationIgnored private var songOffset = 0
    @ObservationIgnored private var loadedAlbumOrder: AlbumOrder?

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
        instances = saved
        downloads.configure(instances: saved)
        if activeID == id {
            if let first = saved.first {
                activate(first.id)
            } else {
                player.stop()
                api = nil
                activeID = nil
                downloadNamespace = nil
                UserDefaults.standard.removeObject(forKey: "activeInstance")
                clearLibrary()
            }
        }
    }

    private func clearLibrary() {
        sessionID = UUID()
        libraryRevisions = [:]
        albums = []
        artists = []
        songs = []
        playlists = []
        libraryErrors = [:]
        libraryLoading = []
        libraryLoaded = []
        albumOffset = 0
        songOffset = 0
        moreAlbums = true
        moreSongs = true
        loadedAlbumOrder = nil
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
                var existingIDs = Set(more ? albums.map(\.id) : [])
                let additions = page.filter { existingIDs.insert($0.id).inserted }
                albums = more ? albums + additions : additions
                albumOffset = offset + page.count
                moreAlbums = page.count == 60 && (!more || !additions.isEmpty)
                loadedAlbumOrder = order
            case .artists:
                let values = try await api.artists()
                guard libraryRevisions[category] == revision, self.api === api, !Task.isCancelled else { return }
                artists = values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            case .songs:
                let offset = more ? songOffset : 0
                let page = try await api.songs(offset: offset)
                guard libraryRevisions[category] == revision, self.api === api, !Task.isCancelled else { return }
                var existingIDs = Set(more ? songs.map(\.id) : [])
                let additions = page.filter { existingIDs.insert($0.id).inserted }
                songs = more ? songs + additions : additions
                songOffset = offset + page.count
                moreSongs = page.count == 100 && (!more || !additions.isEmpty)
            case .playlists:
                let values = try await api.playlists()
                guard libraryRevisions[category] == revision, self.api === api, !Task.isCancelled else { return }
                playlists = values
            }
            libraryLoaded.insert(category)
        } catch {
            if libraryRevisions[category] == revision, self.api === api, !Task.isCancelled {
                libraryErrors[category] = friendlyError(error)
            }
        }
    }

    func playAlbum(_ album: Album, shuffle: Bool = false) async {
        guard let api else { return }
        let session = sessionID
        do {
            let tracks: [Song]
            if !downloads.connected {
                tracks = downloads.savedSongs(albumID: album.id, namespace: DownloadKey.namespace(for: api.instance))
            } else {
                tracks = try await api.album(album.id).songs
            }
            guard sessionID == session, !Task.isCancelled else { return }
            guard !tracks.isEmpty else {
                notice = "This album has no available tracks."
                return
            }
            player.play(tracks, at: shuffle ? Int.random(in: 0..<tracks.count) : 0, shuffle: shuffle)
        } catch {
            if sessionID == session, !Task.isCancelled {
                let saved = downloads.savedSongs(albumID: album.id, namespace: DownloadKey.namespace(for: api.instance))
                if saved.isEmpty {
                    notice = friendlyError(error)
                } else {
                    player.play(saved, at: shuffle ? Int.random(in: 0..<saved.count) : 0, shuffle: shuffle)
                }
            }
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
}

enum LibraryCategory: String, CaseIterable, Identifiable, Hashable {
    case albums, artists, songs, playlists
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

func friendlyError(_ error: Error) -> String {
    if let error = error as? URLError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "You're offline. Connect to your network and try again."
        case .timedOut: return "The server took too long to respond. Try again."
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return "Couldn't reach your server. Check its address, network, and VPN."
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .secureConnectionFailed:
            return "The server's secure connection could not be verified. Check its HTTPS certificate."
        default: return "The connection failed. Check your server and try again."
        }
    }
    return error.localizedDescription
}
