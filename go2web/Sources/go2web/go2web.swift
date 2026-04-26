import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

#if canImport(Network)
@preconcurrency import Network
#endif

@discardableResult
func printHelp(to handle: FileHandle = .standardOutput) -> Int32 {
    let help = """
    go2web — Command-line tool

    Usage:
      go2web -h
      go2web -u <URL>
      go2web -s <search-term>

    Options:
      -h                Show this help message and exit.
      -u <URL>          Fetch the given URL over HTTP (HTTPS support will be added later).
      -s <term>         Search using the provided term (placeholder). Multiple words are allowed.

    """
    if let data = (help + "\n").data(using: .utf8) {
        handle.write(data)
    }
    return 0
}

func printError(_ message: String) -> Int32 {
    let prefix = "Error: "
    if let data = (prefix + message + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
    return 1
}

struct ParsedURL {
    let scheme: String
    let host: String
    let port: Int
    let path: String
}

struct HTTPFetchResult {
    let statusCode: Int
    let contentType: String?
    let readableBody: String
}

struct SearchResult {
    let title: String
    let link: String
    let snippet: String?
}

private func percentDecode(_ s: String) -> String {
    return s.removingPercentEncoding ?? s
}

enum URLParseError: LocalizedError {
    case empty
    case missingScheme
    case unsupportedScheme(String)
    case missingHost
    case invalidPort(String)
    case malformedIPv6

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Invalid URL: empty string."
        case .missingScheme:
            return "Invalid URL: missing scheme (expected http:// or https://)."
        case .unsupportedScheme(let s):
            return "Unsupported scheme: \(s). Only http and https are supported."
        case .missingHost:
            return "Invalid URL: missing host."
        case .invalidPort(let p):
            return "Invalid port: \(p)."
        case .malformedIPv6:
            return "Invalid URL: malformed IPv6 host."
        }
    }
}

func parseURL(_ input: String) throws -> ParsedURL {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw URLParseError.empty }

    guard let sepRange = trimmed.range(of: "://") else {
        throw URLParseError.missingScheme
    }

    let rawScheme = String(trimmed[..<sepRange.lowerBound])
    let scheme = rawScheme.lowercased()

    guard scheme == "http" || scheme == "https" else {
        throw URLParseError.unsupportedScheme(rawScheme)
    }

    let afterScheme = String(trimmed[sepRange.upperBound...])
    guard !afterScheme.isEmpty else {
        throw URLParseError.missingHost
    }

    let hostPortPart: String
    let pathPart: String

    if let slashIndex = afterScheme.firstIndex(of: "/") {
        hostPortPart = String(afterScheme[..<slashIndex])
        pathPart = String(afterScheme[slashIndex...])
    } else {
        hostPortPart = afterScheme
        pathPart = "/"
    }

    var host = ""
    var port: Int?

    if hostPortPart.hasPrefix("[") {
        guard let closing = hostPortPart.firstIndex(of: "]") else {
            throw URLParseError.malformedIPv6
        }

        let hostStart = hostPortPart.index(after: hostPortPart.startIndex)
        host = String(hostPortPart[hostStart..<closing])

        let remainder = hostPortPart[hostPortPart.index(after: closing)...]

        if remainder.hasPrefix(":") {
            let portStr = String(remainder.dropFirst())
            guard !portStr.isEmpty, let p = Int(portStr), p > 0 && p <= 65535 else {
                throw URLParseError.invalidPort(portStr)
            }
            port = p
        } else if !remainder.isEmpty {
            throw URLParseError.malformedIPv6
        }
    } else {
        if let colonIndex = hostPortPart.firstIndex(of: ":") {
            host = String(hostPortPart[..<colonIndex])
            let portStr = String(hostPortPart[hostPortPart.index(after: colonIndex)...])

            guard !portStr.isEmpty, let p = Int(portStr), p > 0 && p <= 65535 else {
                throw URLParseError.invalidPort(portStr)
            }

            port = p
        } else {
            host = hostPortPart
        }
    }

    host = host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else {
        throw URLParseError.missingHost
    }

    let finalPort = port ?? (scheme == "http" ? 80 : 443)
    let path = pathPart.isEmpty ? "/" : pathPart

    return ParsedURL(scheme: scheme, host: host, port: finalPort, path: path)
}

