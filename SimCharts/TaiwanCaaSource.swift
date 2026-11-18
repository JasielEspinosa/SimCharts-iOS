import Foundation

/// Taiwan eAIP (Civil Aeronautical Administration, free and public, ais.caa.gov.tw/eaip): every AD 2 page links the
/// aerodrome, SID, STAR and approach charts as separate PDFs. Only the current edition is used.
enum TaiwanCaaSource {
    static let site = "https://ais.caa.gov.tw/eaip/"

    private static let currentIssue = Rx(
        "Currently Effective Issue.*?<a\\s+href=\"([^\"]+?)[/\\\\]index\\.html\"[^>]*>([^<]+)</a>",
        ignoreCase: true, dotAll: true)
    private static let pdfHref = Rx("href\\s*=\\s*\"([^\"]+?\\.pdf)\"", ignoreCase: true)
    private static let leadingNumber = Rx("^\\d+[-_ ]*")
    private static let starWord = Rx("\\bSTAR\\b|\\bARR\\b")
    private static let sidWord = Rx("\\bSID\\b|\\bDEP\\b")
    private static let iapWord = Rx("\\b(ILS|LOC|LDA|NDB|VOR|RNP|TACAN|RNAV|GLS|APCH)\\b")

    private static var menuFor: String?
    private static var menu = ""

    /// The package folder of the currently effective edition ("AIRAC AIP AMDT 05-26_2026_10_29") and its effective date.
    static func parseCurrentIssue(_ historyHtml: String) -> (folder: String, effective: String)? {
        guard let m = currentIssue.first(historyHtml) else { return nil }
        let folder = Http.htmlDecode(m.group(1)).replacingOccurrences(of: "\\", with: "/").trimmingChars("/")
        return (folder, Http.htmlDecode(m.group(2)).trimmed)
    }

    static func find(_ icaoIn: String) async throws -> AirportResult {
        let icao = icaoIn.uppercased()
        return try await wrapNetwork("\(icao): could not reach the Taiwan eAIP site") {
            guard let issue = parseCurrentIssue(try await Http.getString(site)) else {
                throw ChartSourceError("\(icao): could not work out the current Taiwan eAIP edition.")
            }
            let eaip = Http.resolveEncoded(site, "\(issue.folder)/eAIP/")

            if menuFor != eaip {
                menu = try await Http.getString(Http.resolveEncoded(eaip, "menu.html"))
                menuFor = eaip
            }
            guard let page = findAdPage(menu, icao: icao) else {
                throw ChartSourceError("\(icao): not found in the Taiwan eAIP.")
            }

            let pageURL = Http.resolveEncoded(eaip, page)
            let charts = parseAdPage(try await Http.getString(pageURL), pageURL: pageURL)
            if charts.isEmpty { throw ChartSourceError("\(icao): the Taiwan eAIP lists no charts for this airport.") }
            let amdt = issue.folder.components(separatedBy: "_").first ?? issue.folder
            return AirportResult(
                icao: icao, airportName: nil,
                sourceName: "Taiwan eAIP \(amdt.replacingOccurrences(of: "-", with: "/")) (effective \(issue.effective))",
                charts: charts)
        }
    }

    /// The English AD 2 page for an airport, from the eAIP menu (file name contains spaces and Chinese).
    static func findAdPage(_ menuHtml: String, icao: String) -> String? {
        let esc = NSRegularExpression.escapedPattern(for: icao)
        let pattern = "href=[\"'](RC-AD 2 " + esc + " [^\"'#]*?-en-GB\\.html)#"
        guard let m = Rx(pattern, ignoreCase: true).first(menuHtml) else { return nil }
        return Http.htmlDecode(m.group(1))
    }

    /// Chart PDFs of an AD 2 page (those under Charts/AD), each once, in page order.
    static func parseAdPage(_ html: String, pageURL: String) -> [ChartFile] {
        var charts: [ChartFile] = []
        var seen = Set<String>()
        for m in pdfHref.all(html) {
            let href = Http.htmlDecode(m.group(1)).replacingOccurrences(of: "\\", with: "/")
            if !href.containsCI("/Charts/AD/") { continue }
            let url = Http.resolveEncoded(pageURL, href)
            if !seen.insert(url).inserted { continue }

            let stem = Http.lastSegment(url).removingSuffix(".pdf")
            var name = leadingNumber.replacing(stem, with: "").trimmed
            if name.isEmpty { name = stem }
            charts.append(ChartFile(code: typeCode(name), name: name, url: url))
        }
        return charts
    }

    static func typeCode(_ name: String) -> String {
        let n = name.uppercased()
        if n.hasPrefix("AERONAUTICAL DATA") || n.contains("WP TABLE") { return "DATA" }
        if n.contains("SMAC") || n.contains("SURVEILLANCE MINIMUM") { return "SMAC" }
        if n.contains("OBSTACLE CHART") || n.hasPrefix("AOC") { return "AOC" }
        if n.hasPrefix("PATC") { return "PATC" }
        if ["GMC", "TXI", "AERODROME CHART", "TWY", "TRANSVERSE", "LIGHTING", "PARKING"].contains(where: { n.contains($0) }) { return "APT" }
        if starWord.test(n) { return "STAR" }
        if sidWord.test(n) { return "SID" }
        if iapWord.test(n) { return "IAP" }
        return "PDF"
    }
}
