import SwiftUI
import GevunCore

/// Settings row that asks Navidrome to rescan its music folders and shows the scan's progress.
struct LibraryScanRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @State private var status: ScanStatus?
    @State private var starting = false
    @State private var message: String?

    private var scanning: Bool { starting || status?.scanning == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                Button("Scan for changes", systemImage: "arrow.clockwise") { start(full: false) }
                Button("Full rescan", systemImage: "arrow.triangle.2.circlepath") { start(full: true) }
            } label: {
                HStack {
                    Label("Scan library", systemImage: "arrow.clockwise")
                    Spacer()
                    if scanning { ProgressView() }
                }
                .contentShape(Rectangle())
            }
            .disabled(scanning || store.api == nil)
            .foregroundStyle(.primary)
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(message == nil ? theme.secondary : .red)
            }
        }
        // Polls while a scan runs, including one started elsewhere, then refreshes the app's lists.
        .task(id: "\(store.sessionID):\(scanning)") { await follow() }
    }

    private var detail: String? {
        if let message { return message }
        guard let status else { return nil }
        let count = status.count.map { $0.formatted() }
        if status.scanning { return count.map { "Scanning… \($0) items so far" } ?? "Scanning…" }
        guard let date = status.lastScanDate else { return nil }
        return "Last scanned \(date.formatted(.relative(presentation: .named)))"
    }

    private func start(full: Bool) {
        guard let api = store.api else { return }
        starting = true
        message = nil
        Task {
            defer { starting = false }
            do {
                let value = try await api.startScan(full: full)
                guard store.api === api else { return }
                // The server may report idle for a moment before the scan begins.
                status = ScanStatus(scanning: true, count: value.count, lastScan: value.lastScan)
            } catch GevunError.forbidden {
                message = "Only Navidrome admins can scan the library."
            } catch {
                if store.api === api { message = friendlyError(error) }
            }
        }
    }

    private func follow() async {
        guard let api = store.api else { return }
        var wasScanning = status?.scanning == true
        while !Task.isCancelled {
            guard let value = try? await api.scanStatus(), store.api === api, !Task.isCancelled else { return }
            status = value
            if wasScanning && !value.scanning {
                store.reloadLibrary()
                return
            }
            wasScanning = value.scanning
            guard value.scanning else { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}
