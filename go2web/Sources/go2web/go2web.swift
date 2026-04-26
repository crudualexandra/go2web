import Foundation


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
      -u <URL>          Open or fetch the given URL (placeholder, no network yet).
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
                print("[go2web] Parsed URL:")
                print("  scheme: \(parsed.scheme)")
                print("  host:   \(parsed.host)")
                print("  port:   \(parsed.port)")
                print("  path:   \(parsed.path)")
                return 0
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
