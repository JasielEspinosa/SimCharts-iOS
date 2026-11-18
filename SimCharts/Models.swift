import Foundation

enum SourceMode: String, Codable, CaseIterable {
    case DirectPdf
    case ScanPage
}

/// A user-defined chart source for one ICAO prefix (e.g. "EG" or "LFPG").
struct CustomResource: Codable, Identifiable, Equatable {
    var id = UUID()
    var enabled = true
    var prefix = ""
    var label = ""
    var mode: SourceMode = .DirectPdf
    /// URL with {ICAO} / {icao} placeholders.
    var urlTemplate = ""
}

struct AppSettings: Codable, Equatable {
    var theme = "Dark"
    var selectWhichCharts = true
    var addAirportCodeToFilename = true
    var openAfterDownload = false
    var waitBetweenAirports = true
    var customResources: [CustomResource] = [
        CustomResource(
            enabled: false,
            prefix: "XX",
            label: "Example - replace with a real source",
            mode: .DirectPdf,
            urlTemplate: "https://example.com/charts/{ICAO}.pdf"
        )
    ]
}

struct ChartFile: Identifiable, Equatable {
    let code: String
    let name: String
    let url: String
    var id: String { url }
}

struct AirportResult {
    let icao: String
    let airportName: String?
    let sourceName: String
    var charts: [ChartFile]
}

struct ChartSourceError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
