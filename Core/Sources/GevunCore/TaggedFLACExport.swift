import Foundation

/// Supplement missing FLAC tags while retaining existing metadata blocks and compressed audio.
public enum TaggedFLACExport {
    public static func write(from source: URL, to destination: URL, metadata: DownloadExportMetadata) async throws {
        try Task.checkCancellation()
        guard source.standardizedFileURL != destination.standardizedFileURL else { throw Failure.sameFile }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard try input.read(upToCount: 4) == Data("fLaC".utf8) else { throw Failure.invalidFile }
        var blocks: [Block] = []
        var total = 0
        while true {
            try Task.checkCancellation()
            let header = [UInt8](try input.read(upToCount: 4) ?? Data())
            guard header.count == 4, header[0] & 0x7F != 127 else { throw Failure.invalidFile }
            let type = header[0] & 0x7F
            let size = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            total += size + 4
            guard total <= 64 * 1024 * 1024, blocks.count < 4096 else { throw Failure.tooLarge }
            guard !blocks.isEmpty || (type == 0 && size == 34), blocks.isEmpty || type != 0 else {
                throw Failure.invalidFile
            }
            let data = try input.read(upToCount: size) ?? Data()
            guard data.count == size else { throw Failure.invalidFile }
            blocks.append(Block(type: type, data: data))
            if header[0] & 0x80 != 0 { break }
        }
        let commentIndices = blocks.indices.filter { blocks[$0].type == 4 }
        guard commentIndices.count <= 1 else { throw Failure.invalidFile }
        let commentIndex = commentIndices.first
        var comments = try commentIndex.map { try Comments(data: blocks[$0].data) } ?? Comments()
        comments.add("TITLE", metadata.title)
        comments.add("ARTIST", metadata.artist)
        comments.add("ALBUMARTIST", metadata.albumArtist, aliases: ["ALBUM ARTIST", "ALBUM_ARTIST"])
        comments.add("ALBUM", metadata.album)
        comments.add("DATE", metadata.year.map(String.init), aliases: ["YEAR"])
        comments.add("GENRE", metadata.genre)
        if let track = metadata.track, track > 0 { comments.add("TRACKNUMBER", String(track)) }
        if let total = metadata.trackCount, total > 0 {
            comments.add("TRACKTOTAL", String(total), aliases: ["TOTALTRACKS"])
        }
        if let disc = metadata.disc, disc > 0 { comments.add("DISCNUMBER", String(disc)) }
        comments.add("LYRICS", metadata.lrcLyrics ?? metadata.lyrics)
        comments.add("UNSYNCEDLYRICS", metadata.lyrics)
        let commentBlock = Block(type: 4, data: try comments.encoded())
        if let commentIndex { blocks[commentIndex] = commentBlock } else { blocks.append(commentBlock) }
        if !blocks.contains(where: { $0.type == 6 }), let artwork = metadata.artwork {
            blocks.append(Block(type: 6, data: picture(artwork)))
        }
        var header = Data("fLaC".utf8)
        for (index, block) in blocks.enumerated() {
            guard block.data.count <= 0xFF_FFFF else { throw Failure.tooLarge }
            header.append(block.type | (index == blocks.count - 1 ? 0x80 : 0))
            header.append(contentsOf: [
                UInt8(block.data.count >> 16), UInt8(block.data.count >> 8 & 255), UInt8(block.data.count & 255),
            ])
            header.append(block.data)
        }
        try await AudioExportFile.write(to: destination, header: header, copying: input)
    }

    private struct Block {
        let type: UInt8
        let data: Data
    }

    private struct Comments {
        private var vendor = Data("Gevun".utf8)
        private var entries: [Data] = []
        private var keys = Set<String>()

        init() {}

        init(data: Data) throws {
            let bytes = [UInt8](data)
            var offset = 0
            func count() throws -> Int {
                guard bytes.count - offset >= 4 else { throw Failure.invalidFile }
                defer { offset += 4 }
                return (0..<4).reduce(0) { $0 | Int(bytes[offset + $1]) << ($1 * 8) }
            }
            func entry() throws -> Data {
                let size = try count()
                guard size <= bytes.count - offset else { throw Failure.invalidFile }
                defer { offset += size }
                return Data(bytes[offset..<offset + size])
            }
            vendor = try entry()
            let size = try count()
            guard size <= 65_536 else { throw Failure.tooLarge }
            guard size <= (bytes.count - offset) / 4 else { throw Failure.invalidFile }
            for _ in 0..<size {
                let value = try entry()
                guard let separator = value.firstIndex(of: 61), separator > value.startIndex,
                    value[..<separator].allSatisfy({ (32...125).contains($0) })
                else { throw Failure.invalidFile }
                entries.append(value)
                keys.insert(String(decoding: value[..<separator], as: UTF8.self).uppercased())
            }
            guard offset == bytes.count else { throw Failure.invalidFile }
        }

        mutating func add(_ key: String, _ value: String?, aliases: [String] = []) {
            guard let value, !value.isEmpty, !([key] + aliases).contains(where: keys.contains) else { return }
            entries.append(Data("\(key)=\(value)".utf8))
            keys.insert(key)
        }

        func encoded() throws -> Data {
            let size = 8 + vendor.count + entries.reduce(0) { $0 + 4 + $1.count }
            guard size <= 0xFF_FFFF else { throw Failure.tooLarge }
            var data = littleEndian(vendor.count) + vendor + littleEndian(entries.count)
            for entry in entries { data.append(littleEndian(entry.count) + entry) }
            return data
        }

        private func littleEndian(_ value: Int) -> Data {
            Data((0..<4).map { UInt8(value >> ($0 * 8) & 255) })
        }
    }

    private static func picture(_ image: Data) -> Data {
        func number(_ value: Int) -> Data { Data((0..<4).reversed().map { UInt8(value >> ($0 * 8) & 255) }) }
        let mime = Data((image.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg").utf8)
        // RFC 9639 permits zero for unknown dimensions/depth; the encoded image retains its own dimensions.
        return number(3) + number(mime.count) + mime + number(0)
            + number(0) + number(0) + number(0) + number(0) + number(image.count) + image
    }

    private enum Failure: LocalizedError {
        case sameFile, invalidFile, tooLarge
        var errorDescription: String? {
            switch self {
            case .sameFile: "Export requires a separate copy of the audio file."
            case .invalidFile: "This FLAC has unreadable metadata. The saved file hasn't been changed."
            case .tooLarge: "This FLAC's metadata is too large to export. The saved file hasn't been changed."
            }
        }
    }
}
