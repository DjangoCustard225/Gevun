import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let original = task.originalRequest?.url, let target = request.url,
            Self.sameOrigin(original, target)
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    public static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.scheme?.lowercased() == b.scheme?.lowercased() && a.host?.lowercased() == b.host?.lowercased()
            && (a.port ?? (a.scheme == "https" ? 443 : 80)) == (b.port ?? (b.scheme == "https" ? 443 : 80))
    }
}

public final class NavidromeAPI: @unchecked Sendable {
    public let instance: Instance
    private let queueSupport = QueueSupport()
    private actor QueueSupport {
        private var supported: Bool?
        func usesIndex(_ api: NavidromeAPI) async -> Bool {
            if let supported { return supported }
            do {
                let response = try await api.request("getOpenSubsonicExtensions")
                let value =
                    response.openSubsonicExtensions?.contains {
                        $0.name == "indexBasedQueue" && $0.versions.contains(1)
                    } ?? false
                supported = value
                return value
            } catch { return false }
        }
    }
    private let session: URLSession
    public init(instance: Instance, session: URLSession? = nil) {
        self.instance = instance
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false
            config.urlCache = nil
            config.timeoutIntervalForRequest = 25
            config.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: config, delegate: SameOriginRedirects(), delegateQueue: nil)
        }
    }
    deinit { session.invalidateAndCancel() }

    public func url(_ endpoint: String, parameters: [URLQueryItem] = [], salt: String = UUID().uuidString) throws -> URL
    {
        let base = instance.url.appendingPathComponent("rest").appendingPathComponent(endpoint + ".view")
        guard var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw GevunError.invalidAddress
        }
        parts.queryItems =
            [
                .init(name: "u", value: instance.username),
                .init(name: "t", value: SubsonicToken.hash(password: instance.password, salt: salt)),
                .init(name: "s", value: salt), .init(name: "v", value: "1.16.1"),
                .init(name: "c", value: "Gevun"), .init(name: "f", value: "json"),
            ] + parameters
        // A literal + must not become a space in form-style query parsers.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let result = parts.url else { throw GevunError.invalidAddress }
        return result
    }

    private func request(
        _ endpoint: String, _ parameters: [URLQueryItem] = [],
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy, post: Bool = false
    ) async throws -> Response {
        var request = URLRequest(
            url: try url(endpoint, parameters: post ? [] : parameters),
            cachePolicy: post ? .reloadIgnoringLocalCacheData : cachePolicy)
        if post {
            request.httpMethod = "POST"
            var form = URLComponents()
            form.queryItems = parameters
            request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw GevunError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw GevunError.http(http.statusCode) }
        let decoded: Envelope
        do { decoded = try JSONDecoder().decode(Envelope.self, from: data) } catch { throw GevunError.invalidResponse }
        guard decoded.response.status == "ok" else {
            switch decoded.response.error?.code ?? 0 {
            case 40, 41, 42, 43, 44: throw GevunError.authentication
            case 50: throw GevunError.forbidden
            case 70: throw GevunError.notFound
            case let code: throw GevunError.server(code)
            }
        }
        return decoded.response
    }

    public func ping() async throws -> String {
        let response = try await request("ping")
        return [response.type ?? "Navidrome", response.serverVersion].compactMap { $0 }.joined(separator: " ")
    }

    /// Requests `endpoint` and returns the payload at `key`, failing when the server leaves it out.
    private func payload<Value>(
        _ endpoint: String, _ parameters: [URLQueryItem] = [], fresh: Bool = false,
        at key: KeyPath<Response, Value?>
    ) async throws -> Value {
        let response = try await request(
            endpoint, parameters, cachePolicy: fresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy)
        guard let value = response[keyPath: key] else { throw GevunError.invalidResponse }
        return value
    }

    public func albums(
        type: String = "alphabeticalByName", genre: String? = nil, offset: Int = 0, size: Int = 60
    ) async throws -> [Album] {
        var parameters = [item("type", type), item("offset", offset), item("size", size)]
        if let genre { parameters.append(item("genre", genre)) }
        return try await payload("getAlbumList2", parameters, at: \.albumList2).album ?? []
    }

    public func genres() async throws -> [Genre] {
        let list: GenreList = try await payload("getGenres", fresh: true, at: \.genres)
        return (list.genre ?? []).filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// An artist's most popular songs. Navidrome needs an external agent such as Last.fm to rank them.
    public func topSongs(artist name: String, count: Int = 10) async throws -> [Song] {
        let list: SongList = try await payload(
            "getTopSongs", [item("artist", name), item("count", count)], at: \.topSongs)
        return list.song ?? []
    }

    /// Everything the user has favourited.
    public func favorites() async throws -> Favorites {
        try await payload("getStarred2", fresh: true, at: \.starred2)
    }

    /// Favourites (`star`) or unfavourites (`unstar`) a song, album or artist.
    public func setFavorite(_ favorite: Bool, id: String, kind: FavoriteKind) async throws {
        let name =
            switch kind {
            case .song: "id"
            case .album: "albumId"
            case .artist: "artistId"
            }
        _ = try await request(favorite ? "star" : "unstar", [item(name, id)])
    }

    public func album(_ id: String) async throws -> Album {
        try await payload("getAlbum", [item("id", id)], at: \.album)
    }

    public func artists() async throws -> [Artist] {
        let list: ArtistList = try await payload("getArtists", at: \.artists)
        return (list.index ?? []).flatMap { $0.artist ?? [] }
    }

    public func artist(_ id: String) async throws -> Artist {
        try await payload("getArtist", [item("id", id)], fresh: true, at: \.artist)
    }

    public func artistInfo(_ id: String) async throws -> ArtistInfo {
        try await payload(
            "getArtistInfo2", [item("id", id), item("count", 12), item("includeNotPresent", "false")],
            fresh: true, at: \.artistInfo2)
    }

    public func savedQueue() async throws -> SavedPlayQueue? {
        if await queueSupport.usesIndex(self) {
            return try await request("getPlayQueueByIndex").playQueueByIndex
        }
        return try await request("getPlayQueue").playQueue
    }

    public func saveQueue(songs: [Song], index: Int, position: Double) async throws {
        guard songs.indices.contains(index), position.isFinite else { return }
        let indexed = await queueSupport.usesIndex(self)
        _ = try await request(
            indexed ? "savePlayQueueByIndex" : "savePlayQueue",
            songs.map { item("id", $0.id) } + [
                (indexed ? item("currentIndex", index) : item("current", songs[index].id)),
                item("position", Int64(min(max(0, position), Double(Int64.max / 1000)) * 1000)),
                item("changedBy", "Gevun"),
            ], post: true)
    }

    public func share(_ ids: [String]) async throws -> URL {
        let response = try await request("createShare", ids.map { item("id", $0) }, post: true)
        guard let value = response.shares?.share?.first?.url, let url = URL(string: value),
            ["https", "http"].contains(url.scheme?.lowercased() ?? "")
        else { throw GevunError.invalidResponse }
        return url
    }

    public func search(_ query: String, albumOffset: Int = 0, artistOffset: Int = 0, songOffset: Int = 0) async throws
        -> SearchResults
    {
        try await payload(
            "search3",
            [
                item("query", query), item("albumCount", 30), item("artistCount", 30),
                item("songCount", 30), item("albumOffset", albumOffset), item("artistOffset", artistOffset),
                item("songOffset", songOffset),
            ], at: \.searchResult3)
    }

    public func songs(offset: Int = 0, size: Int = 100) async throws -> [Song] {
        try await payload(
            "search3",
            [
                item("query", ""), item("albumCount", 0), item("artistCount", 0),
                item("songCount", size), item("songOffset", offset),
            ], at: \.searchResult3
        ).songs
    }

    public func playlists() async throws -> [Playlist] {
        try await payload("getPlaylists", fresh: true, at: \.playlists).playlist ?? []
    }

    public func playlist(_ id: String) async throws -> Playlist {
        try await payload("getPlaylist", [item("id", id)], fresh: true, at: \.playlist)
    }

    /// Creates a playlist with `songIDs` in order. Older servers may not return the new playlist.
    @discardableResult
    public func createPlaylist(name: String, songIDs: [String]) async throws -> Playlist? {
        try await request(
            "createPlaylist", [item("name", Playlist.cleanName(name))] + songIDs.map { item("songId", $0) }, post: true
        ).playlist
    }

    /// Replaces a playlist's songs with `songIDs`, used for reordering.
    public func replacePlaylistSongs(_ id: String, songIDs: [String]) async throws {
        _ = try await request(
            "createPlaylist", [item("playlistId", id)] + songIDs.map { item("songId", $0) }, post: true)
    }

    /// Renames, appends songs, or removes entries by their position in the playlist.
    public func updatePlaylist(
        _ id: String, name: String? = nil, adding songIDs: [String] = [], removingIndexes indexes: [Int] = []
    ) async throws {
        var parameters = [item("playlistId", id)]
        if let name { parameters.append(item("name", Playlist.cleanName(name))) }
        parameters += songIDs.map { item("songIdToAdd", $0) }
        parameters += indexes.map { item("songIndexToRemove", $0) }
        _ = try await request("updatePlaylist", parameters, post: true)
    }

    public func deletePlaylist(_ id: String) async throws {
        _ = try await request("deletePlaylist", [item("id", id)], post: true)
    }

    public func lyrics(for song: Song) async throws -> [StructuredLyrics] {
        do {
            let list: LyricsList = try await payload("getLyricsBySongId", [item("id", song.id)], at: \.lyricsList)
            return (list.structuredLyrics ?? []).filter(\.hasContent)
        } catch let error as GevunError {
            // Use the legacy endpoint only when the server cannot handle song-ID lyrics.
            switch error {
            case .server(0), .server(10), .http(404), .http(501): break
            default: throw error
            }
        }
        try Task.checkCancellation()
        let response = try await request(
            "getLyrics",
            [item("artist", ArtistCredit.nonempty(song.artist) ?? song.artistName), item("title", song.title)])
        guard let lyrics = response.lyrics else { throw GevunError.invalidResponse }
        guard let text = lyrics.value, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n").map { LyricLine(value: $0) }
        return [StructuredLyrics(displayArtist: lyrics.artist, displayTitle: lyrics.title, line: lines)]
    }

    public func scrobble(_ id: String) async throws {
        _ = try await request(
            "scrobble",
            [item("id", id), item("submission", "true"), item("time", Int(Date().timeIntervalSince1970 * 1000))])
    }

    public func streamURL(_ id: String, quality: DownloadQuality = DownloadQuality()) throws -> URL {
        guard quality.format != .original else {
            return try url("stream", parameters: [item("id", id), item("format", "raw"), item("maxBitRate", 0)])
        }
        // A size estimate lets the player show the length and seek within a converted stream.
        return try url(
            "stream",
            parameters: [
                item("id", id), item("format", quality.format.rawValue), item("maxBitRate", quality.bitrate),
                item("estimateContentLength", "true"),
            ])
    }

    public func downloadURL(_ id: String, quality: DownloadQuality) throws -> URL {
        // Navidrome's download extension uses `bitrate`, unlike stream's `maxBitRate`.
        try url(
            "download",
            parameters: [
                item("id", id), item("format", quality.format == .original ? "raw" : quality.format.rawValue),
                item("bitrate", quality.bitrate),
            ])
    }

    public func artwork(_ id: String, size: Int = 600) async throws -> Data {
        let (data, response) = try await session.data(
            from: url("getCoverArt", parameters: [item("id", id), item("size", size)]))
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
            http.mimeType?.hasPrefix("image/") == true,
            data.count <= 15_000_000
        else { throw GevunError.invalidResponse }
        return data
    }

    private func item(_ name: String, _ value: some CustomStringConvertible) -> URLQueryItem {
        .init(name: name, value: value.description)
    }
}

