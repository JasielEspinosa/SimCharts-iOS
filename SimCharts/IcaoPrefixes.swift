import Foundation

/// ICAO input parsing and the ICAO location-prefix -> country table.
enum IcaoPrefixes {
    // First letters that map to a single country: the folder prefix is one letter.
    private static let singleLetter: Set<Character> = ["K", "C", "Y"]
    private static let codePattern = Rx("^[A-Z0-9]{3,4}$")

    private static let countries: [String: String] = {
        var m = [String: String]()
        func add(_ country: String, _ prefixes: String) {
            for p in prefixes.split(separator: " ") { m[String(p)] = country }
        }
        add("Solomon Islands", "AG"); add("Nauru", "AN"); add("Papua New Guinea", "AY")
        add("Greenland", "BG"); add("Iceland", "BI"); add("Kosovo", "BK")
        add("Algeria", "DA"); add("Benin", "DB"); add("Burkina Faso", "DF"); add("Ghana", "DG")
        add("Cote d'Ivoire", "DI"); add("Nigeria", "DN"); add("Niger", "DR"); add("Tunisia", "DT"); add("Togo", "DX")
        add("Belgium", "EB"); add("Germany", "ED ET"); add("Estonia", "EE"); add("Finland", "EF")
        add("United Kingdom", "EG"); add("Netherlands", "EH"); add("Ireland", "EI"); add("Denmark", "EK")
        add("Luxembourg", "EL"); add("Norway", "EN"); add("Poland", "EP"); add("Sweden", "ES")
        add("Latvia", "EV"); add("Lithuania", "EY")
        add("South Africa", "FA"); add("Botswana", "FB"); add("Congo", "FC"); add("Eswatini", "FD")
        add("Central African Republic", "FE"); add("Equatorial Guinea", "FG"); add("Ascension", "FH")
        add("Mauritius", "FI"); add("Cameroon", "FK"); add("Zambia", "FL")
        add("Madagascar / Indian Ocean", "FM"); add("Angola", "FN"); add("Gabon", "FO"); add("Sao Tome", "FP")
        add("Mozambique", "FQ"); add("Seychelles", "FS"); add("Chad", "FT"); add("Zimbabwe", "FV")
        add("Malawi", "FW"); add("Lesotho", "FX"); add("Namibia", "FY"); add("DR Congo", "FZ")
        add("Mali", "GA"); add("Gambia", "GB"); add("Spain (Canary Islands)", "GC"); add("Spain (Ceuta/Melilla)", "GE")
        add("Sierra Leone", "GF"); add("Guinea-Bissau", "GG"); add("Liberia", "GL"); add("Morocco", "GM")
        add("Senegal", "GO"); add("Mauritania", "GQ"); add("Western Sahara", "GS"); add("Guinea", "GU"); add("Cape Verde", "GV")
        add("Ethiopia", "HA"); add("Burundi", "HB"); add("Somalia", "HC"); add("Djibouti", "HD"); add("Egypt", "HE")
        add("Eritrea", "HH"); add("Kenya", "HK"); add("Libya", "HL"); add("Rwanda", "HR"); add("Sudan", "HS")
        add("Tanzania", "HT"); add("Uganda", "HU")
        add("Albania", "LA"); add("Bulgaria", "LB"); add("Cyprus", "LC"); add("Croatia", "LD"); add("Spain", "LE")
        add("France", "LF"); add("Greece", "LG"); add("Hungary", "LH"); add("Italy", "LI"); add("Slovenia", "LJ")
        add("Czechia", "LK"); add("Israel", "LL"); add("Malta", "LM"); add("Monaco", "LN"); add("Austria", "LO")
        add("Portugal", "LP"); add("Bosnia and Herzegovina", "LQ"); add("Romania", "LR"); add("Switzerland", "LS")
        add("Turkiye", "LT"); add("Moldova", "LU"); add("Palestine", "LV"); add("North Macedonia", "LW")
        add("Gibraltar", "LX"); add("Serbia / Montenegro", "LY"); add("Slovakia", "LZ")
        add("Turks and Caicos", "MB"); add("Dominican Republic", "MD"); add("Guatemala", "MG"); add("Honduras", "MH")
        add("Jamaica", "MK"); add("Mexico", "MM"); add("Nicaragua", "MN"); add("Panama", "MP"); add("Costa Rica", "MR")
        add("El Salvador", "MS"); add("Haiti", "MT"); add("Cuba", "MU"); add("Cayman Islands", "MW")
        add("Bahamas", "MY"); add("Belize", "MZ")
        add("Cook Islands", "NC"); add("Fiji / Tonga", "NF"); add("Kiribati / Tuvalu", "NG"); add("Niue", "NI")
        add("Wallis and Futuna", "NL"); add("Samoa", "NS"); add("French Polynesia", "NT"); add("Vanuatu", "NV")
        add("New Caledonia", "NW"); add("New Zealand", "NZ")
        add("Afghanistan", "OA"); add("Bahrain", "OB"); add("Saudi Arabia", "OE"); add("Iran", "OI"); add("Jordan", "OJ")
        add("Kuwait", "OK"); add("Lebanon", "OL"); add("United Arab Emirates", "OM"); add("Oman", "OO")
        add("Pakistan", "OP"); add("Iraq", "OR"); add("Syria", "OS"); add("Qatar", "OT"); add("Yemen", "OY")
        add("United States", "PA PF PG PH PJ PM PO PP PW")
        add("Kiribati", "PC PL"); add("Marshall Islands", "PK"); add("Micronesia / Palau", "PT")
        add("Taiwan", "RC"); add("Japan", "RJ RO"); add("South Korea", "RK"); add("Philippines", "RP")
        add("Argentina", "SA"); add("Brazil", "SB SD SI SJ SN SS SW"); add("Chile", "SC")
        add("Ecuador", "SE"); add("Falkland Islands", "SF"); add("Paraguay", "SG"); add("Colombia", "SK")
        add("Bolivia", "SL"); add("Suriname", "SM"); add("French Guiana", "SO"); add("Peru", "SP")
        add("Uruguay", "SU"); add("Venezuela", "SV"); add("Guyana", "SY")
        add("Antigua and Barbuda", "TA"); add("Barbados", "TB"); add("Dominica", "TD"); add("Guadeloupe / Martinique", "TF")
        add("Grenada", "TG"); add("US Virgin Islands", "TI"); add("Puerto Rico", "TJ"); add("St Kitts and Nevis", "TK")
        add("Saint Lucia", "TL"); add("Caribbean Netherlands", "TN"); add("Anguilla", "TQ"); add("Montserrat", "TR")
        add("Trinidad and Tobago", "TT"); add("British Virgin Islands", "TU"); add("St Vincent", "TV"); add("Bermuda", "TX")
        add("Kazakhstan", "UA"); add("Azerbaijan", "UB"); add("Kyrgyzstan", "UC"); add("Armenia", "UD")
        add("Georgia", "UG"); add("Ukraine", "UK"); add("Belarus", "UM"); add("Central Asia", "UT")
        add("Russia", "UE UH UI UL UN UO UR US UU UW")
        add("India", "VA VE VI VO"); add("Sri Lanka", "VC"); add("Cambodia", "VD"); add("Bangladesh", "VG")
        add("Hong Kong", "VH"); add("Laos", "VL"); add("Macau", "VM"); add("Nepal", "VN"); add("Bhutan", "VQ")
        add("Maldives", "VR"); add("Thailand", "VT"); add("Vietnam", "VV"); add("Myanmar", "VY")
        add("Indonesia", "WA WI WQ WR"); add("Malaysia / Brunei", "WB WM"); add("Timor-Leste", "WP")
        add("Singapore", "WS")
        add("China", "ZB ZG ZH ZJ ZL ZP ZS ZU ZW ZY"); add("North Korea", "ZK"); add("Mongolia", "ZM")
        return m
    }()

