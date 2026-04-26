import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
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

    guard let sepRange = trimmed.range(of: "://") else { throw URLParseError.missingScheme }
    let rawScheme = String(trimmed[..<sepRange.lowerBound])
    let scheme = rawScheme.lowercased()
    guard scheme == "http" || scheme == "https" else { throw URLParseError.unsupportedScheme(rawScheme) }

    let afterScheme = String(trimmed[sepRange.upperBound...])
    guard !afterScheme.isEmpty else { throw URLParseError.missingHost }

    let hostPortAndMaybePath = afterScheme

    let hostPortPart: String
    let pathPart: String
    if let slashIndex = hostPortAndMaybePath.firstIndex(of: "/") {
        hostPortPart = String(hostPortAndMaybePath[..<slashIndex])
        pathPart = String(hostPortAndMaybePath[slashIndex...])
    } else {
        hostPortPart = hostPortAndMaybePath
        pathPart = "/"
    }

    var host = ""
    var port: Int?

    if hostPortPart.hasPrefix("[") {
        // IPv6 literal in brackets
        guard let closing = hostPortPart.firstIndex(of: "]") else { throw URLParseError.malformedIPv6 }
        let hostStart = hostPortPart.index(after: hostPortPart.startIndex)
        host = String(hostPortPart[hostStart..<closing])
        let remainder = hostPortPart[hostPortPart.index(after: closing)...]
        if remainder.hasPrefix(":") {
            let portStr = String(remainder.dropFirst())
            guard !portStr.isEmpty, let p = Int(portStr), p > 0 && p <= 65535 else { throw URLParseError.invalidPort(portStr) }
            port = p
        } else if !remainder.isEmpty {
            // Unexpected characters after closing bracket
            throw URLParseError.malformedIPv6
        }
    } else {
        if let colonIndex = hostPortPart.firstIndex(of: ":") {
            host = String(hostPortPart[..<colonIndex])
            let portStr = String(hostPortPart[hostPortPart.index(after: colonIndex)...])
            guard !portStr.isEmpty, let p = Int(portStr), p > 0 && p <= 65535 else { throw URLParseError.invalidPort(portStr) }
            port = p
        } else {
            host = hostPortPart
        }
    }

    host = host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else { throw URLParseError.missingHost }

    let finalPort = port ?? (scheme == "http" ? 80 : 443)
    let path = pathPart.isEmpty ? "/" : pathPart

    return ParsedURL(scheme: scheme, host: host, port: finalPort, path: path)
}

private func isIPv6LiteralHost(_ host: String) -> Bool {
    return host.contains(":")
}

func performPlainHTTPGet(host: String, port: Int, path: String) -> Int32 {
    var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
    var res: UnsafeMutablePointer<addrinfo>? = nil
    let portStr = String(port)
    let gaiStatus = host.withCString { hPtr in
        portStr.withCString { sPtr in
            getaddrinfo(hPtr, sPtr, &hints, &res)
        }
    }
    if gaiStatus != 0 {
        let msg = String(cString: gai_strerror(gaiStatus))
        _ = printError("getaddrinfo failed: \(msg)")
        return 1
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
        _ = printError("Could not connect to \(host):\(port)")
        return 1
    }

    defer { close(fd) }

    let hostHeaderHost = isIPv6LiteralHost(host) ? "[\(host)]" : host
    let defaultPort = 80
    let hostHeader = (port == defaultPort) ? hostHeaderHost : "\(hostHeaderHost):\(port)"
    let request = "GET \(path.isEmpty ? "/" : path) HTTP/1.1\r\nHost: \(hostHeader)\r\nUser-Agent: go2web-swift/1.0\r\nAccept: text/html, application/json\r\nConnection: close\r\n\r\n"

    let reqBytes = Array(request.utf8)
    var totalSent = 0
    while totalSent < reqBytes.count {
        let sent = reqBytes.withUnsafeBytes { buf -> Int in
            let base = buf.baseAddress!.advanced(by: totalSent)
            return send(fd, base, reqBytes.count - totalSent, 0)
        }
        if sent <= 0 {
            _ = printError("send failed.")
            return 1
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
            return 1
        }
    }

    let response = String(decoding: responseBytes, as: UTF8.self)

    if let sep = response.range(of: "\r\n\r\n") {
        let head = String(response[..<sep.lowerBound])
        let body = String(response[sep.upperBound...])
        let lines = head.split(whereSeparator: { $0.isNewline }).map(String.init)
        let statusLine = lines.first ?? ""
        let headers = lines.dropFirst().joined(separator: "\n")
        print(statusLine)
        print(headers)
        print(body)
    } else if let sep = response.range(of: "\n\n") {
        let head = String(response[..<sep.lowerBound])
        let body = String(response[sep.upperBound...])
        let lines = head.split(whereSeparator: { $0.isNewline }).map(String.init)
        let statusLine = lines.first ?? ""
        let headers = lines.dropFirst().joined(separator: "\n")
        print(statusLine)
        print(headers)
        print(body)
    } else {
        print(response)
    }

    return 0
}

func run() -> Int32 {
    let args = CommandLine.arguments
    // args[0] is the executable name.

    // If no additional arguments, show help.
    guard args.count > 1 else {
        return printHelp()
    }

    let index = 1
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "-h", "--help":
            return printHelp()

        case "-u":
            // Expect exactly one URL string following -u
            let nextIndex = index + 1
            guard nextIndex < args.count else {
                return printError("Missing URL after -u.\n\nTry: go2web -u https://example.com")
            }
            let urlString = args[nextIndex]
            do {
                let parsed = try parseURL(urlString)
                if parsed.scheme == "https" {
                    print("HTTPS support will be added later.")
                    return 0
                }
                return performPlainHTTPGet(host: parsed.host, port: parsed.port, path: parsed.path)
            } catch {
                if let e = error as? URLParseError {
                    return printError(e.localizedDescription)
                } else {
                    return printError("Failed to parse URL: \(urlString)")
                }
            }

        case "-s":
            // Consume all remaining tokens as the search term (supports multi-word)
            let nextIndex = index + 1
            guard nextIndex < args.count else {
                return printError("Missing search term after -s.\n\nTry: go2web -s swift concurrency tutorial")
            }
            let terms = args[nextIndex...].joined(separator: " ")
            print("[go2web] Would search for: \(terms)")
            return 0

        default:
            // Unknown flag or stray argument
            return printError("Unknown option or argument: \(arg).\n\nRun 'go2web -h' for usage.")
        }
    }

    // Fallback (should not reach here due to returns above)
    return 0
}

@main
struct Go2Web {
    static func main() {
        let code = run()
        exit(code)
    }
}
