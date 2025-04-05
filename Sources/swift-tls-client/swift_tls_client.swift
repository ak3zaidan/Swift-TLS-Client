import UIKit
import Network

struct Proxy {
    var Host: String
    var Port: UInt16
    var Username: String
    var Password: String
}

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

enum RequestError: Error {
    case proxyFormatError
    case proxyConnectError
    case requestError
    case urlFormatError
    case unknownError
}

func httpRequest(requestType: String,
             endpoint: String,
             body: String?,
             proxy: Proxy,
             headers: [String:String],
             headerOrder: [String],
             cookies: [String:String],
             maxReadBytes: Int = 500000) async throws -> HTTPResponse {
    
    guard let url = URL(string: endpoint) else {
        throw RequestError.urlFormatError
    }

    let host = url.host ?? ""
    let path = url.path.isEmpty ? "/" : url.path
    let query = url.query ?? ""
    let fullPath = query.isEmpty ? path : "\(path)?\(query)"
    
    let request = buildHTTPRequest(method: requestType, path: fullPath, host: host, headers: headers, headerOrder: headerOrder, cookies: cookies, body: body)

    let responseData = try await makeRequest(httpRequest: request, proxy: proxy, url: url, maxReadBytes: maxReadBytes)
    
    guard let responseString = String(data: responseData, encoding: .utf8) else {
        throw RequestError.requestError
    }

    guard let httpResponse = parseHTTPResponse(rawResponse: responseString) else {
        throw RequestError.requestError
    }
    
    return httpResponse
}

func makeRequest(httpRequest: String, proxy: Proxy, url: URL, maxReadBytes: Int) async throws -> Data {
    let proxyEndpoint = NWEndpoint.hostPort(host: .init(proxy.Host),
                                            port: NWEndpoint.Port(integerLiteral: proxy.Port))
    let proxyConfig = ProxyConfiguration(httpCONNECTProxy: proxyEndpoint, tlsOptions: nil)
    proxyConfig.applyCredential(username: proxy.Username, password: proxy.Password)

    let parameters = NWParameters.tls
    let privacyContext = NWParameters.PrivacyContext(description: "ProxyConfig")
    privacyContext.proxyConfigurations = [proxyConfig]
    parameters.setPrivacyContext(privacyContext)

    let connection = NWConnection(
        to: .hostPort(
            host: .init(url.host ?? ""),
            port: .init(integerLiteral: UInt16(url.port ?? 443))
        ),
        using: parameters
    )

    return try await withCheckedThrowingContinuation { continuation in
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: httpRequest.data(using: .utf8), completion: .contentProcessed({ error in
                    if let error = error {
                        continuation.resume(throwing: RequestError.requestError)
                        return
                    }

                    Task {
                        do {
                            let finalData = try await readAllData(connection: connection, maxReadBytes: maxReadBytes)
                            continuation.resume(returning: finalData)
                        } catch {
                            continuation.resume(throwing: RequestError.proxyConnectError)
                        }
                    }
                }))
            case .failed(let error):
                continuation.resume(throwing: RequestError.proxyConnectError)

            case .cancelled:
                continuation.resume(throwing: RequestError.requestError)

            case .waiting(let error):
                continuation.resume(throwing: RequestError.requestError)

            default:
                break
            }
        }
        connection.start(queue: .global())
    }
}