private func decodeCommonHTMLEntities(_ text: String) -> String {
    var result = text
    let entities: [(String, String)] = [
        ("&amp;", "&"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", "\""),
        ("&#39;", "'"),
        ("&nbsp;", " ")
    ]

    for (entity, char) in entities {
        result = result.replacingOccurrences(of: entity, with: char)
    }

    return result
}

func parseDuckDuckGoHTML(_ html: String) -> [SearchResult] {
    // Normalize newlines and collapse some whitespace for simpler regex scanning
    let text = html.replacingOccurrences(of: "\r\n", with: "\n")
                   .replacingOccurrences(of: "\r", with: "\n")

    // Regex to find result titles and links
    // Captures href (group 1) and inner HTML of the anchor (group 2)
    let pattern = "<a[^>]*class=\\\"result__a\\\"[^>]*href=\\\"([^\\\"]+)\\\"[^>]*>([\\s\\S]*?)</a>"
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }

    var results: [SearchResult] = []
    let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)

    re.enumerateMatches(in: text, options: [], range: nsrange) { match, _, stop in
        guard let match = match, match.numberOfRanges >= 3 else { return }

        // Extract href
        let hrefRange = match.range(at: 1)
        let titleHTMLRange = match.range(at: 2)
        guard let hrefSwiftRange = Range(hrefRange, in: text),
              let titleHTMLSwiftRange = Range(titleHTMLRange, in: text) else { return }

        let href = String(text[hrefSwiftRange])
        var titleHTML = String(text[titleHTMLSwiftRange])

        // Convert basic entities and strip inner tags to get title text
        titleHTML = decodeCommonHTMLEntities(titleHTML)
        if let titleTags = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let r = NSRange(titleHTML.startIndex..<titleHTML.endIndex, in: titleHTML)
            titleHTML = titleTags.stringByReplacingMatches(in: titleHTML, options: [], range: r, withTemplate: " ")
        }
        let title = titleHTML.trimmingCharacters(in: .whitespacesAndNewlines)

        // DuckDuckGo uses redirect links like /l/?kh=-1&uddg=<encoded>
        // Try to resolve uddg parameter if present
        var link = href.replacingOccurrences(of: "&amp;", with: "&")
        if link.hasPrefix("/l/?") || link.hasPrefix("/l? ") || link.contains("uddg=") {
            if let qIndex = link.range(of: "uddg=")?.upperBound {
                let encoded = String(link[qIndex...])
                // Trim after next & if present
                let decodedParam = encoded.split(separator: "&", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? encoded
                link = percentDecode(decodedParam)
            }
        }

        // Find a nearby snippet after this anchor
        var snippet: String? = nil
        let searchStart = titleHTMLSwiftRange.upperBound
        let tail = String(text[searchStart...])
        if let snippetRe = try? NSRegularExpression(pattern: "<div[^>]*class=\\\"result__snippet[^\\\"]*\\\"[^>]*>([\\s\\S]*?)</div>", options: [.caseInsensitive]) {
            let nsTail = NSRange(tail.startIndex..<tail.endIndex, in: tail)
            if let m = snippetRe.firstMatch(in: tail, options: [], range: nsTail), m.numberOfRanges >= 2,
               let sr = Range(m.range(at: 1), in: tail) {
                var inner = String(tail[sr])
                inner = decodeCommonHTMLEntities(inner)
                if let tagRe = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
                    let r = NSRange(inner.startIndex..<inner.endIndex, in: inner)
                    inner = tagRe.stringByReplacingMatches(in: inner, options: [], range: r, withTemplate: " ")
                }
                snippet = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        results.append(SearchResult(title: title, link: link, snippet: snippet))
        if results.count >= 10 { stop.pointee = true }
    }

    return results
}

