import Foundation

/// Japan. The official AIP (MLIT SWIM portal) needs a registered account, so it cannot be read without a login.
/// This uses a public, unofficial mirror of the AIP Japan aerodrome charts (nagodede.github.io), which publishes one
/// combined PDF per airport and an index with the AIRAC edition it was built from. It can lag behind the current
/// AIRAC, so the edition date is always shown. For flight simulation only.
enum JapanMirrorSource {
    static let baseURL = "https://nagodede.github.io/aip/japan/documents/"

    private static var info: [String: Any]?

    static func find(_ icaoIn: String) async throws -> AirportResult {
        let icao = icaoIn.uppercased()
        return try await wrapNetwork("\(icao): could not reach the Japan AIP chart mirror") {
            if info == nil {
                let text = try await Http.getString(baseURL + "info.json")
                guard let data = text.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw ChartSourceError("\(icao): the Japan AIP chart mirror index could not be read.")
                }
                info = obj
            }
            let (edition, title) = lookup(info ?? [:], icao: icao)
            if title == nil {
                throw ChartSourceError("\(icao): not in the Japan AIP chart mirror (it covers 127 Japanese airports).")
            }

            var charts: [ChartFile] = []
            for (suffix, name) in [("chart", "AIP Charts"), ("full", "AD 2 Full Section")] {
                let url = "\(baseURL)\(icao)_\(suffix).pdf"
                if await isPdf(url) { charts.append(ChartFile(code: "PDF", name: name, url: url)) }
            }
            if charts.isEmpty {
                throw ChartSourceError("\(icao): the Japan AIP chart mirror has no chart files for this airport.")
            }
            return AirportResult(
                icao: icao, airportName: nil,
                sourceName: "AIP Japan, unofficial mirror (AIRAC effective \(edition); may be out of date)",
                charts: charts)
        }
    }

    /// HEAD request only: checks the file exists without downloading it.
    private static func isPdf(_ url: String) async -> Bool {
        guard let (_, resp) = try? await Http.fetch(url, method: "HEAD") else { return false }
        let type = resp.value(forHTTPHeaderField: "Content-Type") ?? ""
        return (200..<300).contains(resp.statusCode) && type.lowercased().contains("pdf")
    }

    /// Edition date ("2026-03-01") and airport title from the mirror's info.json (title is nil if absent).
    static func lookup(_ root: [String: Any], icao: String) -> (edition: String, title: String?) {
        var edition = "unknown"
        if let eff = root["EffectiveDate"] as? String, eff.count >= 10 { edition = String(eff.prefix(10)) }
        if let list = root["Airports"] as? [[String: Any]] {
            for a in list {
                if let code = a["Icao"] as? String, code.caseInsensitiveCompare(icao) == .orderedSame {
                    return (edition, (a["Title"] as? String) ?? icao)
                }
            }
        }
        return (edition, nil)
    }
}
