import UIKit

@MainActor
final class DownloadAppDelegate: NSObject, UIApplicationDelegate {
    private static weak var downloads: DownloadStore?
    private static var pending: (() -> Void)?

    static func attach(_ store: DownloadStore) {
        downloads = store
        if let pending {
            store.attachBackgroundCompletion(pending)
            self.pending = nil
        }
    }

    func application(
        _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == DownloadStore.sessionIdentifier else { completionHandler(); return }
        if let downloads = Self.downloads {
            downloads.attachBackgroundCompletion(completionHandler)
        } else {
            Self.pending = completionHandler
        }
    }
}
