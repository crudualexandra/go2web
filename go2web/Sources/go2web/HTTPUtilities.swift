import Foundation

enum ResponseDecision {
    case final(HTTPFetchResult)
    case followRedirect
    case fatalError
}

func resolveRelativePath(basePath: String, relative: String) -> String {
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

func isIPv6LiteralHost(_ host: String) -> Bool {
    return host.contains(":")
}

