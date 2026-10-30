import Foundation
import GevunCore
import Network
import Observation

@MainActor
@Observable
final class DownloadStore {
    private(set) var library = DownloadLibrary() {
        didSet {
            let keys = Set(library.copies.map(\.key))
            if keys != savedKeys { savedKeys = keys }
        }
    }
    private(set) var savedKeys: Set<DownloadKey> = []
    private(set) var progress: [UUID: Double] = [:]
    private(set) var connected = false
    private(set) var onWiFi = false
    private(set) var storageError: String?
    var wifiOnly: Bool {
        didSet {
            guard wifiOnly != oldValue else { return }
            UserDefaults.standard.set(wifiOnly, forKey: "downloadsWiFiOnly")
            // Each request captures the cellular policy. Recreate unfinished requests when it changes.
            for id in Array(active.keys) { restart(id) }
            pump()
        }
    }
    @ObservationIgnored private var instances: [String: Instance] = [:]
    @ObservationIgnored private let root: URL
    @ObservationIgnored private let delegate: DownloadDelegate
    @ObservationIgnored private var session: URLSession!
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var active: [UUID: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var validations: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var metadataTask: Task<Void, Never>?
    @ObservationIgnored private var committedLibrary = DownloadLibrary()
    @ObservationIgnored private var reconciling = true
    @ObservationIgnored private var configurationRevision = UUID()
    @ObservationIgnored private var backgroundEventsFinished = false
    @ObservationIgnored private var backgroundCompletion: (() -> Void)?

    static let sessionIdentifier = "app.gevun.music.downloads"

    init() {
        wifiOnly = UserDefaults.standard.object(forKey: "downloadsWiFiOnly") as? Bool ?? true
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineMusic", isDirectory: true)
        delegate = DownloadDelegate(root: root)
        do {
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var directory = root
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            let index = root.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: index.path) {
                library = try JSONDecoder().decode(DownloadLibrary.self, from: Data(contentsOf: index))
            }
            library.copies.removeAll {
                !FileManager.default.fileExists(atPath: root.appendingPathComponent($0.filename).path)
            }
        } catch {
            storageError = "Couldn't open download storage. \(error.localizedDescription)"
        }
        committedLibrary = library
        delegate.owner = self
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 7 * 24 * 3600
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.connected = path.status == .satisfied
                self.onWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
                if !self.canTransfer { self.metadataTask?.cancel() }
                self.resumeWaiting()
                self.pump()
                self.cacheMetadata()
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.gevun.download-network"))
    }

    var canTransfer: Bool { connected && (!wifiOnly || onWiFi) }
    var waitingMessage: String? {
        if !connected { return "Waiting for a connection" }
        return wifiOnly && !onWiFi ? "Waiting for Wi-Fi" : nil
    }

