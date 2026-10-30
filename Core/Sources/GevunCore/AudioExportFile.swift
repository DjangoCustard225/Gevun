import Foundation

enum AudioExportFile {
    /// Write a new metadata header, then stream the untouched encoded audio into a separate file.
    static func write(to destination: URL, header: Data, copying input: FileHandle) async throws {
        try Task.checkCancellation()
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            try output.write(contentsOf: header)
            var chunks = 0
            while true {
                try Task.checkCancellation()
                guard let bytes = try input.read(upToCount: 1024 * 1024), !bytes.isEmpty else { break }
                try output.write(contentsOf: bytes)
                chunks += 1
                if chunks.isMultiple(of: 8) { await Task.yield() }
            }
            try Task.checkCancellation()
            try output.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
