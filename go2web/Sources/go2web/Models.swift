import Foundation

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

