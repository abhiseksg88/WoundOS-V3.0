import Foundation

/// A `URLProtocol` subclass that intercepts all requests and returns canned
/// responses via a static `requestHandler` closure.
///
/// Usage:
/// ```
/// URLProtocolMock.requestHandler = { request in
///     let response = HTTPURLResponse(url: request.url!, statusCode: 200, ...)
///     return (response!, someData)
/// }
/// ```
final class URLProtocolMock: URLProtocol {

    /// Set this per-test to control the response for every intercepted request.
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Create a `URLSession` wired to `URLProtocolMock`.
func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [URLProtocolMock.self]
    return URLSession(configuration: config)
}
