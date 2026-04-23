import Foundation

/// Talks to the helpdesk project's widget callables.
///
/// This client is deliberately *unaware* of Firebase. The host app owns its
/// Firebase Auth setup and passes a raw ID token string. That keeps the
/// SPM package a leaf library — no FirebaseAuth or FirebaseFunctions pods
/// pulled into the host app just to embed the widget.
public actor LfhHelpClient {
    public enum Error: Swift.Error, Equatable {
        case httpStatus(Int)
        case callable(status: String, message: String)
        case malformedResponse
    }

    private let config: LfhHelpConfig
    private let session: URLSession

    public init(config: LfhHelpConfig = .production, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Exchanges a host-app Firebase ID token for a Secure-Mode identity.
    ///
    /// - Parameters:
    ///   - appId: helpdesk app slug (e.g. `"app1"`).
    ///   - idToken: ID token obtained via `Auth.auth().currentUser?.getIDToken()`
    ///     *in the host app's Firebase project* (which must be listed on
    ///     `/apps/{appId}.trustedProjects[]`).
    ///   - name: optional display name; the server echoes it into the response.
    /// - Returns: `.signed(...)` Identity that can be passed to `LfhHelpWidget`.
    /// - Throws: `LfhHelpClient.Error` on HTTP or callable failures.
    public func issueSignature(
        appId: String,
        idToken: String,
        name: String?
    ) async throws -> Identity {
        var request = URLRequest(url: config.issueSignatureURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var data: [String: String] = ["appId": appId, "idToken": idToken]
        if let name, !name.isEmpty { data["name"] = name }
        let envelope: [String: Any] = ["data": data]
        request.httpBody = try JSONSerialization.data(withJSONObject: envelope, options: [])

        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Error.malformedResponse
        }

        if (200..<300).contains(http.statusCode) {
            return try decodeResult(body)
        }
        if let err = try? JSONDecoder().decode(CallableErrorEnvelope.self, from: body) {
            throw Error.callable(status: err.error.status, message: err.error.message)
        }
        throw Error.httpStatus(http.statusCode)
    }

    private func decodeResult(_ body: Data) throws -> Identity {
        let envelope = try JSONDecoder().decode(CallableResultEnvelope.self, from: body)
        let r = envelope.result
        return .signed(
            email: r.email,
            name: r.name,
            signature: r.sig,
            version: r.v
        )
    }
}

// MARK: - Wire types

private struct CallableResultEnvelope: Decodable {
    let result: IssueSignatureResult
}

private struct IssueSignatureResult: Decodable {
    let email: String
    let name: String?
    let sig: String
    let v: Int
}

private struct CallableErrorEnvelope: Decodable {
    let error: CallableErrorBody
}

private struct CallableErrorBody: Decodable {
    let message: String
    let status: String
}
