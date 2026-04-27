# go2web

redirect fix: Redirects were fixed in performPlainHTTPGet, performHTTPSGet, and performHTTPSGetRawHTML by using ResponseDecision with final, followRedirect, and fatalError.

Now redirects are counted before following the next Location header. If the limit of 5 is exceeded, the function returns fatalError and stops immediately without printing or caching the final response. resolveRelativePath handles relative redirects, and parseURL handles full redirect URLs.


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


### Step 7 — Search command preparation

In this step, the `-s` command was prepared for web search.

The program now:

- accepts one or multiple words after `-s`;
- builds a DuckDuckGo HTML search URL;
- encodes spaces as `+`;
- includes a parser prepared for extracting the top 10 results from DuckDuckGo HTML;
- extracts result title, link, and snippet when HTML content is available;
- does not use external HTML parser libraries;
- does not use `URLSession`, `URLRequest`, `Data(contentsOf:)`, or HTTP client libraries.
At this stage, real search fetching is not active yet because the selected DuckDuckGo HTML endpoint requires HTTPS. The search parser is already implemented and will be used after HTTPS transport support is added.


### Step 8 — HTTPS transport support

In this step, HTTPS support was added using Apple `Network.framework`.

The program still does not use `URLSession`, `URLRequest`, `Data(contentsOf:)`, or any HTTP client library. The HTTP request is still manually constructed as a raw HTTP/1.1 text request. `Network.framework` is used only as the TLS transport layer for HTTPS connections.


### Step 9 — Search top 10 results

In this step, the -s command was completed.

The program now:
    •    builds the DuckDuckGo HTML search URL;
    •    sends the request over HTTPS;
    •    receives the HTML response;
    •    parses the result titles and links manually;
    •    prints the top 10 search results;
    •    does not use URLSession, URLRequest, Data(contentsOf:), or HTTP client libraries.
This satisfies the main laboratory requirement for go2web -s <search-term>.
### Step 10 — Open search results by number

In this step, the search results became accessible through the CLI.

After running a search, the program saves the top result URLs into `.go2web-last-search`.

The search command uses Bing HTML results because DuckDuckGo returned an anti-bot challenge page during testing. The program still performs a manual HTTPS request and parses the returned HTML without using an HTTP client library.