private struct Envelope: Decodable {
    let response: Response
    enum CodingKeys: String, CodingKey { case response = "subsonic-response" }
}
private struct Response: Decodable {
    let status: String
    let type: String?
    let serverVersion: String?
    let error: APIError?
    let albumList2: AlbumList?
    let album: Album?
    let artists: ArtistList?
    let artist: Artist?
    let artistInfo2: ArtistInfo?
    let lyricsList: LyricsList?
    let lyrics: LegacyLyrics?
    let searchResult3: SearchResults?
    let playQueue: SavedPlayQueue?
    let playQueueByIndex: SavedPlayQueue?
    let openSubsonicExtensions: [QueueExtension]?
    let shares: Shares?
    let playlists: PlaylistList?
    let playlist: Playlist?
    let genres: GenreList?
    let topSongs: SongList?
    let starred2: Favorites?
}
private struct APIError: Decodable { let code: Int }
private struct AlbumList: Decodable { let album: [Album]? }
private struct ArtistList: Decodable { let index: [ArtistIndex]? }
private struct ArtistIndex: Decodable { let artist: [Artist]? }
private struct LyricsList: Decodable { let structuredLyrics: [StructuredLyrics]? }
private struct LegacyLyrics: Decodable {
    let artist: String?
    let title: String?
    let value: String?
}

private struct GenreList: Decodable { let genre: [Genre]? }
private struct SongList: Decodable { let song: [Song]? }
private struct PlaylistList: Decodable { let playlist: [Playlist]? }
private struct Shares: Decodable { let share: [ServerShare]? }
private struct ServerShare: Decodable { let url: String }

private struct QueueExtension: Decodable { let name: String; let versions: [Int] }
