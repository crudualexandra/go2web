import Foundation

func run() -> Int32 {
    let args = CommandLine.arguments

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
            let nextIndex = index + 1

            guard nextIndex < args.count else {
                return printError("Missing URL after -u.\n\nTry: go2web -u https://example.com")
            }

            let urlString = args[nextIndex]

            var resolvedURLString = urlString
            if let idx = Int(urlString), (1...10).contains(idx) {
                if let urls = loadLastSearch(), idx <= urls.count {
                    resolvedURLString = urls[idx - 1]
                    print("[USING LAST SEARCH #\(idx) -> \(resolvedURLString)]")
                } else {
                    return printError("No last search results found or index out of range. Run 'go2web -s <term>' first.")
                }
            }

            do {
                let parsed = try parseURL(resolvedURLString)

                if let cached = readCache(for: resolvedURLString) {
                    print("[CACHE HIT]")
                    print(cached.readableBody)
                    return 0
                }

                let result: HTTPFetchResult?
                if parsed.scheme == "https" {
                    result = performHTTPSGet(host: parsed.host, port: parsed.port, path: parsed.path)
                } else {
                    result = performPlainHTTPGet(host: parsed.host, port: parsed.port, path: parsed.path)
                }

                guard let final = result else { return 1 }

                print(final.readableBody)

                if final.statusCode >= 200 && final.statusCode < 300 {
                    saveCache(for: resolvedURLString, result: final)
                }

                return 0
            } catch {
                if let e = error as? URLParseError {
                    return printError(e.localizedDescription)
                } else {
                    return printError("Failed to parse URL: \(resolvedURLString)")
                }
            }

        case "-s":
            let nextIndex = index + 1
            guard nextIndex < args.count else {
                return printError("Missing search term after -s.\n\nTry: go2web -s swift concurrency tutorial")
            }
            let terms = args[nextIndex...].joined(separator: " ")
            let exactTerms = "\"\(terms)\""
            let query = exactTerms
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
                .replacingOccurrences(of: "%20", with: "+") ?? terms.replacingOccurrences(of: " ", with: "+")

            let searchURL = "https://www.bing.com/search?q=\(query)&setlang=en-US&cc=US&mkt=en-US"
            do {
                let parsed = try parseURL(searchURL)
                if parsed.scheme == "https" {
                    if let (status, contentType, rawHTML) = performHTTPSGetRawHTML(host: parsed.host, port: parsed.port, path: parsed.path) {
                        if status >= 200 && status < 300 {
                            let results = parseBingHTML(rawHTML)
                            if results.isEmpty {
                                saveLastSearch(urls: [])
                                // Save first 10000 characters of rawHTML for debugging
                                let debugSnippet = String(rawHTML.prefix(10_000))
                                let debugURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("bing_debug.html")
                                try? debugSnippet.write(to: debugURL, atomically: true, encoding: .utf8)
                                print("No results parsed.")
                                print("Debug HTML saved to bing_debug.html")
                            } else {
                                for (idx, r) in results.enumerated() {
                                    print("\(idx + 1). \(r.title)")
                                    print(r.link)
                                    if let s = r.snippet, !s.isEmpty { print(s) }
                                    print("")
                                }
                                let urlsToSave = results.map { $0.link }
                                saveLastSearch(urls: Array(urlsToSave.prefix(10)))
                                print("[Bing] Saved \(min(10, urlsToSave.count)) URLs to .go2web-last-search")
                            }
                            return 0
                        } else {
                            print("[Bing] Search request failed with status: \(status). Content-Type: \(contentType ?? "-")")
                            return 1
                        }
                    } else {
                        print("Failed to perform HTTPS search request.")
                        return 1
                    }
                } else {
                    print("Bing HTML search requires HTTPS.")
                    return 1
                }
            } catch {
                return printError("Failed to build search URL.")
            }

        default:
            return printError("Unknown option or argument: \(arg).\n\nRun 'go2web -h' for usage.")
        }

    
    }

    return 0
}

