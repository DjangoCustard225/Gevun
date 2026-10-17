import AVFoundation
import AudioToolbox
import Foundation
import GevunCore

struct DownloadFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func friendlyDownloadError(_ error: Error) -> String {
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError
        || (error as? URLError)?.code == .cannotWriteToFile
    {
        return "There isn't enough free storage. Free some space and retry."
    }
    // Avoid exposing authenticated URLs contained in URLSession's diagnostic descriptions.
    if error is URLError { return "The download was interrupted. Check your connection and retry." }
    return error.localizedDescription
}

enum DownloadValidation {
    struct Result { let file: URL; let extensionName: String; let bytes: Int64 }

    static func check(_ file: URL, job: DownloadJob) async throws -> Result {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: file)
        let prefix = try handle.read(upToCount: 4096) ?? Data()
        try handle.close()
        if let error = DownloadLibrary.responseError(status: 200, prefix: prefix) { throw DownloadFailure(error) }
        let isMP4 = prefix.count >= 8 && String(decoding: prefix[4..<8], as: UTF8.self) == "ftyp"
        let suffix = job.song.suffix?.lowercased() ?? "audio"
        let safeSuffix =
            !suffix.isEmpty && suffix.count < 9 && suffix.allSatisfy { $0.isASCII && $0.isLetter || $0.isNumber }
            ? suffix : "audio"
        let ext =
            job.quality.format == .original
            ? safeSuffix : isMP4 && job.quality.format == .aac ? "m4a" : job.quality.format.rawValue
        let typed = file.deletingLastPathComponent().appendingPathComponent("\(job.id.uuidString).staged.\(ext)")
        if file != typed { try FileManager.default.moveItem(at: file, to: typed) }
        let asset = AVURLAsset(url: typed, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard try await asset.load(.isPlayable) else {
            throw DownloadFailure("This file can't play through the native player. Try downloading as MP3 or AAC.")
        }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw DownloadFailure("The downloaded audio has no readable duration. Try another format.")
        }
        if let expected = job.song.duration, expected > 0, duration + max(3, Double(expected) * 0.02) < Double(expected)
        {
            throw DownloadFailure("The downloaded file appears incomplete. Retry the download.")
        }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw DownloadFailure("The downloaded file has no audio track.") }
        let formats = try await track.load(.formatDescriptions)
        let codecs = formats.map { CMFormatDescriptionGetMediaSubType($0) }
        let expected: AudioFormatID?
        switch job.quality.format {
        case .original: expected = nil
        case .opus: expected = kAudioFormatOpus
        case .mp3: expected = kAudioFormatMPEGLayer3
        case .aac: expected = kAudioFormatMPEG4AAC
        }
        if let expected, !codecs.contains(expected) {
            throw DownloadFailure(
                "The server returned a different format. Check that its \(job.quality.format.title) transcoder is available."
            )
        }
        let bytes = try typed.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes > 0 else { throw DownloadFailure("The server returned an empty file.") }
        if job.quality.format == .original, let expected = job.song.size, expected > 0, Int64(bytes) != expected {
            throw DownloadFailure("The downloaded file size doesn't match the original. Retry the download.")
        }
        try Task.checkCancellation()
        return Result(file: typed, extensionName: ext, bytes: Int64(bytes))
    }
}
