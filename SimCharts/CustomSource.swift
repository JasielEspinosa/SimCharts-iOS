import Foundation

enum CustomSource {
    private static let pdfHref = Rx(
        "href\\s*=\\s*[\"']([^\"']+?\\.pdf(?:\\?[^\"']*)?)[\"']",
        ignoreCase: true)

    static func expandTemplate(_ template: String, icao: String) -> String {
        template
            .replacingOccurrences(of: "{ICAO}", with: icao.uppercased())
            .replacingOccurrences(of: "{icao}", with: icao.lowercased())
    }

    private static func isWebURL(_ s: String) -> Bool {
        s.startsWithCI("http://") || s.startsWithCI("https://")
    }

    /// Extracts absolute http(s) .pdf links from HTML, de-duplicated, in page order.
    static func extractPdfLinks(_ html: String, page: String) -> [String] {
        var seen = Set<String>()
        var list: [String] = []
        for m in pdfHref.all(html) {
            let href = m.group(1).replacingOccurrences(of: "&amp;", with: "&")
            let abs = Http.resolveEncoded(page, href)
            if isWebURL(abs) && seen.insert(abs).inserted { list.append(abs) }
        }
        return list
    }

    private static func nameOf(_ url: String) -> String {
        let path = url.components(separatedBy: "?").first ?? url
        let last = Http.lastSegment(path)
        if let dot = last.lastIndex(of: ".") { return String(last[..<dot]) }
        return last
    }

    static func fetch(_ res: CustomResource, icao: String) async throws -> AirportResult {
        let url = expandTemplate(res.urlTemplate, icao: icao).trimmed.replacingOccurrences(of: " ", with: "%20")
        guard isWebURL(url), URL(string: url) != nil else {
            throw ChartSourceError("Custom resource '\(res.label)' has an invalid URL: \(url)")
        }

        var charts: [ChartFile] = []
        if res.mode == .DirectPdf {
            let n = nameOf(url)
            charts.append(ChartFile(code: "PDF", name: n.trimmed.isEmpty ? icao : n, url: url))
        } else {
            let html: String
            do {
                html = try await Http.getString(url)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw ChartSourceError("Could not read \(url): \(error.localizedDescription)")
            }
            for link in extractPdfLinks(html, page: url) {
                charts.append(ChartFile(code: "PDF", name: nameOf(link), url: link))
            }
        }

        return AirportResult(
            icao: icao.uppercased(),
            airportName: nil,
            sourceName: res.label.trimmed.isEmpty ? "Custom resource" : res.label,
            charts: charts
        )
    }
}
