import Foundation

#if canImport(Network)
@preconcurrency import Network
#endif

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
