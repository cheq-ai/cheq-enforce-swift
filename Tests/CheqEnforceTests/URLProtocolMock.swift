import Foundation

final class URLProtocolMock: URLProtocol {
    static var captured = [URLRequest]()
    /// Optional canned response per request; when nil, everything gets an
    /// empty 204 so the SDK proceeds.
    static var responder: ((URLRequest) -> (statusCode: Int, body: Data))?
    static func reset() {
        captured.removeAll()
        responder = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        URLProtocolMock.captured.append(request)
        let url = request.url ?? URL(string:"https://example.invalid")!
        let (statusCode, body) = URLProtocolMock.responder?(request) ?? (204, Data())
        let resp = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