func readAllData(connection: NWConnection, accumulatedData: Data = Data(), maxReadBytes: Int) async throws -> Data {
    return try await withCheckedThrowingContinuation { continuation in
        connection.receive(minimumIncompleteLength: 1, maximumLength: maxReadBytes) { data, context, isComplete, error in
            if let error = error {
                continuation.resume(throwing: error)
                return
            }

            let newAccumulatedData = accumulatedData + (data ?? Data())

            if isComplete {
                continuation.resume(returning: newAccumulatedData)
            } else {
                Task {
                    do {
                        let finalData = try await readAllData(connection: connection, accumulatedData: newAccumulatedData, maxReadBytes: maxReadBytes)
                        continuation.resume(returning: finalData)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

func buildHTTPRequest(method: String, path: String, host: String, headers: [String: String], headerOrder: [String], cookies: [String: String], body: String?) -> String {
    
    var httpRequest = "\(method) \(path) HTTP/1.1\r\n"
    httpRequest += "Host: \(host)\r\n"

    if headerOrder.isEmpty {
        for (header, value) in headers {
            httpRequest += "\(header): \(value)\r\n"
        }
    } else {
        for header in headerOrder {
            if let value = headers[header] {
                httpRequest += "\(header): \(value)\r\n"
            }
        }
    }

    if !cookies.isEmpty {
        let cookieHeader = cookies.map { "\($0)=\($1)" }.joined(separator: "; ")
        httpRequest += "Cookie: \(cookieHeader)\r\n"
    }

    httpRequest += "\r\n"

    if let requestBody = body {
        httpRequest += requestBody
    }

    return httpRequest
}

func parseHTTPResponse(rawResponse: String) -> HTTPResponse? {
    var statusCode = 0
    var responseBody: String?
    var setCookies: [Cookie] = []
    var redirectURL: String?

    let lines = rawResponse.components(separatedBy: CharacterSet.newlines).filter { !$0.isEmpty }

    if let statusLine = lines.first(where: { $0.starts(with: "HTTP/") }) {
        let components = statusLine.components(separatedBy: " ")
        if components.count >= 2, let code = Int(components[1]) {
            statusCode = code
        }
    }
    
    for line in lines {
        if line.lowercased().starts(with: "set-cookie:") {
            let fullCookieString = line.dropFirst("set-cookie:".count).trimmingCharacters(in: .whitespaces)
            let cookieComponents = fullCookieString.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            var cookie = Cookie(name: "", value: "", domain: nil, path: nil)
            
            if let first = cookieComponents.first {
                let parts = first.split(separator: "=", maxSplits: 1).map(String.init)
                
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts[1].trimmingCharacters(in: .whitespaces)
                    
                    cookie.name = key
                    cookie.value = value
                }
            }
            
            for component in cookieComponents {
                let parts = component.split(separator: "=", maxSplits: 1).map(String.init)
                
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = parts[1].trimmingCharacters(in: .whitespaces)

                    switch key {
                    case "domain":
                        cookie.domain = value
                    case "path":
                        cookie.path = value
                    default:
                        continue
                    }
                }
            }

            setCookies.append(cookie)
        } else if line.lowercased().starts(with: "location:") {
            redirectURL = line.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
        }
    }

    if let headersEndIndex = rawResponse.range(of: "\r\n\r\n", options: .literal)?.upperBound {
        let rawBody = String(rawResponse[headersEndIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        var body = ""
        let parts = rawBody.split(separator: "\r\n").map(String.init)
        var i = 0
        
        while i < parts.count {
            if let chunkSize = Int(parts[i], radix: 16) {
                if chunkSize == 0 {
                    break
                }
                i += 1
                if i < parts.count {
                    body += parts[i]
                }
            }
            i += 1
        }
        
        responseBody = body
    }

    return HTTPResponse(statusCode: statusCode, responseBody: responseBody, setCookies: setCookies, redirectURL: redirectURL)
}

func parseProxy(proxyString: String) -> Proxy? {
    let proxyDetails = proxyString.split(separator: ":").map(String.init)
    guard proxyDetails.count == 4, let port = UInt16(proxyDetails[1]) else {
        return nil
    }
    
    return Proxy(Host: proxyDetails[0], Port: port, Username: proxyDetails[2], Password: proxyDetails[3])
}

class Client {
    var GET = "GET"
    var POST = "POST"
    var proxy: Proxy
    var cookieJar: [Cookie] = []

    init(proxy: String) {
        if let proxy = parseProxy(proxyString: proxy) {
            self.proxy = proxy
        } else {
            self.proxy = Proxy(Host: "", Port: 5000, Username: "", Password: "")
        }
    }
    
    func request(requestType: String,
                 endpoint: String,
                 body: String?,
                 headers: [String:String],
                 headerOrder: [String],
                 maxReadBytes: Int = 500000,
                 followRedirect: Bool,
                 maxRedirectsToFollow: Int = 5) async -> (HTTPResponse?, RequestError?) {
        do {
            let response = try await httpRequest(requestType: requestType,
                                                 endpoint: endpoint,
                                                 body: body,
                                                 proxy: self.proxy,
                                                 headers: headers,
                                                 headerOrder: headerOrder,
                                                 cookies: cookiesForRequest(fullUrl: endpoint))
            
            response.setCookies.forEach { cookie in
                self.updateCookieByName(name: cookie.name,
                                        value: cookie.value,
                                        domain: cookie.domain,
                                        path: cookie.path)
            }
            
            if let redirectURL = response.redirectURL,
                followRedirect && maxRedirectsToFollow > 0 && response.statusCode == 302 {
                
                return await request(requestType: requestType,
                               endpoint: redirectURL,
                               body: body,
                               headers: headers,
                               headerOrder: headerOrder,
                               followRedirect: followRedirect,
                               maxRedirectsToFollow: maxRedirectsToFollow - 1)
            } else {
                return (response, nil)
            }
        } catch let error as RequestError {
            return (nil, error)
        } catch {
            return (nil, RequestError.unknownError)
        }
    }
    
    func cookiesForRequest(fullUrl: String) -> [String: String] {
        guard let url = URL(string: fullUrl), let urlHost = url.host else {
            return [:]
        }
        
        let urlPath = url.path.isEmpty ? "/" : url.path
        var cookiesForRequest: [String: String] = [:]
        
        for cookie in self.cookieJar {
            // Check if the cookie's domain matches the URL's host
            if let cookieDomain = cookie.domain, urlHost.contains(cookieDomain) || cookieDomain.contains(urlHost) {
                // Check if the cookie's path is applicable to the URL's path
                if let cookiePath = cookie.path, urlPath.starts(with: cookiePath) {
                    if !cookie.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                        !cookie.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        cookiesForRequest[cookie.name] = cookie.value
                    }
                } else if cookie.path == nil {
                    if !cookie.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                        !cookie.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // If no path is specified, assume the cookie applies to the entire domain
                        cookiesForRequest[cookie.name] = cookie.value
                    }
                }
            } else if cookie.domain == nil {
                // If no domain is specified, assume the cookie applies to any domain
                if !cookie.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !cookie.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    cookiesForRequest[cookie.name] = cookie.value
                }
            }
        }
        
        return cookiesForRequest
    }

    func deleteCookieByName(name: String) {
        cookieJar.removeAll { $0.name == name }
    }

    func getCookieByName(name: String) -> Cookie? {
        return cookieJar.first { $0.name == name }
    }

    func updateCookieByName(name: String, value: String, domain: String?, path: String?) {
        if let index = cookieJar.firstIndex(where: { $0.name == name }) {
            cookieJar[index] = Cookie(name: name, value: value, domain: domain, path: path)
        } else {
            let newCookie = Cookie(name: name, value: value, domain: domain, path: path)
            cookieJar.append(newCookie)
        }
    }

    func updateProxy(newProxy: String) {
        if let proxy = parseProxy(proxyString: newProxy) {
            self.proxy = proxy
        }
    }
}
