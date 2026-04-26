import Foundation

func cacheDirectoryURL() -> URL {
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".go2web-cache", isDirectory: true)
}

func safeCacheFilename(for url: String) -> String {
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

func cacheFileURL(for url: String) -> URL {
    return cacheDirectoryURL().appendingPathComponent(safeCacheFilename(for: url))
}

func readCache(for url: String, ttl: TimeInterval = 300) -> HTTPFetchResult? {
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

func saveCache(for url: String, result: HTTPFetchResult) {
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

func lastSearchFileURL() -> URL {
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".go2web-last-search")
}

func saveLastSearch(urls: [String]) {
    let content = urls.joined(separator: "\n")
    try? content.write(to: lastSearchFileURL(), atomically: true, encoding: .utf8)
}

func loadLastSearch() -> [String]? {
    guard let raw = try? String(contentsOf: lastSearchFileURL(), encoding: .utf8) else {
        return nil
    }
    return raw.split(whereSeparator: { $0.isNewline }).map(String.init)
}

