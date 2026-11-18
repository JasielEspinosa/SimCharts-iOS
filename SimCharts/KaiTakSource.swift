import Foundation

/// Kai Tak (VHHX), Hong Kong's airport until it closed in 1998. It is not in the Hong Kong eAIP; the charts come from
/// the frozen community archive on the IVAO East Asia Kai Tak page. They are simulation material only: not current,
/// not official.
enum KaiTakSource {
    static let page = "https://xe.ivao.aero/?p=5811"

    /// Known files on that page, in the order they are offered.
    private static let known: [(file: String, title: String)] = [
        ("procedure_vhhx.pdf", "Kai Tak flight procedures (IVAO legacy)"),
        ("VHHX_AD.pdf", "Aerodrome layout and parking (IVAO 2014)"),
        ("VHHX-v4.pdf", "Community chart pack - light (2020)"),
        ("VHHX-v4D.pdf", "Community chart pack - dark (2020)"),
    ]

    private static let pdfHref = Rx(#"href\s*=\s*"([^"]*?/download/charts/[^"]+?\.pdf)""#, ignoreCase: true)

    /// Chart PDFs linked from the page, each once, with the names of the known files.
    static func parseCharts(_ html: String, pageURL: String) -> [ChartFile] {
        var order: [String] = []
        var found: [String: String] = [:] // file name -> url
        for m in pdfHref.all(html) {
            let url = Http.resolveEncoded(pageURL, Http.htmlDecode(m.group(1)))
            let file = String(url.split(separator: "/").last ?? "")
            if found[file] == nil {
                found[file] = url
                order.append(file)
            }
        }
        var charts: [ChartFile] = []
        for k in known {
            if let url = found.removeValue(forKey: k.file) {
                charts.append(ChartFile(code: "PDF", name: k.title, url: url))
            }
        }
        // Anything new the page adds later still gets downloaded, named from its file name.
        for file in order {
            guard let url = found[file] else { continue }
            let name = file.replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "_", with: " ")
            charts.append(ChartFile(code: "PDF", name: name, url: url))
        }
        return charts
    }

    static func find(_ icaoIn: String) async throws -> AirportResult {
        let icao = icaoIn.uppercased()
        return try await wrapNetwork("\(icao): could not reach the IVAO East Asia site") {
            let charts = parseCharts(try await Http.getString(page), pageURL: page)
            if charts.isEmpty { throw ChartSourceError("\(icao): the IVAO Kai Tak page lists no charts.") }
            return AirportResult(
                icao: icao, airportName: nil,
                sourceName: "IVAO East Asia Kai Tak archive - frozen community charts, not current or official",
                charts: charts)
        }
    }
}
