import Foundation

/// Endpoints the widget talks to. Defaults point at production.
/// Host apps can override for local testing or staging (when it exists).
public struct LfhHelpConfig: Sendable {
    /// Base URL the iframe is rendered from. Path segments `/widget/<appId>`
    /// are appended by `LfhHelpWidget`.
    public var widgetOrigin: URL

    /// Fully-qualified URL of the `issueWidgetSignature` callable.
    /// Cloud Run v2 onCall endpoint (see `functions/src/widget/issueSignature.ts`).
    public var issueSignatureURL: URL

    /// `widgetSignedUploadURL` callable — mints a v4-signed Storage PUT
    /// URL for native attachment uploads.
    public var signedUploadURL: URL

    /// `widgetSendAsCustomer` callable — programmatic message send for
    /// host apps that hold a Firebase Auth ID token.
    public var sendAsCustomerURL: URL

    public init(
        widgetOrigin: URL,
        issueSignatureURL: URL,
        signedUploadURL: URL,
        sendAsCustomerURL: URL
    ) {
        self.widgetOrigin = widgetOrigin
        self.issueSignatureURL = issueSignatureURL
        self.signedUploadURL = signedUploadURL
        self.sendAsCustomerURL = sendAsCustomerURL
    }

    /// Production defaults, pinned to `liveflatouthelp` in `us-central1`.
    public static let production = LfhHelpConfig(
        widgetOrigin: URL(string: "https://lfh-web--liveflatouthelp.us-central1.hosted.app")!,
        issueSignatureURL: URL(string: "https://issuewidgetsignature-gllljoe5ga-uc.a.run.app")!,
        signedUploadURL: URL(string: "https://widgetsigneduploadurl-gllljoe5ga-uc.a.run.app")!,
        sendAsCustomerURL: URL(string: "https://widgetsendascustomer-gllljoe5ga-uc.a.run.app")!
    )
}