func makeHumanReadable(body: String, contentType: String?) -> String {
    let type = contentType?.lowercased() ?? ""

    if type.contains("application/json") {
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(obj),
           let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
           let pretty = String(data: prettyData, encoding: .utf8) {
            return pretty
        }

        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    if type.contains("text/html") {
        var text = body

        text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if let reScript = try? NSRegularExpression(pattern: "<script\\b[\\s\\S]*?<\\/script>", options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = reScript.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
        }

        if let reStyle = try? NSRegularExpression(pattern: "<style\\b[\\s\\S]*?<\\/style>", options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = reStyle.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
        }

        text = text.replacingOccurrences(of: "</title>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</h1>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</h2>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</h3>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)

        if let reTags = try? NSRegularExpression(pattern: "<[^>]+>", options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = reTags.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
        }

        text = decodeCommonHTMLEntities(text)

        if let reSpaces = try? NSRegularExpression(pattern: "[ \\t]+", options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = reSpaces.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
        }

        if let reBlank = try? NSRegularExpression(pattern: "\\n\\s*\\n+", options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = reBlank.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "\n\n")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return body.trimmingCharacters(in: .whitespacesAndNewlines)
}

func decodeChunkedBody(_ body: String) -> String {
    let bytes = Array(body.utf8)
    let n = bytes.count
    var i = 0
    var out: [UInt8] = []

    func readLine() -> String? {
        if i >= n { return nil }

        let start = i

        while i < n && bytes[i] != 0x0A {
            i += 1
        }

        var end = i

        if i < n && bytes[i] == 0x0A {
            i += 1

            if end > start && bytes[end - 1] == 0x0D {
                end -= 1
            }
        }

        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    while true {
        guard let sizeLine = readLine() else {
            break
        }

        let noExt = sizeLine
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? sizeLine

        let trimmed = noExt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let size = Int(trimmed, radix: 16) else {
            break
        }

        if size == 0 {
            break
        }

        if i + size > n {
            break
        }

        out.append(contentsOf: bytes[i..<(i + size)])
        i += size

        if i + 1 < n && bytes[i] == 0x0D && bytes[i + 1] == 0x0A {
            i += 2
        } else if i < n && bytes[i] == 0x0A {
            i += 1
        }
    }

    return String(decoding: out, as: UTF8.self)
}

private func resolveRelativePath(basePath: String, relative: String) -> String {
    if relative.hasPrefix("/") {
        return relative
    }

    var baseNoQuery = basePath

    if let q = baseNoQuery.firstIndex(of: "?") {
        baseNoQuery = String(baseNoQuery[..<q])
    }

    if let hash = baseNoQuery.firstIndex(of: "#") {
        baseNoQuery = String(baseNoQuery[..<hash])
    }

    let baseDir: String

    if baseNoQuery.hasSuffix("/") {
        baseDir = baseNoQuery
    } else if let lastSlash = baseNoQuery.lastIndex(of: "/") {
        baseDir = String(baseNoQuery[..<baseNoQuery.index(after: lastSlash)])
    } else {
        baseDir = "/"
    }

    let combined = baseDir + relative
    var stack: [String] = []

    for part in combined.split(separator: "/", omittingEmptySubsequences: false) {
        let s = String(part)

        if s.isEmpty || s == "." {
            continue
        }

        if s == ".." {
            if !stack.isEmpty {
                stack.removeLast()
            }
        } else {
            stack.append(s)
        }
    }

    return "/" + stack.joined(separator: "/")
}

private func isIPv6LiteralHost(_ host: String) -> Bool {
    return host.contains(":")
}

#if canImport(Network)
@available(macOS 10.14, *)
final class HTTPSClientBox: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var responseData = Data()
    private var connection: NWConnection?

    func append(_ data: Data) {
        lock.lock()
        responseData.append(data)
        lock.unlock()
    }

    func finish() {
        semaphore.signal()
    }

    func wait() {
        _ = semaphore.wait(timeout: .now() + 30)
    }

    func resultString() -> String? {
        lock.lock()
        let data = responseData
        lock.unlock()
        return String(data: data, encoding: .utf8)
    }

    func start(host: String, port: UInt16, request: String, tls: Bool) {
        let params = tls ? NWParameters.tls : NWParameters.tcp
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            finish()
            return
        }

        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: params
        )

        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .ready:
                let requestData = Data(request.utf8)
                conn.send(content: requestData, completion: .contentProcessed { [weak self] _ in
                    self?.receiveNext()
                })

            case .failed(_), .cancelled:
                self.finish()

            default:
                break
            }
        }

        conn.start(queue: DispatchQueue.global())
    }

    private func receiveNext() {
        guard let conn = connection else {
            finish()
            return
        }

        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.append(data)
            }

            if isComplete || error != nil {
                self.finish()
            } else {
                self.receiveNext()
            }
        }
    }

    func cancel() {
        connection?.cancel()
    }
}

