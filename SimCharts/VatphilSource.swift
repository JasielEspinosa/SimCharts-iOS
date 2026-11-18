import Foundation

/// Philippine AIP charts from VATPHIL (vatphil.com, VATSIM Philippines vACC): free, no login, flight-sim use only.
/// The official eAIP (ais.caap.gov.ph) needs a paid subscription.
enum VatphilSource {
    static let baseURL = "https://vatphil.com/"
    static let sourceName = "VATPHIL (Philippine AIP)"

    private static let header = Rx(#"<h3[^>]*>\s*([^<]+?)\s*</h3>"#, ignoreCase: true)
    private static let link = Rx(#"viewchart\.php\?id=(\d+)[^>]*>\s*([^<]+?)\s*</a>"#, ignoreCase: true)

    static func find(_ icaoIn: String) async throws -> AirportResult {
        let icao = icaoIn.uppercased()
        let html = try await wrapNetwork("\(icao): could not reach VATPHIL") {
            try await Http.getString("\(baseURL)charts?icao=\(icao)")
        }
        let charts = parse(html)
        if charts.isEmpty { throw ChartSourceError("\(icao): VATPHIL has no charts for this airport.") }
        return AirportResult(icao: icao, airportName: nil, sourceName: sourceName, charts: charts)
    }

    /// Parses the chart table: one column per chart type, one link per chart.
    static func parse(_ html: String) -> [ChartFile] {
        let headers = header.all(html)
        guard let lastHeader = headers.last else { return [] }
        let types = headers.map { typeCode($0.group(1)) }

        // Everything after the last header cell is the data row: one <td> per column.
        let ns = NSString(string: html)
        let start = lastHeader.range.location + lastHeader.range.length
        var rest = ns.substring(from: start)
        if let end = rest.range(of: "</table>", options: .caseInsensitive) {
            rest = String(rest[..<end.lowerBound])
        }

        let cells = Array(rest.components(separatedBy: "<td").dropFirst())
        var seen = Set<String>()
        var result: [ChartFile] = []
        for (i, cell) in cells.enumerated() {
            let code = i < types.count ? types[i] : "PDF"
            for m in link.all(cell) {
                let id = m.group(1)
                let name = Http.htmlDecode(m.group(2)).collapsedSpaces
                if name.isEmpty || !seen.insert(id).inserted { continue }
                result.append(ChartFile(code: code, name: name, url: "\(baseURL)viewchart.php?id=\(id)"))
            }
        }
        return result
    }

    private static func typeCode(_ headerText: String) -> String {
        let h = headerText.lowercased()
        if h.contains("area") { return "AREA" }
        if h.contains("airport") || h.contains("aerodrome") { return "APT" }
        if h.contains("approach") { return "IAP" }
        if h.contains("departure") { return "SID" }
        if h.contains("arrival") { return "STAR" }
        if h.contains("circuit") { return "CIRCUIT" }
        return "PDF"
    }
}
