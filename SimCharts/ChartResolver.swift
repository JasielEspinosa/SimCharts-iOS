import Foundation

/// Turns an ICAO code into the charts available for it.
enum ChartResolver {
    /// Custom resources with the longest matching prefix, then FAA for US codes, then the built-in country sources.
    static func resolve(
        _ icaoIn: String,
        settings: AppSettings,
        faa: FaaDtppSource,
        log: @escaping (String) -> Void
    ) async throws -> AirportResult {
        let icao = icaoIn.uppercased()

        let matches = settings.customResources.filter {
            $0.enabled && !$0.urlTemplate.trimmed.isEmpty && IcaoPrefixes.matchesPrefix(icao, $0.prefix)
        }
        if !matches.isEmpty {
            let longest = matches.map { $0.prefix.trimmed.count }.max() ?? 0
            let best = matches.filter { $0.prefix.trimmed.count == longest }
            var all: [ChartFile] = []
            var sources: [String] = []
            for res in best {
                let one = try await CustomSource.fetch(res, icao: icao)
                all.append(contentsOf: one.charts)
                sources.append(one.sourceName)
            }
            if all.isEmpty { throw ChartSourceError("\(icao): the custom resource found no PDF links.") }
            return AirportResult(icao: icao, airportName: nil, sourceName: sources.joined(separator: ", "), charts: all)
        }

        if IcaoPrefixes.isFaaRegion(icao) {
            guard let apt = try await faa.find(icao, log: log) else {
                throw ChartSourceError("\(icao): not found in the FAA d-TPP (no published procedures).")
            }
            if apt.charts.isEmpty { throw ChartSourceError("\(icao): the FAA lists no charts for this airport.") }
            return apt
        }

        if IcaoPrefixes.isPhilippines(icao) { return try await VatphilSource.find(icao) }
        if IcaoPrefixes.isKaiTak(icao) { return try await KaiTakSource.find(icao) }
        if IcaoPrefixes.isHongKongAis(icao) { return try await HkAisSource.find(icao) }
        if IcaoPrefixes.isTaiwan(icao) { return try await TaiwanCaaSource.find(icao) }
        if IcaoPrefixes.isKorea(icao) { return try await KoreaAimSource.find(icao) }
        if IcaoPrefixes.isJapan(icao) { return try await JapanMirrorSource.find(icao) }
        if IcaoPrefixes.isVietnam(icao) { return try await VietnamAipSource.find(icao) }
        if IcaoPrefixes.isBhutan(icao) { return try await BhutanDoatSource.find(icao) }
        if IcaoPrefixes.isNepal(icao) { return try await NepalCaanSource.find(icao) }

        if IcaoPrefixes.isIndonesia(icao) {
            throw ChartSourceError(
                "\(icao): no chart source for Indonesia. The official AIP Indonesia (aimindonesia.kemenhub.go.id) needs a free login, "
                    + "so SimCharts cannot download it. Save the PDFs from there yourself into \"\(IcaoPrefixes.countryFolderName(icao))/\(icao)\" "
                    + "in the SimCharts folder of the Files app and they will show in the list, or add a source in Settings > Custom Resources."
            )
        }

        let prefix = IcaoPrefixes.getPrefix(icao)
        throw ChartSourceError(
            "\(icao): no chart source for \(prefix) (\(IcaoPrefixes.getCountry(prefix))). Add one in Settings > Custom Resources."
        )
    }
}