@available(macOS 10.14, *)
private func receiveAllOverNWConnection(host: String, port: UInt16, request: String, tls: Bool) -> String? {
    let box = HTTPSClientBox()
    box.start(host: host, port: port, request: request, tls: tls)
    box.wait()
    box.cancel()
    return box.resultString()
}


func performHTTPSGet(host: String, port: Int, path: String) -> HTTPFetchResult? {
    var current = ParsedURL(scheme: "https", host: host, port: port, path: path)
    let maxRedirects = 5
    var redirects = 0

    while true {
        let hostHeaderHost = isIPv6LiteralHost(current.host) ? "[\(current.host)]" : current.host
        let request = buildHTTPRequest(hostHeader: hostHeaderHost, path: current.path, defaultPort: 443, port: current.port)
        guard let response = receiveAllOverNWConnection(host: current.host, port: UInt16(current.port), request: request, tls: true) else {
            _ = printError("HTTPS connection failed.")
            return nil
        }

        func handleHeadAndBody(head: String, body: String) -> HTTPFetchResult? {
            let lines = head.split(whereSeparator: { $0.isNewline }).map(String.init)
            let statusLine = lines.first ?? ""
            var statusCode = 0
            let parts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            if parts.count >= 2, let code = Int(parts[1]) { statusCode = code }

            var contentTypeHeader: String? = nil
            var transferEncodingHeader: String? = nil
            var locationHeader: String? = nil

            for headerLine in lines.dropFirst() {
                if let colon = headerLine.firstIndex(of: ":") {
                    let name = headerLine[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = headerLine[headerLine.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    switch name {
                    case "content-type": contentTypeHeader = String(value)
                    case "transfer-encoding": transferEncodingHeader = String(value)
                    case "location": locationHeader = String(value)
                    default: break
                    }
                }
            }

            if [301, 302, 303, 307, 308].contains(statusCode), let loc = locationHeader {
                let lower = loc.lowercased()
                if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
                    if let parsed = try? parseURL(loc) {
                        if parsed.scheme == "https" {
                            current = parsed
                        } else {
                            // Switch to plain HTTP client for http redirects
                            return performPlainHTTPGet(host: parsed.host, port: parsed.port, path: parsed.path)
                        }
                    } else {
                        _ = printError("Invalid redirect Location: \(loc)")
                        return nil
                    }
                } else {
                    let newPath = resolveRelativePath(basePath: current.path, relative: loc)
                    current = ParsedURL(scheme: current.scheme, host: current.host, port: current.port, path: newPath)
                }
                redirects += 1
                if redirects > maxRedirects {
                    _ = printError("Too many redirects (max 5).")
                    return nil
                }
                return nil
            }

            var processedBody = body
            if let te = transferEncodingHeader?.lowercased(), te.contains("chunked") {
                processedBody = decodeChunkedBody(body)
            }
            let readable = makeHumanReadable(body: processedBody, contentType: contentTypeHeader)
            return HTTPFetchResult(statusCode: statusCode, contentType: contentTypeHeader, readableBody: readable)
        }

        if let sep = response.range(of: "\r\n\r\n") {
            let head = String(response[..<sep.lowerBound])
            let body = String(response[sep.upperBound...])
            if let r = handleHeadAndBody(head: head, body: body) { return r } else { continue }
        } else if let sep = response.range(of: "\n\n") {
            let head = String(response[..<sep.lowerBound])
            let body = String(response[sep.upperBound...])
            if let r = handleHeadAndBody(head: head, body: body) { return r } else { continue }
        } else {
            return HTTPFetchResult(statusCode: 0, contentType: nil, readableBody: response)
        }
    }
}

// Raw-HTML variant for search parsing
func performHTTPSGetRawHTML(host: String, port: Int, path: String) -> (Int, String?, String)? {
    var current = ParsedURL(scheme: "https", host: host, port: port, path: path)
    let maxRedirects = 5
    var redirects = 0

    while true {
        let hostHeaderHost = isIPv6LiteralHost(current.host) ? "[\(current.host)]" : current.host
        let request = buildHTTPRequest(hostHeader: hostHeaderHost, path: current.path, defaultPort: 443, port: current.port)
        guard let response = receiveAllOverNWConnection(host: current.host, port: UInt16(current.port), request: request, tls: true) else {
            return nil
        }

        func handleHeadAndBody(head: String, body: String) -> (Int, String?, String)? {
            let lines = head.split(whereSeparator: { $0.isNewline }).map(String.init)
            let statusLine = lines.first ?? ""
            var statusCode = 0
            let parts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            if parts.count >= 2, let code = Int(parts[1]) { statusCode = code }

            var contentTypeHeader: String? = nil
            var transferEncodingHeader: String? = nil
            var locationHeader: String? = nil

            for headerLine in lines.dropFirst() {
                if let colon = headerLine.firstIndex(of: ":") {
                    let name = headerLine[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = headerLine[headerLine.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    switch name {
                    case "content-type": contentTypeHeader = String(value)
                    case "transfer-encoding": transferEncodingHeader = String(value)
                    case "location": locationHeader = String(value)
                    default: break
                    }
                }
            }

            if [301, 302, 303, 307, 308].contains(statusCode), let loc = locationHeader {
                let lower = loc.lowercased()
                if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
                    if let parsed = try? parseURL(loc) {
                        if parsed.scheme == "https" {
                            // Switch to plain HTTP client for http redirects (raw body not supported here)
                            if let result = performPlainHTTPGet(host: parsed.host, port: parsed.port, path: parsed.path) {
                                return (result.statusCode, result.contentType, result.readableBody)
                            }
                            return nil
                        } else {
                            current = parsed
                        }
                    } else {
                        return nil
                    }
                } else {
                    let newPath = resolveRelativePath(basePath: current.path, relative: loc)
                    current = ParsedURL(scheme: current.scheme, host: current.host, port: current.port, path: newPath)
                }
                redirects += 1
                if redirects > maxRedirects { return nil }
                return nil
            }

            var processedBody = body
            if let te = transferEncodingHeader?.lowercased(), te.contains("chunked") {
                processedBody = decodeChunkedBody(body)
            }
            return (statusCode, contentTypeHeader, processedBody)
        }

        if let sep = response.range(of: "\r\n\r\n") {
            let head = String(response[..<sep.lowerBound])
            let body = String(response[sep.upperBound...])
            if let r = handleHeadAndBody(head: head, body: body) { return r } else { continue }
        } else if let sep = response.range(of: "\n\n") {
            let head = String(response[..<sep.lowerBound])
            let body = String(response[sep.upperBound...])
            if let r = handleHeadAndBody(head: head, body: body) { return r } else { continue }
        } else {
            return (0, nil, response)
        }
    }
}

private func buildHTTPRequest(hostHeader: String, path: String, defaultPort: Int, port: Int) -> String {
    let headerHost = port == defaultPort ? hostHeader : "\(hostHeader):\(port)"
    return """
    GET \(path.isEmpty ? "/" : path) HTTP/1.1\r
    Host: \(headerHost)\r
    User-Agent: go2web-swift/1.0\r
    Accept: text/html, application/json\r
    Connection: close\r
    \r
    \n
    """
}
#else
func performHTTPSGet(host: String, port: Int, path: String) -> HTTPFetchResult? {
    print("HTTPS is not supported on this platform (Network.framework unavailable).")
    return nil
}

func performHTTPSGetRawHTML(host: String, port: Int, path: String) -> (Int, String?, String)? {
    print("HTTPS is not supported on this platform (Network.framework unavailable).")
    return nil
}
#endif

private func cacheDirectoryURL() -> URL {
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".go2web-cache", isDirectory: true)
}

private func safeCacheFilename(for url: String) -> String {
    var output = ""

    for scalar in url.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) {
            output.append(Character(scalar))
        } else {
            output.append("_")
        }
    }

    if output.count > 180 {
        output = String(output.prefix(180))
    }

    return output + ".cache"
}

