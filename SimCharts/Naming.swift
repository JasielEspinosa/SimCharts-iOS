import Foundation

enum Naming {
    private static let invalidChars = Rx(#"[\\/:*?"<>|\u0000-\u001F]"#)

    static func sanitize(_ name: String, maxLength: Int = 120) -> String {
        var s = invalidChars.replacing(name, with: "_").collapsedSpaces
        s = s.trimmingTrailing(CharacterSet(charactersIn: "."))
        if s.count > maxLength { s = String(s.prefix(maxLength)).trimmed }
        return s.isEmpty ? "chart" : s
    }

    static func countryFolder(_ icao: String) -> String {
        sanitize(IcaoPrefixes.countryFolderName(icao))
    }

    static func airportFolder(_ apt: AirportResult) -> String {
        if let n = apt.airportName, !n.trimmed.isEmpty { return "\(apt.icao) - \(sanitize(n))" }
        return apt.icao
    }

    static func chartFileName(_ apt: AirportResult, _ chart: ChartFile, addIcao: Bool, used: inout Set<String>) -> String {
        var base = chart.code == "PDF" ? chart.name : "\(chart.code) - \(chart.name)"
        if addIcao { base = "\(apt.icao) - \(base)" }
        let file = sanitize(base)
        var candidate = "\(file).pdf"
        var n = 2
        while !used.insert(candidate.lowercased()).inserted {
            candidate = "\(file) (\(n)).pdf"
            n += 1
        }
        return candidate
    }
}
