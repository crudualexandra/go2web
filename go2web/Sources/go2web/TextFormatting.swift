import Foundation

func decodeCommonHTMLEntities(_ text: String) -> String {
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

