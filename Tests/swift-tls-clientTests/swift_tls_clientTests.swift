import Testing
@testable import swift_tls_client

@Test func example() async throws {
    Task {
        let proxy = "host:port:username:password"
        
        let client = Client(proxy: proxy)
        
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
    }
}
