import Foundation

/// How trustworthy / current a built-in chart source is.
enum SourceKind: String {
    case official = "Official"
    case community = "Community"
    case unofficialMirror = "Unofficial mirror"
    case historical = "Historical"
}

/// One row of the Supported Countries page.
struct SupportedCountry: Identifiable {
    let country: String
    /// ICAO codes it covers, e.g. "VQ..".
    let codes: String
    let source: String
    let coverage: String
    let kind: SourceKind
    var id: String { country }
}

/// A country the app cannot download yet, and what to do instead.
struct UnsupportedCountry: Identifiable {
    let country: String
    let codes: String
    let reason: String
    var id: String { country }
}

/// The built-in chart sources, alphabetical. Keep in sync with ChartResolver.
enum SupportedCountries {
    static let supported: [SupportedCountry] = [
        SupportedCountry(
            country: "Bhutan", codes: "VQ..", source: "Bhutan AIP (doat.gov.bt)",
            coverage: "Paro VQPR, Gelephu VQGP, Bumthang VQBT and Yonphula VQTY. One PDF per airport: its AD 2 aerodrome section of the AIP.",
            kind: .official),
        SupportedCountry(
            country: "Hong Kong", codes: "VH..", source: "Hong Kong eAIP (ais.gov.hk)",
            coverage: "VHHH: aerodrome, SID, STAR and approach charts.",
            kind: .official),
        SupportedCountry(
            country: "Hong Kong - Kai Tak (historical)", codes: "VHHX", source: "IVAO East Asia archive (xe.ivao.aero)",
            coverage: "Hong Kong's airport until 1998: layout, flight procedures and community chart packs. Frozen simulation charts, not current or official.",
            kind: .historical),
        SupportedCountry(
            country: "Japan", codes: "RJ.. RO..", source: "AIP Japan mirror (nagodede.github.io)",
            coverage: "One combined PDF per airport with its aerodrome charts. The AIRAC date shows in the download log and may be out of date.",
            kind: .unofficialMirror),
        SupportedCountry(
            country: "Macao", codes: "VM..", source: "Hong Kong eAIP (ais.gov.hk)",
            coverage: "VMMC: SID and STAR only (the rest of the Macao AIP needs a terms-of-use tick box).",
            kind: .official),
        SupportedCountry(
            country: "Nepal", codes: "VN..", source: "Nepal eAIP (CAAN, e-aip.caanepal.gov.np)",
            coverage: "14 airports, including Kathmandu VNKT, Pokhara VNPK and Bhairahawa VNBW. One PDF per airport: its AD 2 aerodrome section of the AIP; VNKT is about 70 MB.",
            kind: .official),
        SupportedCountry(
            country: "Philippines", codes: "RP..", source: "VATPHIL (vatphil.com)",
            coverage: "Charts for the airports VATPHIL publishes.",
            kind: .community),
        SupportedCountry(
            country: "South Korea", codes: "RK..", source: "Korea eAIP (aim.koca.go.kr)",
            coverage: "Aerodrome, SID, STAR and approach charts. The PDFs are very large.",
            kind: .official),
        SupportedCountry(
            country: "Taiwan", codes: "RC..", source: "Taiwan eAIP (ais.caa.gov.tw)",
            coverage: "All 19 airports in the eAIP, including Taoyuan RCTP, Songshan RCSS, Kaohsiung RCKH and Taichung RCMQ.",
            kind: .official),
        SupportedCountry(
            country: "United States", codes: "K.. PA PF PG PH PJ PM PO PP PW", source: "FAA d-TPP (faa.gov)",
            coverage: "Every airport with published procedures: diagrams, SIDs, STARs, approaches and minimums.",
            kind: .official),
        SupportedCountry(
            country: "Viet Nam", codes: "VV..", source: "Viet Nam eAIP (aim.vatm.vn)",
            coverage: "Aerodrome, SID, STAR and approach charts, for example VVNB Hanoi.",
            kind: .official),
    ]

    static let notAvailable: [UnsupportedCountry] = [
        UnsupportedCountry(
            country: "Indonesia", codes: "WA.. WI.. WQ.. WR..",
            reason: "The official AIP needs a free login, so it cannot be downloaded. Save its PDFs into the SimCharts folder of the Files app yourself."),
        UnsupportedCountry(
            country: "Singapore", codes: "WS..",
            reason: "No chart source that works from this app yet."),
    ]

    static let otherCountries = "Any other country: add your own source in Settings > Custom Resources."
}
