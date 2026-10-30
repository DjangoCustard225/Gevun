import Foundation
import Observation
import GevunCore

@MainActor
@Observable
final class ListeningSessionStore {
    var automatic = true {
        didSet {
            guard automatic != oldValue, let namespace else { return }
            restoreTask?.cancel()
            generation = UUID(); fetching = false
            worker?.cancel(); worker = nil
            UserDefaults.standard.set(automatic, forKey: "queueSync-" + namespace)
            if automatic {
                initialFetchPending = true; startupRevision = player?.interactionRevision ?? 0; fetch()
            } else {
                worker?.cancel(); pending = nil
            }
        }
    }
    private(set) var status: String?
    @ObservationIgnored private weak var player: PlayerStore?
    @ObservationIgnored private var api: NavidromeAPI?
    @ObservationIgnored private var namespace: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var startupRevision = 0
    @ObservationIgnored private var initialFetchPending = true
    @ObservationIgnored private var fetching = false
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    @ObservationIgnored private var lastFetch = Date.distantPast
    @ObservationIgnored private var lastUpload = Date.distantPast
    @ObservationIgnored private var pending: ListeningSession?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    private let directory: URL

    init(player: PlayerStore) {
        self.player = player
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ListeningSessions", isDirectory: true)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                self?.checkpoint()
            }
        }
    }

    func configure(_ api: NavidromeAPI?) {
        worker?.cancel(); changeTask?.cancel(); restoreTask?.cancel()
        generation = UUID(); pending = nil; fetching = false; worker = nil
        self.api = api
        namespace = api.map { DownloadKey.namespace(for: $0.instance) }
        initialFetchPending = true
        lastFetch = .distantPast; lastUpload = .distantPast; status = nil
        guard let namespace, let player else { return }
        automatic = UserDefaults.standard.object(forKey: "queueSync-" + namespace) as? Bool ?? true
        if let data = try? Data(contentsOf: file(namespace)),
            let saved = try? JSONDecoder().decode(ListeningSession.self, from: data), saved.isValid
        {
            player.restorePaused(saved)
        }
        startupRevision = player.interactionRevision
        if automatic { fetch() }
    }

    func changed() {
        changeTask?.cancel()
        changeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            self?.checkpoint(urgent: true)
        }
    }

    func checkpoint(urgent: Bool = false) {
        if automatic && initialFetchPending && Date().timeIntervalSince(lastFetch) >= 30 { fetch() }
        guard let player, let namespace, player.current != nil else { return }
        guard urgent || player.isPlaying || pending != nil else { return }
        let snapshot = ListeningSession(queue: player.queue, position: player.elapsed)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            try JSONEncoder().encode(snapshot).write(to: file(namespace), options: .atomic)
        } catch { status = "Couldn't save the listening position on this device." }
        guard automatic else { return }
        if initialFetchPending {
            if Date().timeIntervalSince(lastFetch) >= 30 { fetch() }
            return
        }
        guard urgent || (player.isPlaying && Date().timeIntervalSince(lastUpload) >= 15) || pending != nil else {
            return
        }
        pending = snapshot
        upload()
    }

    func saveManually() async {
        startupRevision = -1
        guard let player, player.current != nil else { return }
        pending = ListeningSession(queue: player.queue, position: player.elapsed)
        upload()
        await worker?.value
    }

    func remove(instance: Instance) {
        let namespace = DownloadKey.namespace(for: instance)
        try? FileManager.default.removeItem(at: file(namespace))
        UserDefaults.standard.removeObject(forKey: "queueSync-" + namespace)
    }

    private func file(_ namespace: String) -> URL { directory.appendingPathComponent(namespace + ".json") }

    private func fetch() {
        guard automatic, !fetching, let api else { return }
        fetching = true; lastFetch = Date()
        let generation = generation
        restoreTask = Task { [weak self] in
            do {
                let saved = try await api.savedQueue()
                guard let self, self.generation == generation, self.automatic else { return }
                self.fetching = false; self.initialFetchPending = false
                if let player = self.player, player.interactionRevision == self.startupRevision,
                    let saved, !saved.songs.isEmpty
                {
                    var queue = player.queue
                    if queue.songs.map(\.id) == saved.songs.map(\.id) {
                        queue.select(saved.index)
                    } else {
                        queue.replace(saved.songs, startingAt: saved.index)
                    }
                    player.restorePaused(ListeningSession(queue: queue, position: saved.seconds))
                }
                self.status = nil
                self.checkpoint(urgent: self.player?.interactionRevision != self.startupRevision)
            } catch {
                guard let self, self.generation == generation else { return }
                self.fetching = false
                self.status = "Using the queue on this device. Server sync will retry."
            }
        }
    }

    private func upload() {
        guard worker == nil, let api else { return }
        let generation = generation
        worker = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == generation { self.worker = nil } }
            while let snapshot = self.pending, self.generation == generation, !Task.isCancelled {
                self.pending = nil
                do {
                    try await api.saveQueue(
                        songs: snapshot.queue.songs, index: snapshot.queue.index, position: snapshot.position)
                    guard self.generation == generation, !Task.isCancelled else { return }
                    self.lastUpload = Date(); self.status = "Queue saved to Navidrome."
                } catch {
                    guard self.generation == generation, !Task.isCancelled else { return }
                    if self.pending == nil { self.pending = snapshot }
                    self.status = "Server sync couldn't finish. Your queue is saved on this device."
                    return
                }
            }
        }
    }
    deinit { timer?.cancel(); worker?.cancel(); changeTask?.cancel(); restoreTask?.cancel() }
}
