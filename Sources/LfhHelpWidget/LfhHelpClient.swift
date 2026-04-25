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
    private let requestTimeout: TimeInterval

    /// - Parameters:
    ///   - config: endpoint config; defaults to production.
    ///   - session: URLSession instance; defaults to `.shared`.
    ///   - requestTimeout: per-request timeout in seconds. Default `60` matches
    ///     Foundation's own default — tighten it (e.g. `15`) if your host app
    ///     prefers to fail fast and show a different UI instead of letting the
    ///     user wait out a stalled Cloud Run cold start.
    public init(
        config: LfhHelpConfig = .production,
        session: URLSession = .shared,
        requestTimeout: TimeInterval = 60
    ) {
        self.config = config
        self.session = session
        self.requestTimeout = requestTimeout
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
        request.timeoutInterval = requestTimeout
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

    // MARK: - Programmatic send

    public struct SendResult: Sendable, Equatable {
        public let conversationId: String
        public let messageId: String
    }

    /// Sends a message on the visitor's behalf without opening the help
    /// widget UI. Useful for "Send Diagnostics" menu actions or any flow
    /// that wants to ship a body + attachments programmatically.
    ///
    /// Files are uploaded directly to Firebase Storage via per-file
    /// v4-signed PUT URLs minted by the helpdesk backend; no Firebase
    /// SDK is needed on the host app.
    ///
    /// - Parameters:
    ///   - appId: helpdesk app slug.
    ///   - idToken: Firebase Auth ID token from the host app's project.
    ///     The project ID must be listed on `/apps/{appId}.trustedProjects[]`.
    ///   - body: plain-text message body.
    ///   - attachments: local file URLs to upload and attach. Each
    ///     uploaded as its own object under the customer's prefix.
    ///   - name: optional display name to upsert onto the customer doc.
    ///   - conversationId: append to a specific conversation; otherwise
    ///     finds-or-creates the customer's most-recent thread.
    /// - Returns: ids of the conversation + message that were written.
    public func sendMessage(
        appId: String,
        idToken: String,
        body: String,
        attachments: [URL] = [],
        name: String? = nil,
        conversationId: String? = nil
    ) async throws -> SendResult {
        var uploaded: [SendAttachment] = []
        for url in attachments {
            uploaded.append(try await uploadOneAttachment(appId: appId, idToken: idToken, fileURL: url))
        }
        return try await postSendAsCustomer(
            appId: appId,
            idToken: idToken,
            body: body,
            attachments: uploaded,
            name: name,
            conversationId: conversationId
        )
    }

    // Internal: mint a signed URL, then PUT the file bytes.
    private func uploadOneAttachment(
        appId: String,
        idToken: String,
        fileURL: URL
    ) async throws -> SendAttachment {
        let data = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let contentType = guessContentType(for: fileURL)

        // 1. Mint the signed URL.
        var mintRequest = URLRequest(url: config.signedUploadURL)
        mintRequest.httpMethod = "POST"
        mintRequest.timeoutInterval = requestTimeout
        mintRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let mintPayload: [String: Any] = [
            "data": [
                "appId": appId,
                "idToken": idToken,
                "filename": filename,
                "contentType": contentType,
                "size": data.count,
            ],
        ]
        mintRequest.httpBody = try JSONSerialization.data(withJSONObject: mintPayload, options: [])
        let (mintBody, mintResp) = try await session.data(for: mintRequest)
        guard let mintHttp = mintResp as? HTTPURLResponse else {
            throw Error.malformedResponse
        }
        if !(200..<300).contains(mintHttp.statusCode) {
            if let err = try? JSONDecoder().decode(CallableErrorEnvelope.self, from: mintBody) {
                throw Error.callable(status: err.error.status, message: err.error.message)
            }
            throw Error.httpStatus(mintHttp.statusCode)
        }
        let mint = try JSONDecoder().decode(SignedUploadEnvelope.self, from: mintBody).result

        // 2. PUT bytes to the signed URL. Match the contentType on the
        //    signature exactly; mismatched contentType -> 403 from GCS.
        var putRequest = URLRequest(url: URL(string: mint.uploadUrl)!)
        putRequest.httpMethod = "PUT"
        putRequest.timeoutInterval = requestTimeout
        putRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, putResp) = try await session.upload(for: putRequest, from: data)
        guard let putHttp = putResp as? HTTPURLResponse else {
            throw Error.malformedResponse
        }
        if !(200..<300).contains(putHttp.statusCode) {
            throw Error.httpStatus(putHttp.statusCode)
        }

        return SendAttachment(
            path: mint.path,
            filename: filename,
            size: data.count,
            contentType: contentType
        )
    }

    private func postSendAsCustomer(
        appId: String,
        idToken: String,
        body: String,
        attachments: [SendAttachment],
        name: String?,
        conversationId: String?
    ) async throws -> SendResult {
        var sendRequest = URLRequest(url: config.sendAsCustomerURL)
        sendRequest.httpMethod = "POST"
        sendRequest.timeoutInterval = requestTimeout
        sendRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "appId": appId,
            "idToken": idToken,
            "body": body,
        ]
        if let name, !name.isEmpty { payload["name"] = name }
        if let conversationId, !conversationId.isEmpty {
            payload["conversationId"] = conversationId
        }
        if !attachments.isEmpty {
            payload["attachments"] = attachments.map { a -> [String: Any] in
                [
                    "path": a.path,
                    "filename": a.filename,
                    "size": a.size,
                    "contentType": a.contentType,
                ]
            }
        }
        sendRequest.httpBody = try JSONSerialization.data(
            withJSONObject: ["data": payload], options: []
        )

        let (sendBody, sendResp) = try await session.data(for: sendRequest)
        guard let sendHttp = sendResp as? HTTPURLResponse else {
            throw Error.malformedResponse
        }
        if !(200..<300).contains(sendHttp.statusCode) {
            if let err = try? JSONDecoder().decode(CallableErrorEnvelope.self, from: sendBody) {
                throw Error.callable(status: err.error.status, message: err.error.message)
            }
            throw Error.httpStatus(sendHttp.statusCode)
        }
        let r = try JSONDecoder().decode(SendAsCustomerEnvelope.self, from: sendBody).result
        return SendResult(conversationId: r.conversationId, messageId: r.messageId)
    }
}

// File extension → MIME type, just enough for common cases. Falls back
// to application/octet-stream when unknown — GCS still accepts it.
private func guessContentType(for url: URL) -> String {
    let ext = url.pathExtension.lowercased()
    switch ext {
    case "txt", "log": return "text/plain"
    case "json": return "application/json"
    case "xml": return "application/xml"
    case "html", "htm": return "text/html"
    case "csv": return "text/csv"
    case "pdf": return "application/pdf"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "heic": return "image/heic"
    case "mov": return "video/quicktime"
    case "mp4": return "video/mp4"
    case "zip": return "application/zip"
    default: return "application/octet-stream"
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

private struct SignedUploadEnvelope: Decodable {
    let result: SignedUploadResult
}

private struct SignedUploadResult: Decodable {
    let uploadUrl: String
    let path: String
}

private struct SendAttachment: Sendable {
    let path: String
    let filename: String
    let size: Int
    let contentType: String
}

private struct SendAsCustomerEnvelope: Decodable {
    let result: SendAsCustomerResult
}

private struct SendAsCustomerResult: Decodable {
    let conversationId: String
    let messageId: String
}
