# Swift-TLS-Client
A TLS Client written in Native Swift

**This is a custom Swift TLS Client. With this client you can utilize proxies that require authentication. You also have control over other important request attributes such as header order. This was written above NWConnection. I created this TLS-Client since there are No existing ones available across github or google. Additionally, `URLSession` does NOT work for proxies that require auth. I have found no way of using a proxy that requires auth using a high level Swift method such as URLSession or any of its delegates.**

- It is very simple to use:

- The proxy is expected to be a string in the following format:
    - "Host:Port:Username:Password"

For an http request to be sent out from an iOS device you MUST add the following entry into your info.plist file:
    - NSAllowsArbitraryLoads: true

**To setup a Client just do:**

```
let proxy = "host:port:username:password"

let client = Client(proxy: proxy)
```

The Client class is designed for concurency!

**To Make a Request:**

```
let response = await client.request(
    requestType: client.GET,
    endpoint: "https://us.bape.com/checkouts/c/17d8fa810ae255071f3ab664c094e876/thank_you",
    body: nil,
    headers: [
        "Connection": "close",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0.1 Safari/605.1.15",
        "Accept-Language": "en-US,en;q=0.9",
        "Sec-Fetch-Dest": "document",
        "Sec-Fetch-Mode": "navigate",
        "Sec-Fetch-Site": "none",
        "Priority": "u=0, i"
    ],
    headerOrder: [
        "Connection",
        "Accept",
        "User-Agent",
        "Accept-Language",
        "Sec-Fetch-Dest",
        "Sec-Fetch-Mode",
        "Sec-Fetch-Site",
        "Priority"
    ],
    maxReadBytes: 500000,
    followRedirect: true,
    maxRedirectsToFollow: 5
)
```

**The response contains a tupile of (response?, error?)**

- The response is of type:

```
struct HTTPResponse {
    var statusCode: Int
    var responseBody: String?
    var setCookies: [Cookie]
    var redirectURL: String?
}

struct Cookie {
    var name: String
    var value: String
    var domain: String?
    var path: String?
}
```

- The error is of type:

```
enum RequestError: Error {
    case proxyFormatError
    case proxyConnectError
    case requestError
    case urlFormatError
    case unknownError
}
```

**Printing the Response**

```
if let resp = response.0 {
    
    print("Response Status Code: \(resp.statusCode)")
    
    if let body = resp.responseBody {
        print("Response body: \(body)")
    }
    
    if let redirectURL = resp.redirectURL {
        print("Response redirect: \(redirectURL)")
    }
    
} else if let error = response.1 {
    print(error.localizedDescription)
}
```

- "requestType"
    - This param can be any string such as "GET", "POST", "PUT", etc. Or you can use client.GET so you dont mess up spelling

- "endpoint"
    - This is just the full url you want to request

- "body"
    - The body is an optional string
    
- "headers"
    - The headers param is a dictionary of header name to value
    
- "headerOrder"
    - The headerOrder param is a string array of the header order
    
- "maxReadBytes"
    - This param defaults to 500,000 bytes. This represents how much data to read from a response before closing. Its pretty low level and 500k should work for almost everything

- "followRedirect"
    - This is a bool to lets you control if the client follows redirects upon 302 status codes and a new redirect uri
    
- "maxRedirectsToFollow"
    - This is optional and defaults to 5 and it determines how many redirects the client will follow before quiting

# Additional Client Methods:

- func deleteCookieByName(name: String) {

- func getCookieByName(name: String) -> Cookie? {

- func updateCookieByName(name: String, value: String, domain: String?, path: String?) {

- func updateProxy(newProxy: String) {


The Client class will attempt to auto manage cookies for you by applying cookies to requests that contain the target domain and path.

This is super customizable and theres a lot of room for improvement. If you want to contribute just open an issue and I'll give you commit access.