    /// Splits free text on whitespace/commas/semicolons, upper-cases, validates and de-duplicates.
    static func parseCodes(_ input: String?) -> (valid: [String], invalid: [String]) {
        var valid: [String] = []
        var invalid: [String] = []
        var seen = Set<String>()
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))
        for raw in (input ?? "").components(separatedBy: separators) {
            if raw.isEmpty { continue }
            let code = raw.uppercased()
            if !seen.insert(code).inserted { continue }
            if codePattern.test(code) { valid.append(code) } else { invalid.append(code) }
        }
        return (valid, invalid)
    }

    /// "RP" for RPLL, "K" for KJFK, "C" for CYYZ.
    static func getPrefix(_ icao: String) -> String {
        let c = icao.uppercased()
        guard let first = c.first else { return "" }
        if singleLetter.contains(first) { return String(first) }
        return c.count >= 2 ? String(c.prefix(2)) : c
    }

    static func getCountry(_ prefix: String) -> String {
        let p = prefix.uppercased()
        if p.count == 1 {
            switch p {
            case "K": return "United States"
            case "C": return "Canada"
            case "Y": return "Australia"
            default: return "Unknown"
            }
        }
        return countries[p] ?? "Unknown"
    }

    /// Folder name used for a country: "RP - Philippines".
    static func countryFolderName(_ icao: String) -> String {
        let p = getPrefix(icao)
        return "\(p) - \(getCountry(p))"
    }

    private static func chars(_ icao: String) -> [Character] { Array(icao.uppercased()) }

    /// True for codes the FAA d-TPP can cover (contiguous US, Alaska, Hawaii, Pacific territories).
    static func isFaaRegion(_ icao: String) -> Bool {
        let c = chars(icao)
        if c.first == "K" { return true }
        return c.count >= 2 && c[0] == "P" && "AFGHJMOPW".contains(c[1])
    }

    /// True for Philippine codes (RP..), served by the built-in VATPHIL source.
    static func isPhilippines(_ icao: String) -> Bool { icao.startsWithCI("RP") }

    /// True for Hong Kong (VH..) and Macao (VM..), served by the Hong Kong eAIP.
    static func isHongKongAis(_ icao: String) -> Bool { icao.startsWithCI("VH") || icao.startsWithCI("VM") }

    /// True for Taiwan (RC..), served by the Taiwan eAIP.
    static func isTaiwan(_ icao: String) -> Bool { icao.startsWithCI("RC") }

    /// True for South Korea (RK..), served by the Korea eAIP.
    static func isKorea(_ icao: String) -> Bool { icao.startsWithCI("RK") }

    /// True for Japan (RJ.. and RO.. for Okinawa), served by the AIP Japan chart mirror.
    static func isJapan(_ icao: String) -> Bool { icao.startsWithCI("RJ") || icao.startsWithCI("RO") }

    /// True for Viet Nam (VV..), served by the Viet Nam eAIP.
    static func isVietnam(_ icao: String) -> Bool { icao.startsWithCI("VV") }

    /// True for Indonesia (WA.., WI.., WQ.., WR..). Its official AIP needs a login, so there is no built-in source.
    static func isIndonesia(_ icao: String) -> Bool {
        let c = chars(icao)
        return c.count >= 2 && c[0] == "W" && "AIQR".contains(c[1])
    }

    static func matchesPrefix(_ icao: String, _ prefix: String) -> Bool {
        let p = prefix.trimmed
        return !p.isEmpty && icao.startsWithCI(p)
    }
}
