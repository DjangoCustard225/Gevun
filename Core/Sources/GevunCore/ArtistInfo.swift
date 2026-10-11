import Foundation

public struct ArtistInfo: Decodable, Sendable {
    public let biography: String?
    public let musicBrainzId: String?
    public let lastFmUrl: String?
    public let similarArtist: [Artist]?

    /// Convert provider HTML to inert text without loading web content or remote resources.
    public var description: String? {
        guard var text = biography else { return nil }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        for pattern in [#"(?is)<!--.*?-->"#, #"(?is)<(script|style)\b[^>]*>.*?</\1\s*>"#] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(
            of: #"(?i)<br\s*/?>|</(?:p|div|li|h[1-6])\s*>"#, with: "\n\n", options: .regularExpression
        )
        .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        let entities = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
            "ndash": "–", "mdash": "—", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
            "hellip": "…", "copy": "©", "reg": "®", "bull": "•", "eacute": "é",
        ]
        if let regex = try? NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);"#) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let range = Range(match.range, in: text), let nameRange = Range(match.range(at: 1), in: text)
                else { continue }
                let name = String(text[nameRange])
                var replacement = entities[name]
                if name.hasPrefix("#") {
                    let hex = name.hasPrefix("#x")
                    if let value = UInt32(name.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10),
                        let scalar = UnicodeScalar(value), value >= 32 || value == 10
                    {
                        replacement = String(scalar)
                    }
                }
                if let replacement { text.replaceSubrange(range, with: replacement) }
            }
        }
        text = text.replacingOccurrences(of: #"[^\S\n]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return ArtistCredit.nonempty(text)
    }

    public var lastFMURL: URL? {
        guard let value = ArtistCredit.nonempty(lastFmUrl), let url = URL(string: value),
            ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
            let host = url.host?.lowercased(), host == "last.fm" || host.hasSuffix(".last.fm"),
            url.user == nil, url.password == nil
        else { return nil }
        return url
    }

    public var musicBrainzURL: URL? {
        guard let id = ArtistCredit.nonempty(musicBrainzId), let uuid = UUID(uuidString: id) else { return nil }
        return URL(string: "https://musicbrainz.org/artist/\(uuid.uuidString.lowercased())")
    }

    public func relatedArtists(excluding id: String) -> [Artist] {
        var seen: Set<String> = [id]
        return (similarArtist ?? []).filter {
            !$0.id.isEmpty && $0.id != "-1" && ArtistCredit.nonempty($0.name) != nil && seen.insert($0.id).inserted
        }
    }
}
