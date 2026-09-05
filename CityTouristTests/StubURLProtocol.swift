import Foundation

/// Intercepts URLSession traffic so the Places tests exercise the real request
/// construction, decoding and mapping without touching the network (or the
/// billing account).
final class StubURLProtocol: URLProtocol {

    // URLSession instantiates URLProtocol subclasses itself, so the stub's
    // state has to be static. That makes it shared, which is why the suite
    // using it is marked .serialized — see PlacesAPITests. The lock guards
    // against the session's own background queue racing the test thread.
    private static let lock = NSLock()
    private static var _handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var _recorded: [URLRequest] = []

    /// Set per test. Receives the outgoing request, returns the canned reply.
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    /// Every request the stub saw, so tests can assert on headers and bodies.
    static var recorded: [URLRequest] { lock.withLock { _recorded } }

    static func reset() {
        lock.withLock {
            _handler = nil
            _recorded = []
        }
    }

    /// A session wired to this stub.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func respond(status: Int = 200, json: String) {
        handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self._recorded.append(request) }
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
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

extension URLRequest {
    /// URLProtocol strips httpBody into a stream, so read it back for assertions.
    var stubBody: [String: Any]? {
        var data = httpBody
        if data == nil, let stream = httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = Data()
            let size = 4096
            var chunk = [UInt8](repeating: 0, count: size)
            while stream.hasBytesAvailable {
                let read = stream.read(&chunk, maxLength: size)
                if read <= 0 { break }
                buffer.append(contentsOf: chunk[0..<read])
            }
            data = buffer
        }
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
