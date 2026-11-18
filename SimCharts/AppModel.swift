import SwiftUI
import UIKit

struct TreeRow: Identifiable {
    let node: TreeNode
    let depth: Int
    let open: Bool
    var id: String { node.key }
}

struct OpenFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

@MainActor
final class AppModel: ObservableObject {
    private let faa = FaaDtppSource(cacheDir: ChartStorage.cacheDir)
    private let settingsKey = "simcharts.settings.v1"

    @Published var settings: AppSettings {
        didSet { saveSettings() }
    }

    @Published var nodes: [TreeNode] = [] {
        didSet { recompute() }
    }
    @Published var expanded: Set<String> = [] {
        didSet { recompute() }
    }
    @Published var selectedKey: String?

    /// Text typed in the "Search charts" box; the list shows only matching charts while it is not blank.
    @Published var query = "" {
        didSet { queryChanged() }
    }
    /// The part of `query` the list is actually filtered by: it follows `query` 250 ms after typing pauses, or at once when blank.
    @Published var appliedQuery = "" {
        didSet { recompute() }
    }

    @Published private(set) var rows: [TreeRow] = []
    @Published private(set) var isSearching = false
    @Published private(set) var matchCount = 0

    @Published var status = "Ready"
    @Published var running = false
    @Published var progressDone = 0
    @Published var progressTotal = 0

    /// Airports waiting for the "select which charts" sheet, or nil.
    @Published var selection: [AirportResult]?
    /// Messages to show after a run (unknown codes, missing sources...).
    @Published var problems: [String] = []
    /// A PDF to show in the viewer.
    @Published var openFile: OpenFile?

