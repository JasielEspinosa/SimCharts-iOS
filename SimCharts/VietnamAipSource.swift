import Foundation

/// Viet Nam eAIP (Viet Nam Air Traffic Management, free and public, aim.vatm.vn): the AD 2 page of an airport
/// has a chart table (AD 2.24) whose rows link each chart as a PDF served from /graphics/<id> (no file extension).
enum VietnamAipSource {
    static let site = "https://aim.vatm.vn/images/stories/vnaic.vn/SanPhamDichVu/AIPVietNam/AIP/"

    private static let currentIssue = Rx(
        "Currently Effective Issue.*?<a\\s+href=\"([^\"]+?)/html/index-en-GB\\.html\"[^>]*>([^<]+)</a>",
        ignoreCase: true, dotAll: true)

    // <td><p>Chart title</p></td><td> ... <a href="../../graphics/10329">AD 2-VVNB-7-1</a>
    // Possessive quantifiers keep the matcher iterative (no deep recursion on long pages).
    private static let row = Rx(
        #"<p[^>]*>((?:[^<]++|<(?!/?p[\s>])[^>]*+>)*+)</p>\s*</td>\s*<td[^>]*>\s*(?:<[^>]+>\s*)*<a\s+href="([^"]*?graphics/\d+)"[^>]*>([^<]*)</a>"#,
        ignoreCase: true, dotAll: true)
    private static let tags = Rx("<[^>]+>")
    private static let icaoDash = Rx(#"\s*-\s*ICAO\b"#, ignoreCase: true)
    private static let sidHead = Rx(#"^Standard Departure Charts?\s*-\s*Instrument\s*\(SID\)"#, ignoreCase: true)
    private static let starHead = Rx(#"^Standard Arrival Charts?\s*-\s*Instrument\s*\(STAR\)"#, ignoreCase: true)
    private static let typeDash = Rx(#"^(SID|STAR)\s*-\s*"#)
    private static let approachHead = Rx(#"^Instrument Approach Chart\s*:?\s*"#, ignoreCase: true)

    /// The currently effective package folder ("2026-10-29-AIRAC") and effective date, from the history page.
    static func parseCurrentIssue(_ historyHtml: String) -> (pkg: String, effective: String)? {
        guard let m = currentIssue.first(historyHtml) else { return nil }
        return (Http.htmlDecode(m.group(1)).trimmingChars("/"), Http.htmlDecode(m.group(2)).trimmed)
    }

    static func find(_ icaoIn: String) async throws -> AirportResult {
        let icao = icaoIn.uppercased()
        return try await wrapNetwork("\(icao): could not reach the Viet Nam AIM site") {
            guard let issue = parseCurrentIssue(try await Http.getString(site + "history-en-GB.html")) else {
                throw ChartSourceError("\(icao): could not work out the current Viet Nam eAIP edition.")
            }
            let pageURL = "\(site)\(issue.pkg)/html/eAIP/VV-AD-2.\(icao)-en-GB.html"
            guard let html = try await Http.getStringOrNil(pageURL) else {
                throw ChartSourceError("\(icao): not found in the Viet Nam eAIP.")
            }
            let charts = parseAdPage(html, pageURL: pageURL)
            if charts.isEmpty { throw ChartSourceError("\(icao): the Viet Nam eAIP lists no charts for this airport.") }
            return AirportResult(icao: icao, airportName: nil, sourceName: "Viet Nam eAIP \(issue.pkg) (effective \(issue.effective))", charts: charts)
        }
    }

    private struct Found {
        let number: String
        let code: String
        let name: String
        let url: String
    }

    /// Chart rows of an AD 2 page, each link once, skipping rows the current amendment deleted.
    static func parseAdPage(_ html: String, pageURL: String) -> [ChartFile] {
        let ns = NSString(string: html)
        var found: [Found] = []
        var seen = Set<String>()

        for m in row.all(html) {
            // A row the amendment deletes carries "...Deleted..." on its <tr>.
            let hrefStart = m.groupRange(2).location
            if hrefStart != NSNotFound && hrefStart > 0 {
                let tr = ns.range(of: "<tr", options: [.caseInsensitive, .backwards], range: NSRange(location: 0, length: hrefStart)).location
                if tr != NSNotFound {
                    let end = ns.range(of: ">", options: [], range: NSRange(location: tr, length: ns.length - tr)).location
                    if end != NSNotFound && end > tr {
                        let tag = ns.substring(with: NSRange(location: tr, length: end - tr))
                        if tag.containsCI("Deleted") { continue }
                    }
                }
            }

            let url = Http.resolveEncoded(pageURL, Http.htmlDecode(m.group(2)))
            if !seen.insert(url).inserted { continue }

            let title = clean(m.group(1))
            if title.isEmpty { continue }
            let (code, name) = describe(title)
            found.append(Found(number: clean(m.group(3)), code: code, name: name, url: url))
        }

        var counts: [String: Int] = [:]
        for f in found { counts["\(f.code)\u{1}\(f.name)", default: 0] += 1 }
        return found.map { f in
            let dupe = (counts["\(f.code)\u{1}\(f.name)"] ?? 0) > 1
            let name = dupe && !f.number.isEmpty ? "\(f.name) (\(f.number))" : f.name
            return ChartFile(code: f.code, name: name, url: f.url)
        }
    }

    private static func clean(_ html: String) -> String {
        Http.htmlDecode(tags.replacing(html, with: " "))
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .collapsedSpaces
    }

    /// Chart type and a short file name from the table title.
    static func describe(_ title: String) -> (code: String, name: String) {
        let t = title.uppercased()
        let code: String
        if t.contains("STANDARD DEPARTURE") {
            code = "SID"
        } else if t.contains("STANDARD ARRIVAL") {
            code = "STAR"
        } else if t.contains("INSTRUMENT APPROACH") || t.contains("VISUAL APPROACH") {
            code = "IAP"
        } else if t.contains("OBSTACLE CHART") {
            code = "AOC"
        } else if t.contains("TERRAIN") {
            code = "PATC"
        } else if t.contains("SURVEILLANCE MINIMUM") {
            code = "SMAC"
        } else if t.hasPrefix("AREA CHART") {
            code = "AREA"
        } else {
            code = "APT" // aerodrome, parking/docking, ground movement, operating minima, stands, bird chart
        }
        // "Standard Departure Chart - Instrument (SID) - ICAO - RWY 11L/R: X" -> "SID RWY 11L/R: X"
        var name = icaoDash.replacing(title, with: "")
        name = sidHead.replacing(name, with: "SID")
        name = starHead.replacing(name, with: "STAR")
        name = typeDash.replacing(name, with: "$1 ")
        name = approachHead.replacing(name, with: "Instrument Approach ")
        name = name.trimmed.trimmingTrailing(CharacterSet(charactersIn: "-:")).trimmed
        return (code, name)
    }
}