```bash

sanduta@Crudus-MacBook-Air go2web % rm -rf .go2web-cache
rm -f .go2web-last-search
sanduta@Crudus-MacBook-Air go2web % swift run go2web -h
[1/1] Planning build
Building for debugging...
[1/1] Write swift-version--58304C5D6DBC2206.txt
Build of product 'go2web' complete! (0.15s)
go2web — Command-line tool

Usage:
  go2web -h
  go2web -u <URL>
  go2web -s <search-term>

Options:
  -h                Show this help message and exit.
  -u <URL>          Fetch the given URL over HTTP (HTTPS support will be added later).
  -s <term>         Search using the provided term (placeholder). Multiple words are allowed.

sanduta@Crudus-MacBook-Air go2web % swift run go2web -u http://example.com
Building for debugging...
[1/1] Write swift-version--58304C5D6DBC2206.txt
Build of product 'go2web' complete! (0.10s)
Example Domain
 Example Domain

 This domain is for use in documentation examples without needing permission. Avoid use in operations.

 Learn more
sanduta@Crudus-MacBook-Air go2web % swift run go2web -u http://example.com
Building for debugging...
[1/1] Write swift-version--58304C5D6DBC2206.txt
Build of product 'go2web' complete! (0.10s)
[CACHE HIT]
Example Domain
 Example Domain

 This domain is for use in documentation examples without needing permission. Avoid use in operations.

 Learn more
sanduta@Crudus-MacBook-Air go2web % swift run go2web -u https://example.com
Building for debugging...
[1/1] Write swift-version--58304C5D6DBC2206.txt
Build of product 'go2web' complete! (0.10s)
Example Domain
 Example Domain

 This domain is for use in documentation examples without needing permission. Avoid use in operations.

 Learn more
sanduta@Crudus-MacBook-Air go2web % swift run go2web -u http://httpbin.org/get
Building for debugging...
[1/1] Write swift-version--58304C5D6DBC2206.txt
Build of product 'go2web' complete! (0.10s)
{
  "args" : {

  },
  "headers" : {
    "User-Agent" : "go2web-swift\/1.0",
    "Host" : "httpbin.org",
    "X-Amzn-Trace-Id" : "Root=1-69edf3fe-7a58346e5cb6fbc3615986df",
    "Accept" : "text\/html, application\/json"
  },
  "origin" : "95.65.73.3",
  "url" : "http:\/\/httpbin.org\/get"
}
sanduta@Crudus-MacBook-Air go2web % swift run go2web -u http://httpbin.org/redirect/1
Building for debugging...
[1/1] Write swift-version--58304C5D6DBC2206.txt
Build of product 'go2web' complete! (0.10s)
{
  "args" : {

  },
  "headers" : {
    "User-Agent" : "go2web-swift\/1.0",
    "Host" : "httpbin.org",
    "X-Amzn-Trace-Id" : "Root=1-69edf484-47d1253713126a252febc2ae",
    "Accept" : "text\/html, application\/json"
  },
  "origin" : "95.65.73.3",
  "url" : "http:\/\/httpbin.org\/get"
}
sanduta@Crudus-MacBook-Air go2web % swift run go2web -s apple swift networking
Building for debugging...
[1/1] Write swift-version--58304C5D6DBC2206.txt
Build of product 'go2web' complete! (0.10s)
1. Official Apple Support Community
https://www.bing.com/ck/a?!&&p=c1f2169a2fd54f48ef2d996489d859a7179c20e5ef6b562bf64e1452c1bb5624JmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=38aaae97-3833-6060-2c80-b9d03938619b&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vd2VsY29tZQ&ntb=1
Find answers with millions of other Apple users in our vibrant community. Search discussions or ask a question about your product.

2. Apple support phone number - Apple Community
https://www.bing.com/ck/a?!&&p=47d46c1d34ed74347713019650fc58a6b7b2f851e2b3a82a6c622abccf144b79JmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=38aaae97-3833-6060-2c80-b9d03938619b&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1NTE0ODg5Mg&ntb=1
Sep 23, 2023 &#0183;&#32;The Apple Support phone number in the U.S. is 1-800-275-2273 For numbers in other locations, see: Contact Apple for support and service - Apple Support

3. Apple account login - Apple Community
https://www.bing.com/ck/a?!&&p=f94ac165c462db2e47704965dcfdbf087e408febfb6e9914e1bd77ae16e2d40dJmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=38aaae97-3833-6060-2c80-b9d03938619b&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1NTAwNjY1NQ&ntb=1
Jul 18, 2023 &#0183;&#32;Apple account login How can I be able to login to my apple account using my Apple ID without having iTunes or other apple applications being installed on my pc?

4. Apple Account - Apple Community
https://www.bing.com/ck/a?!&&p=468b275b1895d1c40bb8862a910b1ba9f4bf44e6bc26f5e3693bbae0a8714439JmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=38aaae97-3833-6060-2c80-b9d03938619b&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vY29tbXVuaXR5L2FwcGxlLWFjY291bnQ&ntb=1
Find answers with millions of other Apple Account users in our vibrant community. Search discussions or ask a question about Apple Account.

5. Contact Apple for support and service - Apple Community
https://www.bing.com/ck/a?!&&p=a7e6009dcbadd9560fcd66e8ae112cff166124aef37f60681887f75e748fd38dJmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=38aaae97-3833-6060-2c80-b9d03938619b&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1NTU1NDQyOA&ntb=1
Mar 30, 2024 &#0183;&#32;Apple may provide or recommend responses as a possible solution based on the information provided; every potential issue may involve several factors not detailed in the …

6. Verifying an Apple ID security alert email - Apple Community
https://www.bing.com/ck/a?!&&p=86312fbd7aa4ed769cde9f0f561fcaff61dbbfe04ebc4fff5df1d757d3e1c4a3JmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=38aaae97-3833-6060-2c80-b9d03938619b&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1NjE5MjM0OA&ntb=1
Nov 19, 2025 &#0183;&#32;Criminals are getting very good at imitating Apple messages and sometimes the only indication in an email is very subtle. Have a look at this thread. Someone registered an Apple ID with …

7. This account is locked and can't be used … - Apple Community
https://www.bing.com/ck/a?!&&p=8e78f9d40d2dc24c04e901815622f5966a0574fbc7cb3b5bff55af25ad73d538JmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=38aaae97-3833-6060-2c80-b9d03938619b&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1NTcwMTc2MA&ntb=1
Jul 31, 2024 &#0183;&#32;Managed to get this fixed - the only solution is abandoning the locked/disabled account and re-registering the device with new/different apple id. This required resetting the device by making …

8. What is Hollyhill, why did Apple.com bill… - Apple Community
https://www.bing.com/ck/a?!&&p=7d28cb0144556d276560ad7d9359973051c68b8245af292faf38a73f3fd21540JmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=38aaae97-3833-6060-2c80-b9d03938619b&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1NTQ4NzA3MQ&ntb=1
Feb 19, 2024 &#0183;&#32;Also review: If you don't recognize a charge - Apple Support See your subscriptions overview - Apple If you want to cancel a subscription from Apple - Apple Support Request a refund …

9. Locked out of iphone passcode - Apple Community
https://www.bing.com/ck/a?!&&p=1c5c452534f97de866759ee304ae78dda7772270c8ba6a7d87b5a0e003e08cefJmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=38aaae97-3833-6060-2c80-b9d03938619b&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1Mzg5NDM1MA&ntb=1
May 13, 2022 &#0183;&#32;Mary7902 Said: " Locked out of iphone passcode. " ------- Troubleshooting a Locked iPhone: Hold it Right There! Being Locked Out... Enter the passcode incorrectly too many times, and …

10. Iphone keeps asking for password you must… - Apple Community
https://www.bing.com/ck/a?!&&p=7eb1683c861131f93697ca3ecee27c66eb9c3e2154b2ce7400915126bff76d41JmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=38aaae97-3833-6060-2c80-b9d03938619b&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1NTk2OTUyNA&ntb=1
Feb 13, 2025 &#0183;&#32;Iphone keeps asking for password you must enter both your apple account and password My iPhone keeps asking for my account password at least 3 times a day! It prompts me to …

[Bing] Saved 10 URLs to .go2web-last-search
sanduta@Crudus-MacBook-Air go2web % swift run go2web -u 1
Building for debugging...
[1/1] Write swift-version--58304C5D6DBC2206.txt
Build of product 'go2web' complete! (0.10s)
[USING LAST SEARCH #1 -> https://www.bing.com/ck/a?!&&p=c1f2169a2fd54f48ef2d996489d859a7179c20e5ef6b562bf64e1452c1bb5624JmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=38aaae97-3833-6060-2c80-b9d03938619b&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vd2VsY29tZQ&ntb=1]
Please click here if the page does not redirect automatically ...
sanduta@Crudus-MacBook-Air go2web % swift run go2web -u 3
Building for debugging...
[1/1] Write swift-version--58304C5D6DBC2206.txt
Build of product 'go2web' complete! (0.10s)
[USING LAST SEARCH #3 -> https://www.bing.com/ck/a?!&&p=f94ac165c462db2e47704965dcfdbf087e408febfb6e9914e1bd77ae16e2d40dJmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=38aaae97-3833-6060-2c80-b9d03938619b&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1NTAwNjY1NQ&ntb=1]
Please click here if the page does not redirect automatically ...
sanduta@Crudus-MacBook-Air go2web % ls -la
total 24
drwxr-xr-x   9 sanduta  staff   288 Apr 26 14:18 .
drwxr-xr-x   6 sanduta  staff   192 Apr 26 13:54 ..
drwxr-xr-x  12 sanduta  staff   384 Apr 26 14:19 .build
-rw-r--r--   1 sanduta  staff   159 Apr 26 12:03 .gitignore
drwxr-xr-x   8 sanduta  staff   256 Apr 26 14:19 .go2web-cache
-rw-r--r--@  1 sanduta  staff  2516 Apr 26 14:18 .go2web-last-search
drwxr-xr-x   4 sanduta  staff   128 Apr 26 12:03 .swiftpm
-rw-r--r--@  1 sanduta  staff   234 Apr 26 13:25 Package.swift
drwxr-xr-x   3 sanduta  staff    96 Apr 26 12:03 Sources
sanduta@Crudus-MacBook-Air go2web % swift build -c release
cp .build/release/go2web ./go2web
chmod +x ./go2web
Building for production...
/Users/sanduta/go2web/go2web/Sources/go2web/go2web.swift:1292:9: warning: variable 'index' was never mutated; consider changing to 'let' constant
1290 |     }
1291 | 
1292 |     var index = 1
     |         `- warning: variable 'index' was never mutated; consider changing to 'let' constant
