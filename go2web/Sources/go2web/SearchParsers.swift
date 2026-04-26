import Foundation

private func percentDecode(_ s: String) -> String {
    return s.removingPercentEncoding ?? s
}

func parseDuckDuckGoHTML(_ html: String) -> [SearchResult] {
    // Normalize newlines
    let text = html.replacingOccurrences(of: "\r\n", with: "\n")
                   .replacingOccurrences(of: "\r", with: "\n")

    // Broad anchor regex to capture attributes and inner HTML
    let anchorPattern = #"<a\b([^>]*)>([\s\S]*?)</a>"#
    guard let anchorRe = try? NSRegularExpression(pattern: anchorPattern, options: [.caseInsensitive]) else { return [] }

    // Regexes to extract attributes and inspect content
    let hrefRe = try? NSRegularExpression(pattern: #"href\s*=\s*["']([^"']+)["']"#, options: [.caseInsensitive])
    let classRe = try? NSRegularExpression(pattern: #"class\s*=\s*["']([^"']+)["']"#, options: [.caseInsensitive])

    func containsResultClass(_ classAttr: String) -> Bool {
        classAttr.lowercased().contains("result__a")
    }

    // Helper to strip tags and clean text
    func stripTagsAndClean(_ s: String) -> String {
        var t = s
        if let tagRe = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let r = NSRange(t.startIndex..<t.endIndex, in: t)
            t = tagRe.stringByReplacingMatches(in: t, options: [], range: r, withTemplate: " ")
        }
        t = decodeCommonHTMLEntities(t)
        if let spaceRe = try? NSRegularExpression(pattern: "[ \\t]+", options: []) {
            let r = NSRange(t.startIndex..<t.endIndex, in: t)
            t = spaceRe.stringByReplacingMatches(in: t, options: [], range: r, withTemplate: " ")
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Helper to normalize links according to rules
    func normalizeLink(_ raw: String) -> String? {
        var link = raw.replacingOccurrences(of: "&amp;", with: "&")
        // protocol-relative
        if link.hasPrefix("//") { link = "https:" + link }
        // if DDG redirect with uddg, decode target
        if let range = link.range(of: "uddg=") {
            let after = link[range.upperBound...]
            let value = after.split(separator: "&", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? String(after)
            let decoded = percentDecode(value)
            link = decoded
        } else if link.hasPrefix("/l/?") || link.hasPrefix("/l?") {
            // DDG redirect without uddg: prefix site
            link = "https://duckduckgo.com" + link
        }
        let lower = link.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
        return link
    }

    var results: [SearchResult] = []
    var seen: Set<String> = []

    let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
    anchorRe.enumerateMatches(in: text, options: [], range: nsrange) { match, _, stop in
        guard let match = match, match.numberOfRanges >= 3 else { return }
        guard let attrsRange = Range(match.range(at: 1), in: text),
              let bodyRange = Range(match.range(at: 2), in: text) else { return }

        let attrs = String(text[attrsRange])
        let bodyHTML = String(text[bodyRange])

        // Extract href
        var href: String? = nil
        if let hrefRe = hrefRe {
            let ns = NSRange(attrs.startIndex..<attrs.endIndex, in: attrs)
            if let m = hrefRe.firstMatch(in: attrs, options: [], range: ns), m.numberOfRanges >= 2,
               let r = Range(m.range(at: 1), in: attrs) {
                href = String(attrs[r])
            }
        }
        guard let rawHref = href else { return }

        // Extract class
        var classAttr: String = ""
        if let classRe = classRe {
            let ns = NSRange(attrs.startIndex..<attrs.endIndex, in: attrs)
            if let m = classRe.firstMatch(in: attrs, options: [], range: ns), m.numberOfRanges >= 2,
               let r = Range(m.range(at: 1), in: attrs) {
                classAttr = String(attrs[r])
            }
        }

        // Determine if this anchor should be considered a result
        let lowerHref = rawHref.lowercased()
        let isResult = containsResultClass(classAttr) || lowerHref.contains("uddg=") || lowerHref.hasPrefix("/l/?") || lowerHref.hasPrefix("/l?")
        if !isResult { return }

        // Clean title
        let title = stripTagsAndClean(bodyHTML)
        if title.isEmpty { return }

        // Normalize link
        guard let link = normalizeLink(rawHref) else { return }
        if seen.contains(link) { return }

        results.append(SearchResult(title: title, link: link, snippet: nil))
        seen.insert(link)
        if results.count >= 10 { stop.pointee = true }
    }

    if !results.isEmpty {
        return results
    }

    // Fallback extraction: scan all hrefs and build reasonable results
    guard let hrefScanRe = try? NSRegularExpression(pattern: #"href\s*=\s*[\"']([^\"']+)[\"']"#, options: [.caseInsensitive]) else {
        return results
    }

    // Map of link -> title if found from an anchor
    var linkToTitle: [String: String] = [:]

    // First, try to pair hrefs with nearby anchor text using the broad anchor regex
    do {
        let anchorPattern = #"<a\b([^>]*)>([\s\S]*?)</a>"#
        let anchorRe = try NSRegularExpression(pattern: anchorPattern, options: [.caseInsensitive])
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        anchorRe.enumerateMatches(in: text, options: [], range: nsrange) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 3,
                  let attrsRange = Range(match.range(at: 1), in: text),
                  let bodyRange = Range(match.range(at: 2), in: text) else { return }
            let attrs = String(text[attrsRange])
            let bodyHTML = String(text[bodyRange])

            if let m = hrefScanRe.firstMatch(in: attrs, options: [], range: NSRange(attrs.startIndex..<attrs.endIndex, in: attrs)),
               m.numberOfRanges >= 2,
               let r = Range(m.range(at: 1), in: attrs) {
                let rawHref = String(attrs[r])
                var link = rawHref.replacingOccurrences(of: "&amp;", with: "&")
                if let range = link.range(of: "uddg=") {
                    let after = link[range.upperBound...]
                    let value = after.split(separator: "&", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? String(after)
                    link = percentDecode(value)
                } else if link.hasPrefix("//") {
                    link = "https:" + link
                }
                let lower = link.lowercased()
                if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
                    let cleanedTitle = stripTagsAndClean(bodyHTML)
                    if !cleanedTitle.isEmpty {
                        linkToTitle[link] = cleanedTitle
                    }
                }
            }
        }
    } catch {
        // ignore
    }

    // Now scan all hrefs and build results
    let scanRange = NSRange(text.startIndex..<text.endIndex, in: text)
    hrefScanRe.enumerateMatches(in: text, options: [], range: scanRange) { match, _, stop in
        guard let match = match, match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: text) else { return }
        var link = String(text[r]).replacingOccurrences(of: "&amp;", with: "&")

        // uddg decoding
        if let range = link.range(of: "uddg=") {
            let after = link[range.upperBound...]
            let value = after.split(separator: "&", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? String(after)
            link = percentDecode(value)
        } else if link.hasPrefix("//") {
            link = "https:" + link
        }

        let lower = link.lowercased()
        // Ignore unwanted links
        if lower.contains("duckduckgo.com") || lower.hasPrefix("javascript:") || lower.hasPrefix("#") || lower.contains("/settings") || lower.contains("/feedback") || lower.contains("/html/") {
            return
        }

        // Keep only absolute http(s)
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return }

        if seen.contains(link) { return }

        // Title preference: from anchor mapping if available; otherwise hostname or URL
        var title = linkToTitle[link] ?? ""
        if title.isEmpty {
            if let hostStart = link.range(of: "://")?.upperBound {
                let after = link[hostStart...]
                let host = after.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? String(after)
                title = host
            } else {
                title = link
            }
        }
        title = stripTagsAndClean(title)
        if title.isEmpty { title = link }

        results.append(SearchResult(title: title, link: link, snippet: nil))
        seen.insert(link)
        if results.count >= 10 { stop.pointee = true }
    }

    return results
}

func parseBingHTML(_ html: String) -> [SearchResult] {
    // Normalize newlines
    let text = html.replacingOccurrences(of: "\r\n", with: "\n")
                   .replacingOccurrences(of: "\r", with: "\n")

    // Helper to strip tags and clean
    func clean(_ s: String) -> String {
        var t = s
        if let tagRe = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let r = NSRange(t.startIndex..<t.endIndex, in: t)
            t = tagRe.stringByReplacingMatches(in: t, options: [], range: r, withTemplate: " ")
        }
        t = decodeCommonHTMLEntities(t)
        if let spaceRe = try? NSRegularExpression(pattern: "[ \t]+", options: []) {
            let r = NSRange(t.startIndex..<t.endIndex, in: t)
            t = spaceRe.stringByReplacingMatches(in: t, options: [], range: r, withTemplate: " ")
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Match Bing result blocks
    guard let liRe = try? NSRegularExpression(pattern: #"<li\b[^>]*class=\"[^\"]*b_algo[^\"]*\"[^>]*>([\s\S]*?)</li>"#, options: [.caseInsensitive]) else {
        return []
    }

    // Match title and link inside h2 > a
    let titleLinkRe = try? NSRegularExpression(pattern: #"<h2[^>]*>\s*<a\b[^>]*href=\"([^\"]+)\"[^>]*>([\s\S]*?)</a>\s*</h2>"#, options: [.caseInsensitive])
    // Match snippet paragraph
    let snippetRe = try? NSRegularExpression(pattern: #"<p[^>]*>([\s\S]*?)</p>"#, options: [.caseInsensitive])

    var results: [SearchResult] = []
    var seen: Set<String> = []

    let nsText = NSRange(text.startIndex..<text.endIndex, in: text)
    liRe.enumerateMatches(in: text, options: [], range: nsText) { li, _, stop in
        guard let li = li, li.numberOfRanges >= 2, let liRange = Range(li.range(at: 1), in: text) else { return }
        let block = String(text[liRange])

        var link: String? = nil
        var titleHTML: String? = nil

        if let titleLinkRe = titleLinkRe {
            let ns = NSRange(block.startIndex..<block.endIndex, in: block)
            if let m = titleLinkRe.firstMatch(in: block, options: [], range: ns), m.numberOfRanges >= 3,
               let hrefR = Range(m.range(at: 1), in: block),
               let titleR = Range(m.range(at: 2), in: block) {
                link = String(block[hrefR])
                titleHTML = String(block[titleR])
            }
        }

        guard var rawLink = link, let titleHTMLUnwrapped = titleHTML else { return }

        rawLink = rawLink.replacingOccurrences(of: "&amp;", with: "&")
        let lower = rawLink.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return }
        if seen.contains(rawLink) { return }

        let title = clean(titleHTMLUnwrapped)
        var snippet: String? = nil
        if let snippetRe = snippetRe {
            let ns = NSRange(block.startIndex..<block.endIndex, in: block)
            if let m = snippetRe.firstMatch(in: block, options: [], range: ns), m.numberOfRanges >= 2,
               let sR = Range(m.range(at: 1), in: block) {
                let rawSnippet = String(block[sR])
                let cleaned = clean(rawSnippet)
                if !cleaned.isEmpty { snippet = cleaned }
            }
        }

        results.append(SearchResult(title: title, link: rawLink, snippet: snippet))
        seen.insert(rawLink)
        if results.count >= 10 { stop.pointee = true }
    }

    return results
}

