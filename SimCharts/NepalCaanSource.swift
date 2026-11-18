import Foundation

/// Nepal eAIP (Civil Aviation Authority of Nepal, free and public, e-aip.caanepal.gov.np): the AD 2 list links one PDF
/// per aerodrome (Kathmandu VNKT, Pokhara VNPK, ...) holding its AD 2 aerodrome section. VNKT is about 70 MB.
/// The site sends no intermediate certificate; iOS fetches the missing one itself, so nothing special is needed here.
enum NepalCaanSource {
    static let site = "https://e-aip.caanepal.gov.np/"
    static let listURL = site + "welcome/listall/1"

    // <a class="trigger" ... href="https://e-aip.caanepal.gov.np/_uploads/_pdf/3be3...pdf" target="_blank">&nbsp&nbsp;VNKT</a>
    private static let adPdf = Rx(
        #"href\s*=\s*"([^"]+?\.pdf)"[^>]*>(?:\s|&nbsp;?)*(V[A-Z]{3})\s*</a>"#,
        ignoreCase: true)

    /// ICAO -> PDF address for the aerodromes listed under "AD 2 AERODROME" (first link wins), plus the codes in page order.
    static func parseAerodromes(_ html: String, pageURL: String) -> (order: [String], urls: [String: String]) {
        let ns = NSString(string: html)
        var section = html
        let start = ns.range(of: "AD 2 AERODROME", options: .caseInsensitive)
        if start.location != NSNotFound { section = ns.substring(from: start.location) }
        let sec = NSString(string: section)
        let end = sec.range(of: "AD 3 HELIPORTS", options: .caseInsensitive)
        if end.location != NSNotFound && end.location > 0 { section = sec.substring(to: end.location) }

        var order: [String] = []
        var urls: [String: String] = [:]
        for m in adPdf.all(section) {
            let icao = m.group(2).uppercased()
            if urls[icao] != nil { continue }
            urls[icao] = Http.resolveEncoded(pageURL, Http.htmlDecode(m.group(1)))
            order.append(icao)
        }
        return (order, urls)
    }

    static func find(_ icaoIn: String) async throws -> AirportResult {
        let icao = icaoIn.uppercased()
        return try await wrapNetwork("\(icao): could not reach the Nepal eAIP site") {
            let all = parseAerodromes(try await Http.getString(listURL), pageURL: listURL)
            guard let url = all.urls[icao] else {
                let listed = all.order.isEmpty ? "" : " Airports listed: \(all.order.joined(separator: ", "))."
                throw ChartSourceError("\(icao): not found in the Nepal eAIP.\(listed)")
            }
            let large = icao == "VNKT" ? " (large file, about 70 MB)" : ""
            return AirportResult(
                icao: icao, airportName: nil,
                sourceName: "Nepal eAIP (CAAN) - one PDF with the airport's AD 2 section\(large)",
                charts: [ChartFile(code: "AD2", name: "Aerodrome section (AD 2)", url: url)])
        }
    }
}