1293 | 
1294 |     while index < args.count {
[5/5] Linking go2web
Build complete! (4.90s)
sanduta@Crudus-MacBook-Air go2web % ./go2web -h
go2web — Command-line tool

Usage:
  go2web -h
  go2web -u <URL>
  go2web -s <search-term>

Options:
  -h                Show this help message and exit.
  -u <URL>          Fetch the given URL over HTTP (HTTPS support will be added later).
  -s <term>         Search using the provided term (placeholder). Multiple words are allowed.

sanduta@Crudus-MacBook-Air go2web % ./go2web -u https://example.com
Example Domain
 Example Domain

 This domain is for use in documentation examples without needing permission. Avoid use in operations.

 Learn more
sanduta@Crudus-MacBook-Air go2web % ./go2web -s apple swift networking
1. Official Apple Support Community
https://www.bing.com/ck/a?!&&p=fe11ecaf3028b4f73a9ccc6c465b1fbe2f0434d596dab8cd59a6b67b830187e1JmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=18b9143d-78b9-659c-2117-037a7942640a&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vd2VsY29tZQ&ntb=1
Find answers with millions of other Apple users in our vibrant community. Search discussions or ask a question about your product.

2. Apple support phone number - Apple Community
https://www.bing.com/ck/a?!&&p=275056c7a53601e26d26fe6cbb70ebd312434f0a52b58b2902784dd1568faa24JmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=18b9143d-78b9-659c-2117-037a7942640a&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1NTE0ODg5Mg&ntb=1
Sep 23, 2023 &#0183;&#32;The Apple Support phone number in the U.S. is 1-800-275-2273 For numbers in other locations, see: Contact Apple for support and service - Apple Support

3. Apple account login - Apple Community
https://www.bing.com/ck/a?!&&p=a5aa05a8ffd448434b56f7bd1f5d616875b536688ba3799832c5817cba4a5363JmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=18b9143d-78b9-659c-2117-037a7942640a&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1NTAwNjY1NQ&ntb=1
Jul 18, 2023 &#0183;&#32;Apple account login How can I be able to login to my apple account using my Apple ID without having iTunes or other apple applications being installed on my pc?

4. Apple Account - Apple Community
https://www.bing.com/ck/a?!&&p=fbf3e025b454e51c98b69bf0e2f4e4d993be7c6cccf7177824817c19d393dc8fJmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=18b9143d-78b9-659c-2117-037a7942640a&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vY29tbXVuaXR5L2FwcGxlLWFjY291bnQ&ntb=1
Find answers with millions of other Apple Account users in our vibrant community. Search discussions or ask a question about Apple Account.

5. Contact Apple for support and service - Apple Community
https://www.bing.com/ck/a?!&&p=a21f281fbc4edcd36cfd66eaa9f861bf1d9eb948a0f98f2335f9420167ba8c5bJmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=18b9143d-78b9-659c-2117-037a7942640a&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1NTU1NDQyOA&ntb=1
Mar 30, 2024 &#0183;&#32;Apple may provide or recommend responses as a possible solution based on the information provided; every potential issue may involve several factors not detailed in the …

6. Verifying an Apple ID security alert email - Apple Community
https://www.bing.com/ck/a?!&&p=7d4ba3923bd2f85fff70370eade6cbd6f0010b6eba3ad6332ce2f52166d90089JmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=18b9143d-78b9-659c-2117-037a7942640a&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1NjE5MjM0OA&ntb=1
Nov 19, 2025 &#0183;&#32;Criminals are getting very good at imitating Apple messages and sometimes the only indication in an email is very subtle. Have a look at this thread. Someone registered an Apple ID with …

7. This account is locked and can't be used … - Apple Community
https://www.bing.com/ck/a?!&&p=b8fc4a087581ce6977c2226c28d50c93c0b4c1b7000c891cdf9a464376244e35JmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=18b9143d-78b9-659c-2117-037a7942640a&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1NTcwMTc2MA&ntb=1
Jul 31, 2024 &#0183;&#32;Managed to get this fixed - the only solution is abandoning the locked/disabled account and re-registering the device with new/different apple id. This required resetting the device by making …

8. What is Hollyhill, why did Apple.com bill… - Apple Community
https://www.bing.com/ck/a?!&&p=17e85b8e44fef747dd24ab9809dbe7336ef970b571f66f18f0c777a5d92f8c7aJmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=18b9143d-78b9-659c-2117-037a7942640a&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1NTQ4NzA3MQ&ntb=1
Feb 19, 2024 &#0183;&#32;Also review: If you don't recognize a charge - Apple Support See your subscriptions overview - Apple If you want to cancel a subscription from Apple - Apple Support Request a refund …

9. Locked out of iphone passcode - Apple Community
https://www.bing.com/ck/a?!&&p=1f66934b6d69fa4ef765db41a7db19de3ca098673c42139195b15f144a897ef6JmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=18b9143d-78b9-659c-2117-037a7942640a&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1Mzg5NDM1MA&ntb=1
May 13, 2022 &#0183;&#32;Mary7902 Said: " Locked out of iphone passcode. " ------- Troubleshooting a Locked iPhone: Hold it Right There! Being Locked Out... Enter the passcode incorrectly too many times, and …

10. Iphone keeps asking for password you must… - Apple Community
https://www.bing.com/ck/a?!&&p=7b377b84baec01850283205601204d3b47986cf271c4726535de8dd152cdc409JmltdHM9MTc3NzE2MTYwMA&ptn=3&ver=2&hsh=4&fclid=18b9143d-78b9-659c-2117-037a7942640a&u=a1aHR0cHM6Ly9kaXNjdXNzaW9ucy5hcHBsZS5jb20vdGhyZWFkLzI1NTk2OTUyNA&ntb=1
Feb 13, 2025 &#0183;&#32;Iphone keeps asking for password you must enter both your apple account and password My iPhone keeps asking for my account password at least 3 times a day! It prompts me to …

[Bing] Saved 10 URLs to .go2web-last-search
sanduta@Crudus-MacBook-Air go2web % 
```




./go2web -h : Shows the help menu with all available CLI options.
./go2web -u https://wikipedia.org : Makes an HTTPS request to example.com and prints the page in human-readable text format.
./go2web -u https://wikipedia.org : Runs the same request again to demonstrate the cache mechanism. It should show [CACHE HIT] if the response was saved.
./go2web -u http://httpbin.org/get : Makes an HTTP request to a JSON endpoint and prints the JSON response in a readable formatted way.
./go2web -u http://httpbin.org/redirect/1 ; 
./go2web -u https://httpbin.org/redirect/6
: Tests redirect handling. The program follows the redirect and prints the final response.
./go2web -s chocolate information : Searches the web for "chocolate information" and prints the top 10 results.
./go2web -u 1 : Opens the first link f..../  rom the last search results saved by the program.

