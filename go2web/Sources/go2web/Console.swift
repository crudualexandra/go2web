import Foundation

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

