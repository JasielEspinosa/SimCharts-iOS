import Foundation

/// One regular-expression match; group text is read through NSString so ranges stay valid for any characters.
struct RxMatch {
    let text: NSString
    let result: NSTextCheckingResult

    /// Text of group [i], or "" when the group did not take part in the match.
    func group(_ i: Int) -> String {
        guard i < result.numberOfRanges else { return "" }
        let r = result.range(at: i)
        if r.location == NSNotFound { return "" }
        return text.substring(with: r)
    }

    var range: NSRange { result.range }

    func groupRange(_ i: Int) -> NSRange { result.range(at: i) }
}

/// Small wrapper over NSRegularExpression (ICU syntax, same as the Android app's java.util.regex for these patterns).
struct Rx {
    let re: NSRegularExpression

    init(_ pattern: String, ignoreCase: Bool = false, dotAll: Bool = false) {
        var options: NSRegularExpression.Options = []
        if ignoreCase { options.insert(.caseInsensitive) }
        if dotAll { options.insert(.dotMatchesLineSeparators) }
        // The patterns are constants in this app, so a failure here is a programming error.
        self.re = try! NSRegularExpression(pattern: pattern, options: options)
    }

    func all(_ s: String) -> [RxMatch] {
        let ns = NSString(string: s)
        let found = re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
        return found.map { RxMatch(text: ns, result: $0) }
    }

    func first(_ s: String) -> RxMatch? {
        let ns = NSString(string: s)
        guard let r = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return RxMatch(text: ns, result: r)
    }

    func test(_ s: String) -> Bool { first(s) != nil }

    /// `template` uses $1, $2... for groups (a literal dollar sign must be written as \$).
    func replacing(_ s: String, with template: String) -> String {
        let ns = NSString(string: s)
        return re.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }
}

private let whitespaceRx = Rx(#"\s+"#)

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Trims the given characters from both ends.
    func trimmingChars(_ chars: String) -> String {
        trimmingCharacters(in: CharacterSet(charactersIn: chars))
    }

    /// Trims characters from the end only.
    func trimmingTrailing(_ set: CharacterSet) -> String {
        var s = self
        while let last = s.unicodeScalars.last, set.contains(last) {
            s.unicodeScalars.removeLast()
        }
        return s
    }

    func containsCI(_ other: String) -> Bool {
        range(of: other, options: .caseInsensitive) != nil
    }

    func startsWithCI(_ prefix: String) -> Bool {
        range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
    }

    /// Runs of whitespace become one space; the ends are trimmed.
    var collapsedSpaces: String {
        whitespaceRx.replacing(self, with: " ").trimmed
    }

    func removingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
