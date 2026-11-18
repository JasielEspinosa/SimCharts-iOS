import Foundation

/// Bhutan AIP (Department of Air Transport, free and public, doat.gov.bt/aip): AD 2.1 of every aerodrome (Paro VQPR,
/// Gelephu VQGP, Bumthang VQBT, Yonphula VQTY) is one PDF holding the aerodrome section (AD 2).
enum BhutanDoatSource {
    static let site = "https://www.doat.gov.bt/aip/"

    // <a href="http://www.doat.gov.bt/wp-content/uploads/2026/05/AD2_1-Aerodromes-VQPR.pdf?ver=1793762964">
    private static let adPdf = Rx(
        #"href\s*=\s*"([^"]*?AD2_1-Aerodromes?-?\s*([A-Z]{4})\.pdf[^"]*)""#,
        ignoreCase: true)

    /// ICAO -> PDF address for every aerodrome on the AIP page (first link wins, query string dropped, https),
    /// plus the codes in page order.
    static func parseAerodromes(_ html: String, pageURL: String) -> (order: [String], urls: [String: String]) {
        var order: [String] = []
        var urls: [String: String] = [:]
        for m in adPdf.all(html) {
            let icao = m.group(2).uppercased()
            if urls[icao] != nil { continue }
            var href = Http.htmlDecode(m.group(1))
            if let cut = href.firstIndex(where: { $0 == "?" || $0 == "#" }) { href = String(href[..<cut]) }
            var url = Http.resolveEncoded(pageURL, href)
            if url.hasPrefix("http://") { url = "https://" + url.dropFirst(7) }
            urls[icao] = url
            order.append(icao)
        }
        return (order, urls)
    }

    static func find(_ icaoIn: String) async throws -> AirportResult {
        let icao = icaoIn.uppercased()
        return try await wrapNetwork("\(icao): could not reach the Bhutan AIP site") {
            let all = parseAerodromes(try await Http.getString(site), pageURL: site)
            guard let url = all.urls[icao] else {
                let listed = all.order.isEmpty ? "" : " Airports listed: \(all.order.joined(separator: ", "))."
                throw ChartSourceError("\(icao): not found in the Bhutan AIP.\(listed)")
            }
            return AirportResult(
                icao: icao, airportName: nil,
                sourceName: "Bhutan AIP (doat.gov.bt) - one PDF with the airport's AD 2 section",
                charts: [ChartFile(code: "AD2", name: "Aerodrome section (AD 2)", url: url)])
        }
    }
}