private func cacheFileURL(for url: String) -> URL {
    return cacheDirectoryURL().appendingPathComponent(safeCacheFilename(for: url))
}

private func readCache(for url: String, ttl: TimeInterval = 300) -> HTTPFetchResult? {
    let fileURL = cacheFileURL(for: url)

    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return nil
    }

    guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else {
        return nil
    }

    let separator = "\n---GO2WEB_BODY---\n"

    guard let bodyRange = raw.range(of: separator) else {
        return nil
    }

    let metadata = String(raw[..<bodyRange.lowerBound])
    let body = String(raw[bodyRange.upperBound...])

    var timestamp: TimeInterval?
    var contentType: String?
    var statusCode = 200

    for line in metadata.split(whereSeparator: { $0.isNewline }) {
        if let colon = line.firstIndex(of: ":") {
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)

            switch name {
            case "timestamp":
                timestamp = TimeInterval(value)
            case "content-type":
                contentType = String(value)
            case "status-code":
                statusCode = Int(value) ?? 200
            default:
                break
            }
        }
    }

    guard let savedAt = timestamp else {
        return nil
    }

    let age = Date().timeIntervalSince1970 - savedAt

    guard age >= 0 && age <= 300 else {
        return nil
    }

    return HTTPFetchResult(statusCode: statusCode, contentType: contentType, readableBody: body)
}

