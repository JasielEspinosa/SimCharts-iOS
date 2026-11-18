import Foundation

struct FaaChart {
    let code: String
    let name: String
    let pdf: String
}

final class FaaAirport {
    let icao: String
    let name: String
    var charts: [FaaChart] = []
    init(icao: String, name: String) {
        self.icao = icao
        self.name = name
    }
}

final class FaaIndex {
    var cycle = ""
    var airports: [String: FaaAirport] = [:]
}

/// Stream-parses the FAA d-TPP metafile.
final class FaaDtppParser: NSObject, XMLParserDelegate {
    let index = FaaIndex()
    private var current: FaaAirport?
    private var inRecord = false
    private var tag: String?
    private var code = ""
    private var name = ""
    private var pdf = ""

    static func parse(fileURL: URL) -> FaaIndex? {
        guard let parser = XMLParser(contentsOf: fileURL) else { return nil }
        let delegate = FaaDtppParser()
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.index
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "digital_tpp":
            index.cycle = attributeDict["cycle"] ?? ""
        case "airport_name":
            let icao = (attributeDict["icao_ident"] ?? "").trimmed.uppercased()
            if icao.isEmpty {
                current = nil
            } else if let existing = index.airports[icao] {
                current = existing
            } else {
                let apt = FaaAirport(icao: icao, name: attributeDict["ID"] ?? icao)
                index.airports[icao] = apt
                current = apt
            }
        case "record":
            inRecord = true
            code = ""
            name = ""
            pdf = ""
        default:
            if inRecord { tag = elementName }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inRecord else { return }
        switch tag {
        case "chart_code": code += string
        case "chart_name": name += string
        case "pdf_name": pdf += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "record" {
            inRecord = false
            if let apt = current, !pdf.trimmed.isEmpty {
                apt.charts.append(FaaChart(code: code.trimmed, name: name.trimmed, pdf: pdf.trimmed))
            }
        }
        tag = nil
    }
}

/// Downloads (and caches) the FAA metafile and turns an ICAO code into chart URLs.
final class FaaDtppSource {
    static let metafileURL = "https://nfdc.faa.gov/webContent/dtpp/current.xml"
    static let pdfBaseURL = "https://aeronav.faa.gov/d-tpp/"
    private static let cacheSeconds: TimeInterval = 12 * 60 * 60

    private let cacheFile: URL
    private var index: FaaIndex?
    private var indexLoadedAt = Date.distantPast

    init(cacheDir: URL) {
        cacheFile = cacheDir.appendingPathComponent("dtpp-current.xml")
    }

    private func cacheAge() -> TimeInterval? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
              let modified = attrs[.modificationDate] as? Date else { return nil }
        return Date().timeIntervalSince(modified)
    }

    func getIndex(log: @escaping (String) -> Void) async throws -> FaaIndex {
        if let idx = index, Date().timeIntervalSince(indexLoadedAt) < Self.cacheSeconds { return idx }

        let age = cacheAge()
        if age == nil || (age ?? 0) > Self.cacheSeconds {
            do {
                log("Downloading FAA chart index (once a day, ~10 MB)...")
                try await download()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if cacheAge() == nil {
                    throw ChartSourceError("Could not download the FAA chart index: \(error.localizedDescription)")
                }
                log("FAA index download failed, using the older cached copy.")
            }
        }

        let file = cacheFile
        let parsed = await Task.detached(priority: .userInitiated) { FaaDtppParser.parse(fileURL: file) }.value
        guard let idx = parsed else { throw ChartSourceError("Could not read the FAA chart index.") }
        index = idx
        indexLoadedAt = Date()
        return idx
    }

    private func download() async throws {
        let (tmp, resp) = try await Http.session.download(for: try Http.request(Self.metafileURL))
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HttpError(status: (resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let fm = FileManager.default
        try? fm.removeItem(at: cacheFile)
        try fm.moveItem(at: tmp, to: cacheFile)
    }

    func find(_ icao: String, log: @escaping (String) -> Void) async throws -> AirportResult? {
        let idx = try await getIndex(log: log)
        guard let apt = idx.airports[icao.uppercased()] else { return nil }
        let base = "\(Self.pdfBaseURL)\(idx.cycle)/"
        return AirportResult(
            icao: apt.icao,
            airportName: Self.titleCase(apt.name),
            sourceName: "FAA d-TPP cycle \(idx.cycle)",
            charts: apt.charts.map { ChartFile(code: $0.code, name: $0.name, url: base + $0.pdf) }
        )
    }

    static func titleCase(_ s: String) -> String {
        s.lowercased()
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { String($0.prefix(1)).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")
    }
}

/// Human-readable names for FAA chart codes.
enum FaaChartTypes {
    static func describe(_ code: String) -> String {
        switch code {
        case "APD": return "Airport Diagram"
        case "IAP": return "Instrument Approaches"
        case "DP": return "Departures (SID)"
        case "STR": return "Arrivals (STAR)"
        case "ODP": return "Obstacle Departure Procedures"
        case "MIN": return "Minimums"
        case "HOT": return "Hot Spots"
        case "LAH": return "LAHSO"
        case "DAU": return "Other"
        case "AREA": return "Area & Aerodrome Information"
        case "APT": return "Airport Charts"
        case "SID": return "Departures (SID)"
        case "STAR": return "Arrivals (STAR)"
        case "CIRCUIT": return "Traffic Circuit"
        case "AOC": return "Aerodrome Obstacle Charts"
        case "PBP": return "Pushback Procedures"
        case "PATC": return "Precision Approach Terrain"
        case "VFR": return "VFR Charts"
        case "SMAC": return "Surveillance Minimum Altitude"
        case "HLL", "HZMB", "CTR", "ATOC", "AERO": return "Other"
        case "DATA": return "Procedure Data Tables"
        case "PDF": return "Charts"
        default: return code
        }
    }
}
