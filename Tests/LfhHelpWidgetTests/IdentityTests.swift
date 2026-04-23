import XCTest
@testable import LfhHelpWidget

final class IdentityTests: XCTestCase {
    func testAnonymousProducesNoQueryItems() {
        let items = Identity.anonymous.queryItems()
        XCTAssertTrue(items.isEmpty)
    }

    func testSignedProducesEmailSigVInOrder() {
        let id = Identity.signed(
            email: "user@example.com",
            name: nil,
            signature: "abc123",
            version: 3
        )
        let items = id.queryItems()
        XCTAssertEqual(items.map(\.name), ["email", "sig", "v"])
        XCTAssertEqual(items.first { $0.name == "email" }?.value, "user@example.com")
        XCTAssertEqual(items.first { $0.name == "sig" }?.value, "abc123")
        XCTAssertEqual(items.first { $0.name == "v" }?.value, "3")
    }

    func testSignedIncludesNameWhenProvided() {
        let id = Identity.signed(
            email: "user@example.com",
            name: "Alice Example",
            signature: "deadbeef",
            version: 1
        )
        let items = id.queryItems()
        XCTAssertEqual(items.map(\.name), ["email", "name", "sig", "v"])
        XCTAssertEqual(items.first { $0.name == "name" }?.value, "Alice Example")
    }

    func testSignedOmitsEmptyName() {
        let id = Identity.signed(
            email: "user@example.com",
            name: "",
            signature: "deadbeef",
            version: 1
        )
        let items = id.queryItems()
        XCTAssertFalse(items.contains { $0.name == "name" })
    }

    func testBuildIframeURLAppendsQueryItemsToBase() {
        let base = URL(string: "https://widget.example.com/widget/app1")!
        let id = Identity.signed(
            email: "u+tag@example.com",
            name: "Alice",
            signature: "hex",
            version: 2
        )
        let url = Identity.buildIframeURL(base: base, identity: id)
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return XCTFail("URL did not resolve as components")
        }
        XCTAssertEqual(components.path, "/widget/app1")
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "email" })?.value,
            "u+tag@example.com"
        )
        XCTAssertEqual(components.queryItems?.count, 4)
    }

    func testBuildIframeURLAnonymousReturnsBaseUnchanged() {
        let base = URL(string: "https://widget.example.com/widget/app1")!
        let url = Identity.buildIframeURL(base: base, identity: .anonymous)
        XCTAssertEqual(url, base)
    }
}
