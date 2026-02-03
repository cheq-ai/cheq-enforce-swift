import Foundation

final class URLProtocolMock: URLProtocol {
    static var captured = [URLRequest]()
    static func reset() { captured.removeAll() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        URLProtocolMock.captured.append(request)
        // Respond 204 to everything so the SDK proceeds
        let url = request.url ?? URL(string:"https://example.invalid")!
        let resp = HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
