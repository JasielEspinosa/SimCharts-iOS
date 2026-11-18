import Foundation

/// Korea eAIP (Ministry of Land, Infrastructure and Transport AIM, free and public, aim.koca.go.kr): each AD 2 page
/// links the aerodrome, SID, STAR and approach charts as PDFs. Links the current amendment deleted are skipped.
enum KoreaAimSource {
    static let site = "https://aim.koca.go.kr/eaipPub/Package/"

    private static let currentIssue = Rx(
        "Currently Effective Issue.*?<a\\s+href=\"([^\"]+?)/html/index-en-GB\\.html\"[^>]*>([^<]+)</a>",
        ignoreCase: true, dotAll: true)
    private static let pdfAnchor = Rx(
        "<a\\b[^>]*href\\s*=\\s*\"([^\"]+?\\.pdf)\"[^>]*>(.*?)</a>",
        ignoreCase: true, dotAll: true)
    private static let tags = Rx("<[^>]+>")
    private static let numberPrefix = Rx("^\\(([\\d-]+)\\)")
    private static let numberPrefixStrip = Rx("^\\([\\d-]+\\)\\s*")

    /// The currently effective package folder ("2026-11-12") and effective date, from the history page.
    static func parseCurrentIssue(_ historyHtml: String) -> (pkg: String, effective: String)? {
        guard let m = currentIssue.first(historyHtml) else { return nil }
        return (Http.htmlDecode(m.group(1)).trimmingChars("/"), Http.htmlDecode(m.group(2)).trimmed)
    }

    static func find(_ icaoIn: String) async throws -> AirportResult {
        let icao = icaoIn.uppercased()
        return try await wrapNetwork("\(icao): could not reach the Korea AIM site") {
            guard let issue = parseCurrentIssue(try await Http.getString(site + "history-en-GB.html")) else {
                throw ChartSourceError("\(icao): could not work out the current Korea eAIP edition.")
            }
            let pageURL = "\(site)\(issue.pkg)/html/eAIP/KR-AD-2.\(icao)-en-GB.html"
            guard let html = try await Http.getStringOrNil(pageURL) else {
                throw ChartSourceError("\(icao): not found in the Korea eAIP.")
            }
            let charts = parseAdPage(html, icao: icao, pageURL: pageURL)
            if charts.isEmpty { throw ChartSourceError("\(icao): the Korea eAIP lists no charts for this airport.") }
            return AirportResult(icao: icao, airportName: nil, sourceName: "Korea eAIP \(issue.pkg) (effective \(issue.effective))", charts: charts)
        }
    }

    private struct Found {
        let number: String
        let code: String
        let name: String
        let url: String
    }

    /// Chart PDFs of an AD 2 page, each once, skipping links the current amendment deleted.
    static func parseAdPage(_ html: String, icao icaoIn: String, pageURL: String) -> [ChartFile] {
        let folder = "/pdf/AD/\(icaoIn.uppercased())/"
        var found: [Found] = []
        var seen = Set<String>()

        for m in pdfAnchor.all(html) {
            let href = Http.htmlDecode(m.group(1))
            if !href.containsCI(folder) { continue }

            // The nearest div is the inner "graphic-box"; the class sits on the enclosing "Figure-..." div.
            let start = m.range.location
            let from = max(0, start - 600)
            let before = NSString(string: NSString(string: html).substring(with: NSRange(location: from, length: start - from)))
            let clsRange = before.range(of: "<div class=\"Figure", options: [.caseInsensitive, .backwards])
            if clsRange.location != NSNotFound {
                let cls = clsRange.location
                let tail = NSRange(location: cls, length: before.length - cls)
                let closed = before.range(of: "</a>", options: .caseInsensitive, range: tail).location != NSNotFound
                if !closed && before.length > cls + 12 {
                    let valueRange = NSRange(location: cls + 12, length: before.length - (cls + 12))
                    let quote = before.range(of: "\"", options: [], range: valueRange)
                    if quote.location != NSNotFound && quote.location > cls {
                        let cssClass = before.substring(with: NSRange(location: cls + 12, length: quote.location - (cls + 12)))
                        if cssClass.containsCI("Deleted") { continue }
                    }
                }
            }

            let url = Http.resolveEncoded(pageURL, href).replacingOccurrences(of: "http://", with: "https://")
            if !seen.insert(url).inserted { continue }

            let stem = Http.lastSegment(url).removingSuffix(".pdf")
            let number = numberPrefix.first(stem)?.group(1) ?? ""
            var title = Http.htmlDecode(tags.replacing(m.group(2), with: " ")).collapsedSpaces
            if title.isEmpty { title = numberPrefixStrip.replacing(stem, with: "") }
            let (code, name) = describe(title)
            found.append(Found(number: number, code: code, name: name, url: url))
        }

        var counts: [String: Int] = [:]
        for f in found { counts["\(f.code)\u{1}\(f.name)", default: 0] += 1 }
        return found.map { f in
            let dupe = (counts["\(f.code)\u{1}\(f.name)"] ?? 0) > 1
            let name = dupe && !f.number.isEmpty ? "\(f.name) (\(f.number))" : f.name
            return ChartFile(code: f.code, name: name, url: f.url)
        }
    }

    static func describe(_ title: String) -> (code: String, name: String) {
        let t = title.trimmed.uppercased()
        if t == "SID" { return ("SID", "Standard Instrument Departures") }
        if t == "STAR" { return ("STAR", "Standard Arrival Routes") }
        if t.contains("AREA CHART") { return ("AREA", nice(title)) }
        if t.contains("OBSTACLE CHART") { return ("AOC", nice(title)) }
        if t.contains("TERRAIN") { return ("PATC", nice(title)) }
        if t.contains("SURVEILLANCE MINIMUM") { return ("SMAC", nice(title)) }
        if t.contains("INSTR APCH") { return ("IAP", "Instrument Approach Charts") }
        if t.contains("VISUAL APCH") { return ("IAP", "Visual Approach Charts") }
        if t == "AD CHART" { return ("APT", "Aerodrome Chart") }
        if t.contains("PARKING") || t.contains("GROUND MOVEMENT") || t.contains("DOCKING") { return ("APT", nice(title)) }
        return ("PDF", nice(title))
    }

    private static func nice(_ s: String) -> String {
        Http.titleCase(s)
            .replacingOccurrences(of: "Ad ", with: "Aerodrome ")
            .replacingOccurrences(of: "Apch", with: "Approach")
            .replacingOccurrences(of: "Atc ", with: "ATC ")
            .replacingOccurrences(of: "Precision App ", with: "Precision Approach ")
    }
}