private func saveCache(for url: String, result: HTTPFetchResult) {
    let dir = cacheDirectoryURL()

    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
        return
    }

    let fileURL = cacheFileURL(for: url)

    let contentType = result.contentType ?? ""
    let raw = """
    timestamp: \(Date().timeIntervalSince1970)
    status-code: \(result.statusCode)
    content-type: \(contentType)
    ---GO2WEB_BODY---
    \(result.readableBody)
    """

    try? raw.write(to: fileURL, atomically: true, encoding: .utf8)
}

func performPlainHTTPGet(host: String, port: Int, path: String) -> HTTPFetchResult? {
    var current = ParsedURL(scheme: "http", host: host, port: port, path: path)
    let maxRedirects = 5
    var redirects = 0

    while true {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var res: UnsafeMutablePointer<addrinfo>? = nil
        let portStr = String(current.port)

        let gaiStatus = current.host.withCString { hPtr in
            portStr.withCString { sPtr in
                getaddrinfo(hPtr, sPtr, &hints, &res)
            }
        }

        if gaiStatus != 0 {
            let msg = String(cString: gai_strerror(gaiStatus))
            _ = printError("getaddrinfo failed: \(msg)")
            return nil
        }

        var fd: Int32 = -1
        var ptr = res

        while ptr != nil {
            let ai = ptr!.pointee
            fd = socket(ai.ai_family, ai.ai_socktype, ai.ai_protocol)

            if fd == -1 {
                ptr = ai.ai_next
                continue
            }

            if connect(fd, ai.ai_addr, ai.ai_addrlen) == 0 {
                break
            } else {
                close(fd)
                fd = -1
                ptr = ai.ai_next
            }
        }

        if res != nil {
            freeaddrinfo(res)
        }

        if fd == -1 {
            _ = printError("Could not connect to \(current.host):\(current.port)")
            return nil
        }

        let hostHeaderHost = isIPv6LiteralHost(current.host) ? "[\(current.host)]" : current.host
        let defaultPort = 80
        let hostHeader = current.port == defaultPort ? hostHeaderHost : "\(hostHeaderHost):\(current.port)"

        let request = """
        GET \(current.path.isEmpty ? "/" : current.path) HTTP/1.1\r
        Host: \(hostHeader)\r
        User-Agent: go2web-swift/1.0\r
        Accept: text/html, application/json\r
        Connection: close\r
        \r

        """

        let reqBytes = Array(request.utf8)
        var totalSent = 0

        while totalSent < reqBytes.count {
            let sent = reqBytes.withUnsafeBytes { buf -> Int in
                let base = buf.baseAddress!.advanced(by: totalSent)
                return send(fd, base, reqBytes.count - totalSent, 0)
            }

            if sent <= 0 {
                _ = printError("send failed.")
                close(fd)
                return nil
            }

            totalSent += sent
        }

        var responseBytes: [UInt8] = []
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while true {
            let received = buffer.withUnsafeMutableBytes { ptr -> Int in
                guard let base = ptr.baseAddress else {
                    return -1
                }

                return recv(fd, base, bufferSize, 0)
            }

            if received > 0 {
                responseBytes.append(contentsOf: buffer.prefix(received))
            } else if received == 0 {
                break
            } else {
                _ = printError("recv failed.")
                close(fd)
                return nil
            }
        }

        close(fd)

        let response = String(decoding: responseBytes, as: UTF8.self)

        func handleHeadAndBody(head: String, body: String) -> HTTPFetchResult? {
            let lines = head.split(whereSeparator: { $0.isNewline }).map(String.init)
            let statusLine = lines.first ?? ""

            var statusCode = 0
            let parts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)

            if parts.count >= 2, let code = Int(parts[1]) {
                statusCode = code
            }

            var contentTypeHeader: String?
            var transferEncodingHeader: String?
            var locationHeader: String?

            for headerLine in lines.dropFirst() {
                if let colon = headerLine.firstIndex(of: ":") {
                    let name = headerLine[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = headerLine[headerLine.index(after: colon)...].trimmingCharacters(in: .whitespaces)

                    switch name {
                    case "content-type":
                        contentTypeHeader = String(value)
                    case "transfer-encoding":
                        transferEncodingHeader = String(value)
                    case "location":
                        locationHeader = String(value)
                    default:
                        break
                    }
                }
            }

            if [301, 302, 303, 307, 308].contains(statusCode), let loc = locationHeader {
                let lower = loc.lowercased()

                if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
                    if let parsed = try? parseURL(loc) {
                        if parsed.scheme == "https" {
                            print("HTTPS support will be added later.")
                            return HTTPFetchResult(statusCode: statusCode, contentType: contentTypeHeader, readableBody: "")
                        } else {
                            current = parsed
                        }
                    } else {
                        _ = printError("Invalid redirect Location: \(loc)")
                        return nil
                    }
                } else {
                    let newPath = resolveRelativePath(basePath: current.path, relative: loc)
                    current = ParsedURL(scheme: current.scheme, host: current.host, port: current.port, path: newPath)
                }

                redirects += 1

                if redirects > maxRedirects {
                    _ = printError("Too many redirects (max 5).")
                    return nil
                }

                return nil
            }

            var processedBody = body

            if let te = transferEncodingHeader?.lowercased(), te.contains("chunked") {
                processedBody = decodeChunkedBody(body)
            }

            let readable = makeHumanReadable(body: processedBody, contentType: contentTypeHeader)

            return HTTPFetchResult(
                statusCode: statusCode,
                contentType: contentTypeHeader,
                readableBody: readable
            )
        }

        let result: HTTPFetchResult?

        if let sep = response.range(of: "\r\n\r\n") {
            let head = String(response[..<sep.lowerBound])
            let body = String(response[sep.upperBound...])
            result = handleHeadAndBody(head: head, body: body)
        } else if let sep = response.range(of: "\n\n") {
            let head = String(response[..<sep.lowerBound])
            let body = String(response[sep.upperBound...])
            result = handleHeadAndBody(head: head, body: body)
        } else {
            result = HTTPFetchResult(statusCode: 0, contentType: nil, readableBody: response)
        }

        if let finalResult = result {
            return finalResult
        }

        continue
    }
}

