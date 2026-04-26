import Foundation

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

