import Foundation

/// ID3v2.3/v2.4 framing and text encoding, independent of the audio file and library metadata.
struct ID3Tag {
    private static let maximumTagSize = 32 * 1024 * 1024
    private(set) var version: UInt8 = 3
    private var revision: UInt8 = 0
    private var flags: UInt8 = 0
    private var frames = Data()
    private var identifiers = Set<String>()

    var textEncoding: UInt8 { version == 4 ? 3 : 1 }
    var textTerminator: Data { Data(repeating: 0, count: textEncoding == 1 ? 2 : 1) }

    static func read(from input: FileHandle) throws -> Self {
        let header = [UInt8](try input.read(upToCount: 10) ?? Data())
        guard header.starts(with: [0x49, 0x44, 0x33]) else {
            try input.seek(toOffset: 0)
            return Self()
        }
        guard header.count == 10, [3, 4].contains(header[3]), header[4] != 255 else {
            throw MP3ExportError.unsupportedTag
        }
        let allowedFlags: UInt8 = header[3] == 3 ? 0xE0 : 0xF0
        guard header[5] & ~allowedFlags == 0 else { throw MP3ExportError.unsupportedTag }
        let count = try integer(header[6..<10], synchsafe: true)
        guard count <= maximumTagSize else { throw MP3ExportError.tagTooLarge }
        var body = [UInt8](try input.read(upToCount: count) ?? Data())
        guard body.count == count else { throw MP3ExportError.corruptTag }
        if header[3] == 4, header[5] & 0x10 != 0 {
            let footer = [UInt8](try input.read(upToCount: 10) ?? Data())
            guard footer == [0x33, 0x44, 0x49] + Array(header[3...]) else { throw MP3ExportError.corruptTag }
        }
        if header[3] == 3, header[5] & 0x80 != 0 { body = deunsynchronised(body) }
        var offset = 0
        if header[5] & 0x40 != 0 {
            guard body.count >= 4 else { throw MP3ExportError.corruptTag }
            let size = try integer(body[0..<4], synchsafe: header[3] == 4)
            offset = header[3] == 3 ? size + 4 : size
            guard offset >= (header[3] == 3 ? 10 : 6), offset <= body.count else {
                throw MP3ExportError.corruptTag
            }
        }
        // Extended headers contain CRC/padding/restrictions that would become stale after editing.
        // Preserve frame contents and rebuild the structural header without a CRC or footer.
        var tag = Self(version: header[3], revision: header[4], flags: header[5] & 0xA0)
        while offset < body.count {
            if body[offset] == 0 {
                guard body[offset...].allSatisfy({ $0 == 0 }) else { throw MP3ExportError.corruptTag }
                break
            }
            guard body.count - offset >= 10 else { throw MP3ExportError.corruptTag }
            let id = body[offset..<offset + 4]
            guard id.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) else {
                throw MP3ExportError.corruptTag
            }
            let size = try integer(body[offset + 4..<offset + 8], synchsafe: tag.version == 4)
            guard size > 0, size <= body.count - offset - 10 else { throw MP3ExportError.corruptTag }
            tag.identifiers.insert(String(decoding: id, as: UTF8.self))
            tag.frames.append(contentsOf: body[offset..<offset + 10 + size])
            offset += 10 + size
        }
        return tag
    }

    func text(_ value: String) -> Data {
        let value = value.replacingOccurrences(of: "\u{0}", with: " ")
        if textEncoding == 3 { return Data(value.utf8) }
        return Data([0xFF, 0xFE]) + Data(value.utf16.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] })
    }

    mutating func addText(_ id: String, _ value: String?) throws {
        guard let value, !value.isEmpty else { return }
        try addFrame(id, payload: Data([textEncoding]) + text(value))
    }

    mutating func addFrame(_ id: String, payload: Data) throws {
        guard !identifiers.contains(id) else { return }
        var bytes = payload
        var frameFlags: UInt8 = 0
        if version == 4 {
            let escaped = Data(Self.unsynchronised([UInt8](payload)))
            if flags & 0x80 != 0 || escaped != payload {
                bytes = escaped
                frameFlags = 2
            }
        }
        guard bytes.count <= Self.maximumTagSize, frames.count + bytes.count + 10 <= Self.maximumTagSize else {
            throw MP3ExportError.tagTooLarge
        }
        frames.append(Data(id.utf8))
        frames.append(contentsOf: Self.encodedInteger(bytes.count, synchsafe: version == 4))
        frames.append(contentsOf: [0, frameFlags])
        frames.append(bytes)
        identifiers.insert(id)
    }

    func encoded() throws -> Data {
        var body = frames
        var headerFlags = flags
        if version == 3 {
            body = Data(Self.unsynchronised([UInt8](frames)))
            headerFlags = body == frames ? flags & ~0x80 : flags | 0x80
        }
        guard body.count <= Self.maximumTagSize else { throw MP3ExportError.tagTooLarge }
        return Data("ID3".utf8) + Data([version, revision, headerFlags])
            + Data(Self.encodedInteger(body.count, synchsafe: true)) + body
    }

    private static func integer(_ bytes: ArraySlice<UInt8>, synchsafe: Bool) throws -> Int {
        guard !synchsafe || bytes.allSatisfy({ $0 < 128 }) else { throw MP3ExportError.corruptTag }
        return bytes.reduce(0) { ($0 << (synchsafe ? 7 : 8)) | Int($1) }
    }

    static func encodedInteger(_ value: Int, synchsafe: Bool) -> [UInt8] {
        let bits = synchsafe ? 7 : 8
        let mask = synchsafe ? 127 : 255
        return (0..<4).reversed().map { UInt8((value >> ($0 * bits)) & mask) }
    }

    private static func unsynchronised(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        for index in bytes.indices {
            result.append(bytes[index])
            if bytes[index] == 255,
                index + 1 == bytes.count || bytes[index + 1] == 0 || bytes[index + 1] >= 224
            {
                result.append(0)
            }
        }
        return result
    }

    private static func deunsynchronised(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        var index = 0
        while index < bytes.count {
            result.append(bytes[index])
            if bytes[index] == 255, index + 1 < bytes.count, bytes[index + 1] == 0 { index += 1 }
            index += 1
        }
        return result
    }
}

enum MP3ExportError: LocalizedError {
    case sameFile, unsupportedTag, corruptTag, tagTooLarge
    var errorDescription: String? {
        switch self {
        case .sameFile: "Export requires a separate copy of the audio file."
        case .unsupportedTag: "This MP3 uses an unsupported ID3 tag version. The saved file hasn't been changed."
        case .corruptTag: "This MP3 has an unreadable ID3 tag. The saved file hasn't been changed."
        case .tagTooLarge: "This MP3's metadata is too large to export. The saved file hasn't been changed."
        }
    }
}