func run() -> Int32 {
    let args = CommandLine.arguments

    guard args.count > 1 else {
        return printHelp()
    }

    var index = 1

    while index < args.count {
        let arg = args[index]

        switch arg {
        case "-h", "--help":
            return printHelp()

        case "-u":
            let nextIndex = index + 1

            guard nextIndex < args.count else {
                return printError("Missing URL after -u.\n\nTry: go2web -u https://example.com")
            }

            let urlString = args[nextIndex]

            do {
                let parsed = try parseURL(urlString)

                if let cached = readCache(for: urlString) {
                    print("[CACHE HIT]")
                    print(cached.readableBody)
                    return 0
                }

                let result: HTTPFetchResult?
                if parsed.scheme == "https" {
                    result = performHTTPSGet(host: parsed.host, port: parsed.port, path: parsed.path)
                } else {
                    result = performPlainHTTPGet(host: parsed.host, port: parsed.port, path: parsed.path)
                }

                guard let final = result else { return 1 }

                print(final.readableBody)

                if final.statusCode >= 200 && final.statusCode < 300 {
                    saveCache(for: urlString, result: final)
                }

                return 0
            } catch {
                if let e = error as? URLParseError {
                    return printError(e.localizedDescription)
                } else {
                    return printError("Failed to parse URL: \(urlString)")
                }
            }

        case "-s":
            let nextIndex = index + 1
            guard nextIndex < args.count else {
                return printError("Missing search term after -s.\n\nTry: go2web -s swift concurrency tutorial")
            }
            let terms = args[nextIndex...].joined(separator: " ")
            let query = terms.replacingOccurrences(of: " ", with: "+")
            let searchURL = "https://html.duckduckgo.com/html/?q=\(query)"

            do {
                let parsed = try parseURL(searchURL)
                if parsed.scheme == "https" {
                    if let (status, contentType, rawHTML) = performHTTPSGetRawHTML(host: parsed.host, port: parsed.port, path: parsed.path) {
                        if status >= 200 && status < 300 {
                            let results = parseDuckDuckGoHTML(rawHTML)
                            if results.isEmpty {
                                print("No results parsed.")
                            } else {
                                for (idx, r) in results.enumerated() {
                                    print("\(idx + 1). \(r.title)")
                                    print(r.link)
                                    if let s = r.snippet, !s.isEmpty { print(s) }
                                    print("")
                                }
                            }
                            return 0
                        } else {
                            print("Search request failed with status: \(status). Content-Type: \(contentType ?? "-")")
                            return 1
                        }
                    } else {
                        print("Failed to perform HTTPS search request.")
                        return 1
                    }
                } else {
                    print("DuckDuckGo HTML search requires HTTPS.")
                    return 1
                }
            } catch {
                return printError("Failed to build search URL.")
            }

        default:
            return printError("Unknown option or argument: \(arg).\n\nRun 'go2web -h' for usage.")
        }

        index += 1
    }

    return 0
}

@main
struct Go2Web {
    static func main() {
        let code = run()
        exit(code)
    }
}
