import Foundation
import GevunCore

final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var owner: DownloadStore?
    let root: URL
    init(root: URL) { self.root = root }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        do {
            let handle = try FileHandle(forReadingFrom: location)
            defer { try? handle.close() }
            let prefix = try handle.read(upToCount: 4096) ?? Data()
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            if let error = DownloadLibrary.responseError(status: status, prefix: prefix) {
                throw DownloadFailure(error)
            }
            let staged = root.appendingPathComponent("\(id.uuidString).staged.part")
            try FileManager.default.moveItem(at: location, to: staged)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: staged.path)
            Task { @MainActor [weak self] in self?.owner?.received(id, file: staged) }
        } catch {
            let message = friendlyDownloadError(error)
            Task { @MainActor [weak self] in self?.owner?.fail(id, message: message) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        if let network = error as? URLError, [.notConnectedToInternet, .networkConnectionLost].contains(network.code) {
            Task { @MainActor [weak self] in self?.owner?.networkInterrupted(id) }
            return
        }
        let message = friendlyDownloadError(error)
        Task { @MainActor [weak self] in self?.owner?.fail(id, message: message) }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        Task { @MainActor [weak self] in
            self?.owner?.updateProgress(id, written: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let original = task.originalRequest?.url, let target = request.url,
            SameOriginRedirects.sameOrigin(original, target)
        else { completionHandler(nil); return }
        completionHandler(request)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak self] in self?.owner?.finishedBackgroundEvents() }
    }
}
