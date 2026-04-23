import XCTest
@testable import LfhHelpWidget

/// In-memory URLProtocol stub — intercepts every request on the stubbed session.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        let status: Int
        let body: Data
    }
    nonisolated(unsafe) static var nextStub: Stub?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lastRequest = request
        // Drain the body via `httpBodyStream` if needed — URLProtocol can
        // receive the body as either `httpBody` or a stream.
        if StubURLProtocol.lastRequest?.httpBody == nil,
           let stream = request.httpBodyStream {
            var data = Data()
            stream.open()
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer {
                buf.deallocate()
                stream.close()
            }
            while stream.hasBytesAvailable {
                let read = stream.read(buf, maxLength: 4096)
                if read <= 0 { break }
                data.append(buf, count: read)
            }
            var mutated = request
            mutated.httpBody = data
            StubURLProtocol.lastRequest = mutated
        }
        guard let stub = StubURLProtocol.nextStub else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotLoadFromNetwork))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func makeStubbedSession() -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: cfg)
}

final class LfhHelpClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.nextStub = nil
        StubURLProtocol.lastRequest = nil
    }

    func testIssueSignatureSendsCallableEnvelope() async throws {
        StubURLProtocol.nextStub = .init(
            status: 200,
            body: #"{"result":{"email":"user@example.com","sig":"abc","v":2}}"#.data(using: .utf8)!
        )
        let client = LfhHelpClient(config: .production, session: makeStubbedSession())

        _ = try await client.issueSignature(appId: "app1", idToken: "tok", name: "Alice")

        let req = StubURLProtocol.lastRequest
        XCTAssertEqual(req?.url, LfhHelpConfig.production.issueSignatureURL)
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(req?.httpBody)
        let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let data = parsed?["data"] as? [String: Any]
        XCTAssertEqual(data?["appId"] as? String, "app1")
        XCTAssertEqual(data?["idToken"] as? String, "tok")
        XCTAssertEqual(data?["name"] as? String, "Alice")
    }

    func testIssueSignatureOmitsNameWhenNil() async throws {
        StubURLProtocol.nextStub = .init(
            status: 200,
            body: #"{"result":{"email":"x@y.com","sig":"s","v":1}}"#.data(using: .utf8)!
        )
        let client = LfhHelpClient(config: .production, session: makeStubbedSession())

        _ = try await client.issueSignature(appId: "app1", idToken: "tok", name: nil)

        let body = try XCTUnwrap(StubURLProtocol.lastRequest?.httpBody)
        let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let data = parsed?["data"] as? [String: Any]
        XCTAssertNil(data?["name"])
    }

    func testIssueSignatureReturnsIdentity() async throws {
        StubURLProtocol.nextStub = .init(
            status: 200,
            body: #"{"result":{"email":"u@x.com","name":"Alice","sig":"deadbeef","v":7}}"#.data(using: .utf8)!
        )
        let client = LfhHelpClient(config: .production, session: makeStubbedSession())

        let identity = try await client.issueSignature(appId: "app1", idToken: "tok", name: "Alice")

        guard case let .signed(email, name, sig, v) = identity else {
            return XCTFail("expected .signed identity, got \(identity)")
        }
        XCTAssertEqual(email, "u@x.com")
        XCTAssertEqual(name, "Alice")
        XCTAssertEqual(sig, "deadbeef")
        XCTAssertEqual(v, 7)
    }

    func testIssueSignatureMapsCallableErrorToLfhError() async throws {
        StubURLProtocol.nextStub = .init(
            status: 403,
            body: #"{"error":{"message":"project not trusted for this app","status":"PERMISSION_DENIED"}}"#.data(using: .utf8)!
        )
        let client = LfhHelpClient(config: .production, session: makeStubbedSession())

        do {
            _ = try await client.issueSignature(appId: "app1", idToken: "tok", name: nil)
            XCTFail("expected throw")
        } catch let LfhHelpClient.Error.callable(status, message) {
            XCTAssertEqual(status, "PERMISSION_DENIED")
            XCTAssertEqual(message, "project not trusted for this app")
        } catch {
            XCTFail("expected .callable, got \(error)")
        }
    }

    func testIssueSignatureHandlesNon2xxWithoutErrorEnvelope() async throws {
        StubURLProtocol.nextStub = .init(
            status: 502,
            body: Data("bad gateway".utf8)
        )
        let client = LfhHelpClient(config: .production, session: makeStubbedSession())

        do {
            _ = try await client.issueSignature(appId: "app1", idToken: "tok", name: nil)
            XCTFail("expected throw")
        } catch LfhHelpClient.Error.httpStatus(let status) {
            XCTAssertEqual(status, 502)
        } catch {
            XCTFail("expected .httpStatus, got \(error)")
        }
    }
}
