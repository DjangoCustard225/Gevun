import UIKit
import GevunCore

@MainActor
final class ArtworkCache {
    weak var downloads: DownloadStore?
    private let cache = NSCache<NSString, UIImage>()
    private var tasks: [String: Task<UIImage?, Never>] = [:]
    private var generation = UUID()
    init() {
        cache.totalCostLimit = 60 * 1024 * 1024
        cache.countLimit = 180
    }
    func cachedImage(id: String, api: NavidromeAPI, size: Int) -> UIImage? {
        cache.object(forKey: key(id: id, api: api, size: size) as NSString)
    }

    func image(id: String, api: NavidromeAPI, size: Int = 600) async -> UIImage? {
        let key = key(id: id, api: api, size: size)
        if let image = cache.object(forKey: key as NSString) { return image }
        if let task = tasks[key] { return await task.value }
        let generation = generation
        let task = Task<UIImage?, Never> {
            let local = downloads.flatMap { try? Data(contentsOf: $0.artworkURL(id, instance: api.instance)) }
            let data: Data?
            if let local { data = local } else { data = try? await api.artwork(id, size: size) }
            guard let data, !Task.isCancelled,
                let source = UIImage(data: data)
            else { return nil }
            // UIKit decodes and downsamples asynchronously before the image reaches a frame.
            // Bound the decoded size even when a server ignores the requested thumbnail size.
            let prepared = await source.byPreparingThumbnail(ofSize: CGSize(width: size, height: size))
            guard !Task.isCancelled else { return nil }
            return prepared
        }
        tasks[key] = task
        let result = await task.value
        guard self.generation == generation, !task.isCancelled else { return nil }
        tasks[key] = nil
        if let result {
            let cost =
                result.cgImage.map { $0.bytesPerRow * $0.height } ?? Int(result.size.width * result.size.height * 4)
            cache.setObject(result, forKey: key as NSString, cost: cost)
        }
        return result
    }

    private func key(id: String, api: NavidromeAPI, size: Int) -> String {
        "\(api.instance.id):\(id):\(size)"
    }

    func clear() {
        generation = UUID()
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        cache.removeAllObjects()
    }
}
