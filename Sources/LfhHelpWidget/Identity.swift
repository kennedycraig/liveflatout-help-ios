import Foundation

/// End-user identity for the widget iframe.
///
/// - `anonymous`: the iframe signs in with `signInAnonymously` server-side.
/// - `signed`: the iframe consumes `?email=&sig=&v=` and calls
///   `widgetMintToken` to upgrade to a Firebase custom token.
///   See spec §5.1 for the wire format.
public enum Identity: Equatable, Sendable {
    case anonymous
    case signed(email: String, name: String?, signature: String, version: Int)

    /// URL query items to append to the iframe URL. Empty for `.anonymous`.
    public func queryItems() -> [URLQueryItem] {
        switch self {
        case .anonymous:
            return []
        case let .signed(email, name, signature, version):
            var items: [URLQueryItem] = [URLQueryItem(name: "email", value: email)]
            if let name, !name.isEmpty {
                items.append(URLQueryItem(name: "name", value: name))
            }
            items.append(URLQueryItem(name: "sig", value: signature))
            items.append(URLQueryItem(name: "v", value: String(version)))
            return items
        }
    }

    /// Appends `queryItems()` to `base` using `URLComponents`. Returns `base`
    /// unchanged for `.anonymous`.
    public static func buildIframeURL(base: URL, identity: Identity) -> URL {
        let extra = identity.queryItems()
        if extra.isEmpty { return base }
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base
        }
        var items = components.queryItems ?? []
        items.append(contentsOf: extra)
        components.queryItems = items
        return components.url ?? base
    }
}
