import AVFoundation
import GevunCore

/// Probe actual local files, rather than inferring AVPlayer support from Safari's codec list.
actor NativeDownloadFormats {
    static let shared = NativeDownloadFormats()
    private var cached: Set<DownloadFormat>?
    func supported() async -> Set<DownloadFormat> {
        if let cached { return cached }
        var result: Set<DownloadFormat> = [.original]
        guard let url = Bundle.main.url(forResource: "DownloadProbes", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let probes = try? PropertyListDecoder().decode([String: Data].self, from: data)
        else { return result }
        for format in DownloadFormat.allCases where format != .original {
            guard let bytes = probes[format.rawValue] else { continue }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(format.rawValue)
            do {
                try bytes.write(to: file)
                let asset = AVURLAsset(url: file)
                if try await asset.load(.isPlayable), try await asset.load(.duration).seconds > 0,
                    let track = try await asset.loadTracks(withMediaType: .audio).first
                {
                    let reader = try AVAssetReader(asset: asset)
                    let output = AVAssetReaderTrackOutput(
                        track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
                    if reader.canAdd(output) {
                        let provider = reader.outputProvider(for: output)
                        try reader.start()
                        if try await provider.next() != nil { result.insert(format) }
                        reader.cancelReading()
                    }
                }
            } catch { /* Unsupported native codecs remain disabled. */  }
            try? FileManager.default.removeItem(at: file)
        }
        cached = result
        return result
    }
}
