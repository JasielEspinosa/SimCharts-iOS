import Foundation

/// One published AIP Hong Kong amendment, from https://www.ais.gov.hk/ais.json.
struct HkEdition {
    let no: String
    /// "yyyy-MM-dd"
    let effective: String
    let published: String
}

/// Hong Kong eAIP (Civil Aviation Department, free and public): VHHH charts, plus the SID/STAR charts it publishes
/// for Macao (VMMC). The rest of the Macao AIP is on aacm.gov.mo behind a terms-of-use tick box.
enum HkAisSource {
    static let site = "https://www.ais.gov.hk/"

    private static let row = Rx("<tr\\b[^>]*>(.*?)</tr>", ignoreCase: true, dotAll: true)
    private static let pdfHref = Rx("href\\s*=\\s*\"([^\"]+?\\.pdf)\"", ignoreCase: true)
    private static let anchor = Rx("<a\\b[^>]*>.*?</a>", ignoreCase: true, dotAll: true)
    private static let tags = Rx("<[^>]+>")
    private static let icaoSuffix = Rx("\\s*[-\u{2013}]\\s*ICAO\\s*$")

    // MARK: editions

    static func parseEditions(_ json: String) -> [HkEdition] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["amdt"] as? [[String: Any]] else { return [] }
        var list: [HkEdition] = []
        for a in arr {
            guard let eff = a["effDate"] as? String, eff.count >= 10 else { continue }
            list.append(HkEdition(
                no: "\(a["no"] ?? "")",
                effective: String(eff.prefix(10)),
                published: (a["pubDate"] as? String) ?? ""
            ))
        }
        return list
    }

    /// The site keeps every edition under the folder of the newest publication date:
    /// eaip_<newest pubDate>/<effDate>-000000/. Returns editions already in force, newest first.
    static func inForce(_ all: [HkEdition], today: String) -> [(edition: HkEdition, baseURL: String)] {
        guard let newest = all.map({ $0.published }).max() else { return [] }
        let newestPub = newest.replacingOccurrences(of: "-", with: "")
        return all.filter { $0.effective <= today }
            .sorted { $0.effective > $1.effective }
            .map { ($0, "\(site)eaip_\(newestPub)/\($0.effective)-000000/") }
    }

    private static func todayUTC() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: lookup

    static func find(_ icaoIn: String) async throws -> AirportResult {
        let icao = icaoIn.uppercased()
        return try await wrapNetwork("\(icao): could not reach the Hong Kong AIS site") {
            let json = try await Http.getString(site + "ais.json")
            let editions = inForce(parseEditions(json), today: todayUTC())
            if editions.isEmpty {
                throw ChartSourceError("\(icao): could not work out the current Hong Kong AIP edition.")
            }
            for (edition, baseURL) in editions.prefix(2) {
                let pageURL = "\(baseURL)html/eAIP/VH-AD-2-\(icao)-en-US.html"
                guard let html = try await Http.getStringOrNil(pageURL) else { continue }
                let charts = parseAdPage(html, icao: icao, pageURL: pageURL)
                if charts.isEmpty { continue }
                let note = icao == "VMMC" ? " - SID/STAR for Macao only" : ""
                return AirportResult(icao: icao, airportName: nil, sourceName: "Hong Kong eAIP AMDT \(edition.no)\(note)", charts: charts)
            }
            throw ChartSourceError("\(icao): not found in the Hong Kong eAIP.")
        }
    }

    // MARK: parsing

    /// Charts of an AD 2 page: each PDF once, titled from its table row, typed from its file name.
    static func parseAdPage(_ html: String, icao icaoIn: String, pageURL: String) -> [ChartFile] {
        let icao = icaoIn.uppercased()
        let filePrefix = "VH-AD-2-\(icao)-"
        let marker = "AD 2-\(icao)-"
        var order: [String] = []
        var urls: [String: String] = [:]
        var titles: [String: (rank: Int, title: String)] = [:]

        for r in row.all(html) {
            let body = r.group(1)
            let pdfs = pdfHref.all(body)
            if pdfs.isEmpty { continue }

            let text = clean(tags.replacing(anchor.replacing(body, with: " "), with: " "))
            let (rank, title) = rowTitle(text, marker: marker)
            for m in pdfs {
                let href = Http.htmlDecode(m.group(1))
                var stem = href.split(separator: "/").last.map(String.init) ?? href
                if stem.lowercased().hasSuffix(".pdf") { stem = String(stem.dropLast(4)) }
                if !stem.startsWithCI(filePrefix) { continue }
                if urls[stem] == nil {
                    order.append(stem)
                    urls[stem] = Http.resolveEncoded(pageURL, href)
                }
                if let cur = titles[stem] {
                    if rank > cur.rank || (rank == cur.rank && rank > 0 && title.count < cur.title.count) {
                        titles[stem] = (rank, title)
                    }
                } else {
                    titles[stem] = (rank, title)
                }
            }
        }

        return order.map { stem in
            let rest = String(stem.dropFirst(filePrefix.count))
            let name: String
            if let t = titles[stem], t.rank > 0 {
                name = t.title
            } else {
                name = rest.replacingOccurrences(of: "-", with: " ")
            }
            return ChartFile(code: typeCode(rest), name: name, url: urls[stem] ?? "")
        }
    }

    private static func rowTitle(_ rowText: String, marker: String) -> (Int, String) {
        let trimSet = " -\u{2013}*"
        if let r = rowText.range(of: marker, options: .caseInsensitive) {
            let idx = rowText.distance(from: rowText.startIndex, to: r.lowerBound)
            if idx > 0 {
                let head = String(rowText[..<r.lowerBound])
                let t = icaoSuffix.replacing(head, with: "").trimmingChars(trimSet)
                if !t.isEmpty && t.count <= 110 { return (2, t) }
            }
        }
        if let r = rowText.range(of: "See for details", options: .caseInsensitive) {
            let idx = rowText.distance(from: rowText.startIndex, to: r.lowerBound)
            if idx >= 1 && idx <= 89 {
                return (1, String(rowText[..<r.lowerBound]).trimmingChars(trimSet))
            }
        }
        return (0, "")
    }

    private static func clean(_ s: String) -> String {
        Http.htmlDecode(s).collapsedSpaces
    }

    private static func typeCode(_ rest: String) -> String {
        let first = (rest.split(separator: "-", omittingEmptySubsequences: false).first.map(String.init) ?? rest).uppercased()
        switch first {
        case "IAC": return "IAP"
        case "ADC": return "APT"
        case "AC": return "AREA"
        default: return first
        }
    }
}
