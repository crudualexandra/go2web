# go2web

`go2web` is a Swift command-line tool created for the Web Programming laboratory work.  
The goal of the project is to implement a small CLI web client that can make manual HTTP requests, search the web, and display human-readable responses without using built-in or third-party HTTP client libraries.

## Progress

### Step 1 — Basic CLI argument parsing

In this step, the basic command-line interface was implemented using `CommandLine.arguments`.

Implemented options:

```bash
go2web -h
go2web -u <URL>
go2web -s <search-term>
```

Current behavior:
    •    -h prints the help message.
    •    -u <URL> accepts a URL and prints a placeholder message.
    •    -s <search-term> accepts one or multiple search words and prints a placeholder search message.
    •    Missing or unknown arguments are handled with error messages.
    
Tested commands:
```bash
swift run go2web -h
swift run go2web -u http://example.com
swift run go2web -s swift sockets tutorial
```

Result:
```bash
go2web — Command-line tool

Usage:
  go2web -h
  go2web -u <URL>
  go2web -s <search-term>
```

### Step 2 — Manual URL parsing

In this step, manual URL parsing was added for `http://` and `https://` addresses.

The parser extracts:

- scheme
- host
- port
- path

Default ports are selected automatically:

- `http` → port `80`
- `https` → port `443`

Tested commands:

```bash
swift run go2web -u http://example.com
swift run go2web -u http://example.com/test/page
swift run go2web -u "https://example.com/search?q=test"
```

Example result:
```bash
[go2web] Parsed URL:
  scheme: https
  host:   example.com
  port:   443
  path:   /search?q=test
```
At this stage, the program still does not make a real network request. The parsed URL will be used in the next step to build a raw HTTP request over TCP sockets.



### Step 3 — Raw HTTP GET over POSIX sockets

In this step, the `-u` command was connected to a real HTTP request implementation.

The program now:

- parses the URL;
- creates a TCP socket using POSIX socket functions;
- resolves the host with `getaddrinfo`;
- connects to the server using `connect`;
- manually builds an HTTP/1.1 `GET` request as text;
- sends the request using `send`;
- reads the raw server response using `recv`;
- separates the HTTP headers from the response body.

No HTTP client libraries are used. The implementation does not use `URLSession`, `URLRequest`, `Data(contentsOf:)`, Alamofire, or any third-party HTTP client.

Tested command:

```bash
swift run go2web -u http://example.com
```

Result:
```bash
HTTP/1.1 200 OK
Content-Type: text/html
Transfer-Encoding: chunked

<!doctype html><html lang="en"><head><title>Example Domain</title>...
```
At this stage, the response is still printed mostly raw. HTML cleaning and human-readable formatting will be implemented in the next step.
