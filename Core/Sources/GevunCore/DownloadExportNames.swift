import Foundation

public enum DownloadExportNames {
    private static let forbiddenCharacters = CharacterSet.controlCharacters.union(
        CharacterSet(charactersIn: "/\\:*?\"<>|"))

    /// Converted AAC is exported in a taggable M4A container; original files keep their extension.
    public static func filenames(for copies: [OfflineSong]) -> [String] {
        var used = Set<String>()
        return copies.map { copy in
            let artist = clean(copy.song.artistName, fallback: "Unknown artist")
            let title = clean(copy.song.title, fallback: "Untitled")
            let stem = limited("\(artist) - \(title)")
            let suffix =
                copy.quality.format == .aac
                ? "m4a" : URL(fileURLWithPath: copy.filename).pathExtension.lowercased()
            let ext =
                !suffix.isEmpty && suffix.utf8.count <= 8
                    && suffix.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
                ? suffix : "audio"
            var filename = "\(stem).\(ext)"
            var number = 2
            while !used.insert(filename.precomposedStringWithCanonicalMapping.lowercased()).inserted {
                filename = "\(stem) (\(number)).\(ext)"
                number += 1
            }
            return filename
        }
    }

    private static func clean(_ value: String, fallback: String) -> String {
        let cleaned = value.components(separatedBy: forbiddenCharacters).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return cleaned.isEmpty ? fallback : cleaned
    }

    private static func limited(_ value: String) -> String {
        // Leave room for the extension and duplicate suffix within a 255-byte filesystem component.
        var result = ""
        var bytes = 0
        for character in value {
            let count = character.utf8.count
            guard bytes + count <= 220 else { break }
            result.append(character)
            bytes += count
        }
        return result.isEmpty ? "Song" : result.trimmingCharacters(in: .whitespaces)
    }
}
