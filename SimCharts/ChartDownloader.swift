import Foundation

struct DownloadSummary {
    var downloaded = 0
    var skipped = 0
    var failed = 0
    var firstFile: URL?
}

enum ChartDownloader {

    /// Downloads the given airports (already filtered to the wanted charts) into [root].
    static func download(
        root: URL,
        airports: [AirportResult],
        settings: AppSettings,
        log: @escaping (String) -> Void,
        progress: @escaping (Int, Int) -> Void
    ) async throws -> DownloadSummary {
        let total = airports.reduce(0) { $0 + $1.charts.count }
        var done = 0
        var summary = DownloadSummary()
        progress(0, total)

        for (i, apt) in airports.enumerated() {
            try Task.checkCancellation()
            let country = try ChartStorage.ensureDir(root, Naming.countryFolder(apt.icao))
            let dir = try ChartStorage.ensureDir(country, Naming.airportFolder(apt))

            log("\(apt.icao): downloading \(apt.charts.count) chart(s) from \(apt.sourceName)...")
            var used = Set<String>()
            for chart in apt.charts {
                try Task.checkCancellation()
                let fileName = Naming.chartFileName(apt, chart, addIcao: settings.addAirportCodeToFilename, used: &used)
                let dest = dir.appendingPathComponent(fileName)
                do {
                    let wrote = try await fetchToFile(chart.url, dest: dest)
                    if wrote { summary.downloaded += 1 } else { summary.skipped += 1 }
                    if summary.firstFile == nil || chart.code == "APD" { summary.firstFile = dest }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    summary.failed += 1
                    log("  failed: \(fileName) (\(error.localizedDescription))")
                }
                done += 1
                progress(done, total)
            }

            if settings.waitBetweenAirports && i < airports.count - 1 {
                log("Waiting 3 seconds before the next airport...")
                try await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }

        log("Done: \(summary.downloaded) downloaded, \(summary.skipped) already up to date, \(summary.failed) failed.")
        return summary
    }

    /// Returns true when the file was written; false when a file of the same size already exists.
    private static func fetchToFile(_ url: String, dest: URL) async throws -> Bool {
        let fm = FileManager.default
        var existingSize: Int64? = nil
        if let attrs = try? fm.attributesOfItem(atPath: dest.path), let n = attrs[.size] as? NSNumber {
            existingSize = n.int64Value
        }

        // Same size on disk already? A HEAD request tells without downloading the file again.
        if let size = existingSize, size > 0,
           let (_, head) = try? await Http.fetch(url, method: "HEAD"),
           (200..<300).contains(head.statusCode),
           head.expectedContentLength == size {
            return false
        }

        let (tmp, resp) = try await Http.session.download(for: try Http.request(url))
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if !(200..<300).contains(http.statusCode) {
            try? fm.removeItem(at: tmp)
            throw HttpError(status: http.statusCode)
        }
        // Some sites answer 200 with an HTML error page for a bad link: never save that as a PDF.
        if (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased().contains("html") {
            try? fm.removeItem(at: tmp)
            throw ChartSourceError("the server did not return a PDF")
        }
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: tmp, to: dest)
        return true
    }
}
