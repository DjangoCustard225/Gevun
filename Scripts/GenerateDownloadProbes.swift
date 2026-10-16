import Foundation

// Tiny generated tones exercise Navidrome's MP3 and ADTS AAC containers.
// Run from the repository root with ffmpeg installed. No copyrighted audio is used.
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
var probes: [String: Data] = [:]
for (format, codec, container, bitrate) in [
    ("mp3", "libmp3lame", "mp3", "192k"),
    ("aac", "aac", "adts", "256k"),
] {
    let file = temporary.appendingPathComponent(format)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.5:sample_rate=48000",
        "-af", "volume=0.01", "-ac", "2", "-c:a", codec, "-b:a", bitrate, "-f", container, file.path,
    ]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("Couldn't generate \(format) probe") }
    probes[format] = try Data(contentsOf: file)
}
let directory = URL(fileURLWithPath: "Gevun/Resources", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let encoder = PropertyListEncoder()
encoder.outputFormat = .binary
let data = try encoder.encode(probes)
try data.write(to: directory.appendingPathComponent("DownloadProbes.plist"), options: .atomic)
print("Generated native format probes (\(data.count) bytes).")
