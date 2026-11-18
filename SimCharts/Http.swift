import Foundation

struct HttpError: Error, LocalizedError {
    let status: Int
    var errorDescription: String? { "HTTP \(status)" }
}

enum Http {
    static let userAgent = "SimCharts/1.0 (flight-sim chart downloader)"

    /// Timeouts make a stalled download fail instead of hanging.
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 3600
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpAdditionalHeaders = ["User-Agent": Http.userAgent]
        return URLSession(configuration: c)
    }()

    static func makeURL(_ s: String) throws -> URL {
        if let u = URL(string: s) { return u }
        throw URLError(.badURL)
    }

    static func request(_ s: String, method: String = "GET") throws -> URLRequest {
        var req = URLRequest(url: try makeURL(s))
        req.httpMethod = method
        return req
    }

    /// Fetches [s] (any status code) and returns the body with the response.
    static func fetch(_ s: String, method: String = "GET") async throws -> (Data, HTTPURLResponse) {
        let (data, resp) = try await session.data(for: try request(s, method: method))
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    static func decodeText(_ d: Data) -> String {
        var s = String(decoding: d, as: UTF8.self)
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
        return s
    }

    /// Body text of a 2xx response; anything else throws HttpError.
    static func getString(_ s: String) async throws -> String {
        let (data, resp) = try await fetch(s)
        guard (200..<300).contains(resp.statusCode) else { throw HttpError(status: resp.statusCode) }
        return decodeText(data)
    }

    /// Like getString, but a 404 gives nil (the page does not exist).
    static func getStringOrNil(_ s: String) async throws -> String? {
        let (data, resp) = try await fetch(s)
        if resp.statusCode == 404 { return nil }
        guard (200..<300).contains(resp.statusCode) else { throw HttpError(status: resp.statusCode) }
        return decodeText(data)
    }

    // MARK: URL helpers

    /// Resolves [ref] against [base] and percent-encodes spaces and non-ASCII characters
    /// (the Taiwan and Korea eAIP links contain both).
    static func resolveEncoded(_ base: String, _ ref: String) -> String {
        // Decode first so an already-encoded base ("%20") is not encoded twice ("%2520").
        let b = decodePercent(base)
        let r = decodePercent(ref)
        return encode(resolve(b, r))
    }

    private static func decodePercent(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }

    private struct Parts {
        var scheme: String
        var authority: String
        var path: String
        var query: String?
    }

    private static func split(_ url: String) -> Parts? {
        var rest = url
        if let h = rest.firstIndex(of: "#") { rest = String(rest[..<h]) }
        var query: String? = nil
        if let q = rest.firstIndex(of: "?") {
            query = String(rest[rest.index(after: q)...])
            rest = String(rest[..<q])
        }
        guard let sep = rest.range(of: "://") else { return nil }
        let scheme = String(rest[..<sep.lowerBound])
        let afterScheme = rest[sep.upperBound...]
        var authority = String(afterScheme)
        var path = ""
        if let slash = afterScheme.firstIndex(of: "/") {
            authority = String(afterScheme[..<slash])
            path = String(afterScheme[slash...])
        }
        return Parts(scheme: scheme, authority: authority, path: path, query: query)
    }

    private static func resolve(_ base: String, _ ref: String) -> String {
        var ref = ref
        if let h = ref.firstIndex(of: "#") { ref = String(ref[..<h]) }
        if ref.hasPrefix("http://") || ref.hasPrefix("https://") { return ref }
        guard let b = split(base) else { return ref }
        if ref.hasPrefix("//") { return b.scheme + ":" + ref }

        var refPath = ref
        var refQuery: String? = nil
        if let q = ref.firstIndex(of: "?") {
            refQuery = String(ref[ref.index(after: q)...])
            refPath = String(ref[..<q])
        }

        var path: String
        var query: String?
        if refPath.isEmpty {
            path = b.path
            query = refQuery ?? b.query
        } else {
            query = refQuery
            if refPath.hasPrefix("/") {
                path = refPath
            } else {
                var dir = "/"
                if let slash = b.path.lastIndex(of: "/") { dir = String(b.path[...slash]) }
                path = dir + refPath
            }
            path = normalize(path)
        }
        var out = b.scheme + "://" + b.authority + path
        if let q = query { out += "?" + q }
        return out
    }

    private static func normalize(_ path: String) -> String {
        let segs = path.components(separatedBy: "/")
        var out: [String] = []
        for (i, s) in segs.enumerated() {
            let last = i == segs.count - 1
            if s == "." {
                if last { out.append("") }
                continue
            }
            if s == ".." {
                if out.count > 1 { out.removeLast() }
                if last { out.append("") }
                continue
            }
            out.append(s)
        }
        return out.joined(separator: "/")
    }

    private static func encode(_ url: String) -> String {
        guard let p = split(url) else { return url }
        let path = p.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? p.path
        var out = p.scheme + "://" + p.authority + path
        if let q = p.query {
            out += "?" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)
        }
        return out
    }

    /// Last path segment, percent-decoded ("+" stays a plus sign).
    static func lastSegment(_ url: String) -> String {
        let raw = url.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        return raw.replacingOccurrences(of: "+", with: "%2B").removingPercentEncoding ?? raw
    }

    static func htmlDecode(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    /// Capitalises every word ("area chart(dep)" -> "Area Chart(Dep)").
    static func titleCase(_ s: String) -> String {
        var out = ""
        var prevLetter = false
        for ch in s.lowercased() {
            if !prevLetter && ch.isLetter {
                out += String(ch).uppercased()
            } else {
                out.append(ch)
            }
            prevLetter = ch.isLetter
        }
        return out
    }
}

/// Runs a network lookup; any error that is not already a ChartSourceError becomes "<what>: <reason>".
func wrapNetwork<T>(_ what: String, _ body: () async throws -> T) async throws -> T {
    do {
        return try await body()
    } catch let e as ChartSourceError {
        throw e
    } catch is CancellationError {
        throw CancellationError()
    } catch {
        if Task.isCancelled { throw CancellationError() }
        throw ChartSourceError("\(what): \(error.localizedDescription)")
    }
}
