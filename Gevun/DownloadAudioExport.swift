import Foundation
import UIKit
import GevunCore

struct DownloadExportSource: Sendable {
    let copy: OfflineSong
    let url: URL
    let album: Album?
    let artworkURL: URL?
    let lyricsURL: URL
    let instance: Instance?
}

enum DownloadAudioExport {
    static func prepare(_ source: DownloadExportSource, filename: String) async throws -> URL {
        try Task.checkCancellation()
        guard try source.url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let isFLAC = source.copy.quality.format == .original && source.url.pathExtension.lowercased() == "flac"
        guard isFLAC || [.aac, .mp3].contains(source.copy.quality.format) else { return source.url }
        let directory = try makeTemporaryDirectory()
        let destination = directory.appendingPathComponent(filename)
        do {
            let metadata = await loadMetadata(for: source)
            try Task.checkCancellation()
            if isFLAC {
                try await TaggedFLACExport.write(from: source.url, to: destination, metadata: metadata)
            } else if source.copy.quality.format == .mp3 {
                try await TaggedMP3Export.write(from: source.url, to: destination, metadata: metadata)
            } else {
                try await TaggedAACExport.write(from: source.url, to: destination, metadata: metadata)
            }
            return destination
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func loadMetadata(for source: DownloadExportSource) async -> DownloadExportMetadata {
        let api = source.instance.map(makeAPI)
        let album: Album?
        if let cached = source.album {
            album = cached
        } else if let id = source.copy.song.albumId, let api {
            album = try? await api.album(id)
        } else {
            album = nil
        }
        async let lyrics = lyrics(for: source, api: api)
        async let artwork = artwork(for: source, album: album, api: api)
        return await DownloadExportMetadata(song: source.copy.song, album: album, lyrics: lyrics, artwork: artwork)
    }

    private static func makeAPI(for instance: Instance) -> NavidromeAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: SameOriginRedirects(), delegateQueue: nil)
        return NavidromeAPI(instance: instance, session: session)
    }

    private static func lyrics(for source: DownloadExportSource, api: NavidromeAPI?) async -> [StructuredLyrics] {
        if let data = try? Data(contentsOf: source.lyricsURL),
            let cached = try? JSONDecoder().decode([StructuredLyrics].self, from: data),
            cached.contains(where: \.hasContent)
        {
            return cached
        }
        guard !Task.isCancelled, let api else { return [] }
        return (try? await api.lyrics(for: source.copy.song)) ?? []
    }

    private static func artwork(for source: DownloadExportSource, album: Album?, api: NavidromeAPI?) async -> Data? {
        var data = source.artworkURL.flatMap { try? Data(contentsOf: $0) }
        if data == nil, !Task.isCancelled, let id = source.copy.song.coverArt ?? album?.coverArt, let api {
            data = try? await api.artwork(id, size: 1200)
        }
        guard let data, let image = UIImage(data: data) else { return nil }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) || data.starts(with: [0xFF, 0xD8, 0xFF]) { return data }
        return image.jpegData(compressionQuality: 0.95)
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GevunExports", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        pruneExpiredFiles(in: root)
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return directory
    }

    private static func pruneExpiredFiles(in root: URL) {
        let expiry = Date().addingTimeInterval(-24 * 3600)
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for file in files {
            if let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate, created < expiry {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
