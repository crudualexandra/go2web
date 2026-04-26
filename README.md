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


### Step 4 — Human-readable response formatting

In this step, raw HTTP responses were converted into human-readable output.

The program now:

- reads the `Content-Type` header;
- removes HTML tags from `text/html` responses;
- removes `script` and `style` blocks;
- decodes common HTML entities;
- pretty-prints JSON responses when the content type is `application/json`;
- handles `Transfer-Encoding: chunked` responses by removing chunk size markers before formatting the body.

Tested command:

```bash
swift run go2web -u http://example.com
```
Result:
```bash
Example Domain

This domain is for use in documentation examples without needing permission. Avoid use in operations.

Learn more
```
This step satisfies the requirement that responses should be human-readable and not printed as raw HTML.


### Step 5 — HTTP redirect handling

In this step, HTTP redirect support was added.

The program now detects redirect status codes:

- `301`
- `302`
- `303`
- `307`
- `308`

When a redirect response is received, the program reads the `Location` header and follows the new address. Both absolute and relative redirect locations are supported. A maximum limit of 5 redirects is used to avoid infinite redirect loops.


### Step 6 — File-based HTTP cache

In this step, a simple file-based cache mechanism was added.

The program now creates a local folder named `.go2web-cache` in the current working directory. Successful GET responses are saved in this folder.

Each cache file stores:

- timestamp
- status code
- content type
- human-readable body

The cache TTL is 300 seconds. If the same URL is requested again within this time, the program reads the saved response from cache instead of making a new network request.
