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
            // Placeholder behavior (no network):
            print("[go2web] Would open URL: \(urlString)")
            return 0

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
