import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

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