    private var job: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var pending: CheckedContinuation<[AirportResult]?, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = AppSettings()
        }
        refreshTree()
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    // MARK: tree

    func refreshTree() {
        let root = ChartStorage.root
        Task {
            let scanned = await Task.detached(priority: .userInitiated) { ChartStorage.scan(root) }.value
            self.nodes = scanned
        }
    }

    private func queryChanged() {
        debounce?.cancel()
        if query.trimmed.isEmpty {
            // Emptying or clearing the box filters at once.
            appliedQuery = ""
            return
        }
        debounce = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !Task.isCancelled { self.appliedQuery = self.query }
        }
    }

    private func recompute() {
        let searching = !appliedQuery.trimmed.isEmpty
        let shown = searching ? filterTree(nodes, appliedQuery) : nodes
        let open = searching ? folderKeys(shown) : expanded

        var out: [TreeRow] = []
        func walk(_ list: [TreeNode], _ depth: Int) {
            for n in list {
                let isOpen = !n.isFile && open.contains(n.key)
                out.append(TreeRow(node: n, depth: depth, open: isOpen))
                if isOpen { walk(n.children, depth + 1) }
            }
        }
        walk(shown, 0)

        rows = out
        isSearching = searching
        matchCount = searching ? countFiles(shown) : 0
    }

    func toggleExpanded(_ key: String) {
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
    }

    func select(_ key: String) {
        selectedKey = key
    }

    private func find(_ list: [TreeNode], _ key: String) -> TreeNode? {
        for n in list {
            if n.key == key { return n }
            if let hit = find(n.children, key) { return hit }
        }
        return nil
    }

    /// Expands one folder and all of its subfolders (never the whole tree).
    func expandFolder(_ node: TreeNode) {
        if node.isFile { return }
        expanded.formUnion(folderKeys([node]))
        selectedKey = node.key
    }

    func expandSelected() {
        if let key = selectedKey, let node = find(nodes, key), !node.isFile {
            expandFolder(node)
            status = "Expanded \(node.name)."
        } else {
            status = "Select a folder first, then press Expand Selected."
        }
    }

    func collapseAll() {
        expanded = []
    }

    /// Deletes a folder (and everything in it) from the charts folder. The UI asks for confirmation first.
    func deleteFolder(_ node: TreeNode) {
        if node.isFile { return }
        if running {
            status = "Wait for the download to finish before deleting."
            return
        }
        let url = node.url
        Task {
            let ok = await Task.detached(priority: .userInitiated) { ChartStorage.delete(url) }.value
            if ok {
                let key = node.key
                expanded = expanded.filter { $0 != key && !$0.hasPrefix(key + "/") }
                if let sel = selectedKey, sel == key || sel.hasPrefix(key + "/") { selectedKey = nil }
                status = "Deleted \(node.name)."
            } else {
                problems = ["Could not delete the folder \"\(node.name)\"."]
            }
            refreshTree()
        }
    }

    func clearProblems() {
        problems = []
    }

    // MARK: download

    func confirmSelection(_ chosenIds: Set<String>) {
        guard let all = selection else { return }
        let filtered = all.map { apt -> AirportResult in
            var copy = apt
            copy.charts = apt.charts.filter { chosenIds.contains("\(apt.icao)|\($0.url)") }
            return copy
        }.filter { !$0.charts.isEmpty }
        let cont = pending
        pending = nil
        cont?.resume(returning: filtered)
    }

    func cancelSelection() {
        let cont = pending
        pending = nil
        cont?.resume(returning: nil)
    }

    func startDownload(_ input: String) {
        if running {
            job?.cancel()
            status = "Cancelling..."
            return
        }
        let parsed = IcaoPrefixes.parseCodes(input)
        if parsed.valid.isEmpty {
            status = parsed.invalid.isEmpty
                ? "Enter one or more ICAO codes first."
                : "Not a valid ICAO code: \(parsed.invalid.joined(separator: ", "))"
            return
        }

        running = true
        status = "Starting..."
        progressDone = 0
        progressTotal = 0
        // iOS pauses a backgrounded app, so keep the screen on while charts download.
        UIApplication.shared.isIdleTimerDisabled = true

        let s = settings
        job = Task {
            await self.runDownload(codes: parsed.valid, invalid: parsed.invalid, settings: s)
        }
    }

    private func runDownload(codes: [String], invalid: [String], settings s: AppSettings) async {
        var probs = invalid.map { "\($0): not a valid ICAO code." }
        let setStatus: (String) -> Void = { [weak self] msg in
            Task { @MainActor in self?.status = msg }
        }
        let setProgress: (Int, Int) -> Void = { [weak self] done, total in
            Task { @MainActor in
                self?.progressDone = done
                self?.progressTotal = total
            }
        }

        do {
            var found: [AirportResult] = []
            for code in codes {
                try Task.checkCancellation()
                status = "Looking up \(code)..."
                do {
                    found.append(try await ChartResolver.resolve(code, settings: s, faa: faa, log: setStatus))
                } catch let e as ChartSourceError {
                    probs.append(e.message)
                }
            }

            var toDownload = found
            if !found.isEmpty && s.selectWhichCharts {
                let chosen: [AirportResult]? = await withCheckedContinuation { (cont: CheckedContinuation<[AirportResult]?, Never>) in
                    self.pending = cont
                    self.selection = found
                }
                selection = nil
                pending = nil
                toDownload = chosen ?? []
                if toDownload.isEmpty { status = "Nothing selected." }
            }

            if !toDownload.isEmpty {
                let summary = try await ChartDownloader.download(
                    root: ChartStorage.root, airports: toDownload, settings: s,
                    log: setStatus, progress: setProgress)
                refreshTree()
                if s.openAfterDownload, let first = summary.firstFile { openFile = OpenFile(url: first) }
                if summary.failed > 0 { probs.append("\(summary.failed) file(s) failed to download.") }
            } else if probs.isEmpty && status != "Nothing selected." {
                status = "Nothing to download."
            }
        } catch is CancellationError {
            status = "Cancelled."
            refreshTree()
        } catch {
            if Task.isCancelled {
                status = "Cancelled."
                refreshTree()
            } else {
                probs.append(error.localizedDescription)
            }
        }

        running = false
        progressDone = 0
        progressTotal = 0
        selection = nil
        pending = nil
        UIApplication.shared.isIdleTimerDisabled = false
        if !probs.isEmpty {
            status = probs[0]
            problems = probs
        }
    }
}