    func configure(instances: [Instance]) {
        reconciling = true
        let revision = UUID()
        configurationRevision = revision
        let previous = self.instances
        self.instances = Dictionary(uniqueKeysWithValues: instances.map { (DownloadKey.namespace(for: $0), $0) })
        for id in Array(active.keys) {
            if let namespace = library.jobs.first(where: { $0.id == id })?.key.namespace,
                let old = previous[namespace], let updated = self.instances[namespace], old.password != updated.password
            {
                restart(id)
            }
        }
        session.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                guard let self, self.configurationRevision == revision else { return }
                let live = self.instances
                let removed = Set(self.library.jobs.map(\.key.namespace) + self.library.copies.map(\.key.namespace))
                    .subtracting(live.keys)
                for namespace in removed { self.removeNamespace(namespace) }
                self.active = [:]
                for task in tasks {
                    guard let download = task as? URLSessionDownloadTask,
                        let text = task.taskDescription, let id = UUID(uuidString: text),
                        self.library.jobs.contains(where: { $0.id == id }), self.validations[id] == nil
                    else { task.cancel(); continue }
                    self.active[id] = download
                }
                for index in self.library.jobs.indices {
                    let job = self.library.jobs[index]
                    if self.validations[job.id] != nil { continue }
                    if let file = self.stagedFile(job.id) {
                        self.validate(job.id, file: file)
                    } else if self.active[job.id] == nil && job.state != .failed {
                        self.library.jobs[index].state = .queued
                    }
                }
                self.reconciling = false
                self.persist()
                self.pruneUnreferencedFiles()
                self.pump()
                self.cacheMetadata()
                self.finishBackgroundEventsIfReady()
            }
        }
    }

    func copies(namespace: String) -> [OfflineSong] {
        library.copies.filter { $0.key.namespace == namespace }
            .sorted { $0.song.title.localizedStandardCompare($1.song.title) == .orderedAscending }
    }

    func localURL(songID: String, instance: Instance) -> URL? {
        let key = DownloadKey(namespace: DownloadKey.namespace(for: instance), songID: songID)
        guard let copy = library.copies.first(where: { $0.key == key }) else { return nil }
        let url = root.appendingPathComponent(copy.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func exportSource(for copy: OfflineSong) -> DownloadExportSource {
        let instance = instances[copy.key.namespace]
        let album = copy.song.albumId.flatMap { savedAlbum($0, namespace: copy.key.namespace) }
        let artwork = instance.flatMap { instance in
            (copy.song.coverArt ?? album?.coverArt).map { artworkURL($0, instance: instance) }
        }
        return DownloadExportSource(
            copy: copy, url: root.appendingPathComponent(copy.filename), album: album,
            artworkURL: artwork, lyricsURL: lyricsURL(copy.key), instance: connected ? instance : nil)
    }

    func savedAlbum(_ id: String, namespace: String) -> Album? {
        library.albums.first { $0.namespace == namespace && $0.album.id == id }?.album
    }

    func savedSongs(albumID: String, namespace: String) -> [Song] {
        copies(namespace: namespace).map(\.song).filter { $0.albumId == albumID }.sorted {
            ($0.discNumber ?? 1, $0.track ?? 0, $0.title) < ($1.discNumber ?? 1, $1.track ?? 0, $1.title)
        }
    }

    func quality(namespace: String) -> DownloadQuality { library.preferences[namespace] ?? DownloadQuality() }

    func enqueue(_ songs: [Song], instance: Instance, quality: DownloadQuality, album: Album? = nil) {
        guard storageError == nil else { return }
        let namespace = DownloadKey.namespace(for: instance)
        instances[namespace] = instance
        var updated = library
        updated.preferences[namespace] = quality
        if let album { updated.remember(album, namespace: namespace) }
        for song in songs { updated.enqueue(song, namespace: namespace, quality: quality) }
        library = updated
        persist()
        pump()
    }

    func cancel(_ id: UUID) {
        // Remove the job first: late delegate/validation callbacks cannot resurrect it.
        library.jobs.removeAll { $0.id == id }
        active.removeValue(forKey: id)?.cancel()
        validations.removeValue(forKey: id)?.cancel()
        progress[id] = nil
        if let file = stagedFile(id) { try? FileManager.default.removeItem(at: file) }
        persist()
        pump()
        finishBackgroundEventsIfReady()
    }

    func retry(_ id: UUID) {
        restart(id)
        pump()
    }

    private func resumeWaiting() {
        guard canTransfer else { return }
        for id in library.jobs.filter({ $0.state == .waiting }).map(\.id) { restart(id) }
    }

    func networkInterrupted(_ id: UUID) {
        active[id] = nil
        guard let index = library.jobs.firstIndex(where: { $0.id == id }) else { return }
        library.jobs[index].state = .waiting
        library.jobs[index].error = nil
        progress[id] = nil
        persist()
        pump()
    }

    private func restart(_ id: UUID) {
        guard let old = library.jobs.first(where: { $0.id == id }), validations[id] == nil else { return }
        library.jobs.removeAll { $0.id == id }
        active.removeValue(forKey: id)?.cancel()
        progress[id] = nil
        library.jobs.append(DownloadJob(key: old.key, song: old.song, quality: old.quality))
        persist()
    }

    func remove(_ key: DownloadKey) {
        for job in library.jobs.filter({ $0.key == key }) { cancel(job.id) }
        let removed = library.copies.filter { $0.key == key }
        library.copies.removeAll { $0.key == key }
        persist()
        guard storageError == nil else { return }
        for copy in removed { try? FileManager.default.removeItem(at: root.appendingPathComponent(copy.filename)) }
        try? FileManager.default.removeItem(at: lyricsURL(key))
        pruneArtwork(namespace: key.namespace)
    }

    func removeNamespace(_ namespace: String) {
        let ids = Set(library.jobs.filter { $0.key.namespace == namespace }.map { $0.id })
        let filenames = Set(library.copies.filter { $0.key.namespace == namespace }.map(\.filename))
        var updated = library
        updated.jobs.removeAll { $0.key.namespace == namespace }
        updated.copies.removeAll { $0.key.namespace == namespace }
        updated.albums.removeAll { $0.namespace == namespace }
        updated.preferences[namespace] = nil
        library = updated
        for id in ids {
            active.removeValue(forKey: id)?.cancel()
            validations.removeValue(forKey: id)?.cancel()
            progress[id] = nil
        }
        persist()
        guard storageError == nil else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let name = file.lastPathComponent
            let jobID = name.split(separator: ".").first.flatMap { UUID(uuidString: String($0)) }
            if filenames.contains(name) || name.hasPrefix(namespace + "-") || jobID.map(ids.contains) == true {
                try? FileManager.default.removeItem(at: file)
            }
        }
        pump()
        finishBackgroundEventsIfReady()
    }

    private func pump() {
        guard !reconciling, storageError == nil, canTransfer else { return }
        while active.count + validations.count < 2,
            let index = library.jobs.firstIndex(where: { $0.state == .queued && instances[$0.key.namespace] != nil })
        {
            let job = library.jobs[index]
            guard let instance = instances[job.key.namespace] else { break }
            do {
                var request = URLRequest(
                    url: try NavidromeAPI(instance: instance).downloadURL(job.song.id, quality: job.quality))
                request.allowsCellularAccess = !wifiOnly
                request.setValue("audio/*, application/octet-stream", forHTTPHeaderField: "Accept")
                let task = session.downloadTask(with: request)
                task.taskDescription = job.id.uuidString
                library.jobs[index].state = .transferring
                persist()
                guard storageError == nil else { task.cancel(); return }
                active[job.id] = task
                task.resume()
            } catch { fail(job.id, message: friendlyError(error)) }
        }
    }

    func received(_ id: UUID, file: URL) {
        active[id] = nil
        guard library.jobs.contains(where: { $0.id == id }), !reconciling else {
            if !library.jobs.contains(where: { $0.id == id }) { try? FileManager.default.removeItem(at: file) }
            return
        }
        validate(id, file: file)
    }

    private func validate(_ id: UUID, file: URL) {
        guard let index = library.jobs.firstIndex(where: { $0.id == id }), validations[id] == nil else { return }
        let job = library.jobs[index]
        active[id] = nil
        library.jobs[index].state = .validating
        persist()
        validations[id] = Task { [weak self] in
            do {
                let validated = try await DownloadValidation.check(file, job: job)
                try Task.checkCancellation()
                guard let self, self.library.jobs.contains(where: { $0.id == id }) else { return }
                let filename = "\(id.uuidString).\(validated.extensionName)"
                let destination = self.root.appendingPathComponent(filename)
                try FileManager.default.moveItem(at: validated.file, to: destination)
                let previousLibrary = self.library
                let previous = self.library.complete(id, filename: filename, bytes: validated.bytes)
                self.persist()
                if self.storageError != nil {
                    self.library = previousLibrary
                    try? FileManager.default.moveItem(at: destination, to: file)
                } else if let previous {
                    try? FileManager.default.removeItem(at: self.root.appendingPathComponent(previous.filename))
                }
            } catch {
                if !Task.isCancelled { self?.fail(id, message: friendlyError(error)) }
            }
            guard let self else { return }
            self.validations[id] = nil
            self.progress[id] = nil
            self.pump()
            self.cacheMetadata()
            self.finishBackgroundEventsIfReady()
        }
    }

    func fail(_ id: UUID, message: String) {
        active[id] = nil
        guard let index = library.jobs.firstIndex(where: { $0.id == id }) else { return }
        library.jobs[index].state = .failed
        library.jobs[index].error = message
        progress[id] = nil
        if let file = stagedFile(id) { try? FileManager.default.removeItem(at: file) }
        persist()
        pump()
    }

    func updateProgress(_ id: UUID, written: Int64, expected: Int64) {
        guard active[id] != nil, expected > 0 else { return }
        let value = min(1, max(0, Double(written) / Double(expected)))
        // Avoid invalidating song rows on every network packet.
        if abs((progress[id] ?? -1) - value) >= 0.01 { progress[id] = value }
    }

    private func persist() {
        guard storageError == nil else { return }
        do {
            try JSONEncoder().encode(library).write(to: root.appendingPathComponent("library.json"), options: .atomic)
            committedLibrary = library
        } catch {
            library = committedLibrary
            storageError = "Couldn't save download storage. \(friendlyDownloadError(error))"
        }
    }

    func retryStorage() {
        guard storageError != nil else { return }
        do {
            let index = root.appendingPathComponent("library.json")
            library =
                FileManager.default.fileExists(atPath: index.path)
                ? try JSONDecoder().decode(DownloadLibrary.self, from: Data(contentsOf: index)) : DownloadLibrary()
            committedLibrary = library
            storageError = nil
            configure(instances: Array(instances.values))
        } catch { storageError = "Couldn't open download storage. \(friendlyDownloadError(error))" }
    }

    private func stagedFile(_ id: UUID) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        // Also recover a validated file moved just before a process exit interrupted the index commit.
        return files.first {
            file in
            file.lastPathComponent.hasPrefix(id.uuidString + ".")
                && !library.copies.contains(where: { $0.filename == file.lastPathComponent })
        }
    }

    func finishedBackgroundEvents() {
        backgroundEventsFinished = true
        finishBackgroundEventsIfReady()
    }

    private func pruneUnreferencedFiles() {
        guard storageError == nil else { return }
        let saved = Set(library.copies.map(\.filename))
        let jobs = library.jobs.map { $0.id.uuidString + "." }
        let namespaces = instances.keys.map { $0 + "-" }
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let name = file.lastPathComponent
            if name == "library.json" || saved.contains(name) || jobs.contains(where: { name.hasPrefix($0) })
                || namespaces.contains(where: { name.hasPrefix($0) })
            {
                continue
            }
            try? FileManager.default.removeItem(at: file)
        }
    }

    func attachBackgroundCompletion(_ completion: @escaping () -> Void) {
        backgroundCompletion = completion
        finishBackgroundEventsIfReady()
    }

    private func finishBackgroundEventsIfReady() {
        guard backgroundEventsFinished, validations.isEmpty, !reconciling, let completion = backgroundCompletion else {
            return
        }
        backgroundEventsFinished = false
        backgroundCompletion = nil
        completion()
    }

    // Optional metadata is independent of successful audio downloads.
    func artworkURL(_ id: String, instance: Instance) -> URL {
        root.appendingPathComponent("\(DownloadKey.namespace(for: instance))-art-\(Self.digest(id)).image")
    }

    private static func digest(_ value: String) -> String { SubsonicToken.hash(password: value, salt: "") }

    private func lyricsURL(_ key: DownloadKey) -> URL {
        root.appendingPathComponent("\(key.namespace)-lyrics-\(Self.digest(key.songID)).json")
    }

    func lyrics(songID: String, instance: Instance) -> [StructuredLyrics]? {
        let key = DownloadKey(namespace: DownloadKey.namespace(for: instance), songID: songID)
        guard let data = try? Data(contentsOf: lyricsURL(key)) else { return nil }
        return try? JSONDecoder().decode([StructuredLyrics].self, from: data)
    }

    private func cacheMetadata() {
        guard metadataTask == nil, canTransfer else { return }
        let copies = library.copies
        let cachedKeys = Set(copies.map(\.key))
        metadataTask = Task { [weak self] in
            defer {
                self?.metadataTask = nil
                if let self, self.canTransfer,
                    Task.isCancelled
                        || self.library.copies.contains(where: { current in
                            !cachedKeys.contains(current.key)
                        })
                {
                    self.cacheMetadata()
                }
            }
            for (index, copy) in copies.enumerated() {
                if index.isMultiple(of: 8) { await Task.yield() }
                guard let self, !Task.isCancelled, self.canTransfer else { return }
                let key = copy.key
                guard let instance = self.instances[key.namespace] else { continue }
                let api = NavidromeAPI(instance: instance)
                if let albumID = copy.song.albumId, self.savedAlbum(albumID, namespace: key.namespace) == nil,
                    let album = try? await api.album(albumID), self.savedKeys.contains(key)
                {
                    self.library.remember(album, namespace: key.namespace)
                    self.persist()
                }
                let artIDs = Set(
                    [
                        copy.song.coverArt,
                        copy.song.albumId.flatMap { self.savedAlbum($0, namespace: key.namespace)?.coverArt },
                    ].compactMap { $0 })
                for artID in artIDs {
                    let url = self.artworkURL(artID, instance: instance)
                    if !FileManager.default.fileExists(atPath: url.path),
                        let data = try? await api.artwork(artID, size: 1200),
                        self.savedKeys.contains(key)
                    {
                        try? data.write(to: url, options: .atomic)
                    }
                }
                let lyricsURL = self.lyricsURL(key)
                if !FileManager.default.fileExists(atPath: lyricsURL.path),
                    let lyrics = try? await api.lyrics(for: copy.song),
                    self.savedKeys.contains(key)
                {
                    try? JSONEncoder().encode(lyrics).write(to: lyricsURL, options: .atomic)
                }
            }
        }
    }

    private func pruneArtwork(namespace: String) {
        let used = Set(
            library.copies.filter { $0.key.namespace == namespace }.flatMap { copy in
                [copy.song.coverArt, copy.song.albumId.flatMap { savedAlbum($0, namespace: namespace)?.coverArt }]
                    .compactMap { $0 }.map(Self.digest)
            })
        let prefix = namespace + "-art-"
        for file in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            if file.lastPathComponent.hasPrefix(prefix),
                !used.contains(String(file.deletingPathExtension().lastPathComponent.dropFirst(prefix.count)))
            {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
