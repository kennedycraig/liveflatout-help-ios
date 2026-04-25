# LfhHelpWidget (iOS SPM package)

SwiftUI embed for the helpdesk chat widget.

## What this package provides

- **`HelpSheet` / `LfhHelpWidget`** — a SwiftUI view that hosts the
  text-only chat experience inside a `WKWebView`. Anonymous or Secure
  Mode (identified user). Visitors send and receive messages; the
  thread is real-time-synced from Firestore.
- **`LfhHelpClient.issueSignature`** — exchanges a host-app Firebase ID
  token for a Secure-Mode `Identity` you pass to `HelpSheet`.
- **`LfhHelpClient.sendMessage`** — programmatic, no-UI message send.
  This is the only way to attach files from iOS today (see
  [Programmatic send](#programmatic-send-no-ui)). The chat sheet
  itself is text-only.

Host apps depend on the published mirror repo. SwiftPM URL form:

```swift
// Host app's Package.swift
dependencies: [
    .package(
        url: "https://github.com/kennedycraig/liveflatout-help-ios.git",
        from: "0.1.0"
    ),
],
targets: [
    .target(
        name: "HostApp",
        dependencies: [
            .product(name: "LfhHelpWidget", package: "liveflatout-help-ios"),
        ]
    ),
]
```

Or in Xcode: **File → Add Package Dependencies… → Search or Enter Package URL**
→ paste `https://github.com/kennedycraig/liveflatout-help-ios.git` →
**Add Package**. Pick "Up to Next Major Version" starting at `0.1.0`.

> **Where the source lives:** the canonical source is in the
> [`liveFlatoutHelp` monorepo](https://github.com/kennedycraig/liveFlatoutHelp)
> at `packages/ios-widget/`. The
> [`liveflatout-help-ios`](https://github.com/kennedycraig/liveflatout-help-ios)
> repo is a one-way mirror produced by `git subtree split` from the monorepo
> on each release. File issues and PRs against the monorepo, not the mirror.

## `HelpSheet` — batteries-included

For most host apps, `HelpSheet` is the entry point. It wraps `LfhHelpWidget`
in a `NavigationStack` with a "Done" toolbar, a `ProgressView` while the
identity loads, and a retry screen on failure.

### Anonymous

```swift
import SwiftUI
import LfhHelpWidget

struct RootView: View {
    @State private var helpOpen = false
    var body: some View {
        Button("Help") { helpOpen = true }
            .sheet(isPresented: $helpOpen) {
                HelpSheet(appId: "app1")
            }
    }
}
```

The visitor sees a contact form; submitting it creates a `channel: 'chat'`
conversation in the helpdesk Inbox.

### Secure Mode (identified user)

Prerequisite: the host app's Firebase project ID must be listed on
`/apps/{appId}.trustedProjects[]` in Firestore. Set via
`/admin/settings/<appId>` in the helpdesk admin dashboard.

```swift
import SwiftUI
import FirebaseAuth
import LfhHelpWidget

.fullScreenCover(isPresented: $helpOpen) {
    HelpSheet(appId: "app1") {
        // Secure Mode requires an email-bearing user. Anonymous users,
        // phone-only users, and Sign in with Apple users where Apple
        // didn't share an email all fall back to anonymous chat.
        guard
            let user = Auth.auth().currentUser,
            let email = user.email, !email.isEmpty
        else {
            return .anonymous
        }
        let token = try await user.getIDToken()
        return try await LfhHelpClient().issueSignature(
            appId: "app1",
            idToken: token,
            name: user.displayName
        )
    }
}
```

The closure runs every time the sheet is presented, so it always sees the
current signed-in user. `LfhHelpClient` defaults to production endpoints in
`LfhHelpConfig.production`; override via `LfhHelpClient(config: .init(...))`
for local or staging testing.

> **`idToken has no email claim`?** That's the backend rejecting a
> Secure-Mode call for a user whose ID token has no `email` field. The
> `guard` above prevents it for anonymous and phone-only users. For
> Sign in with Apple users, make sure the host app persists the email
> Apple shares on the *first* sign-in to the Firebase user record
> (`createUser`'s `Auth.auth().currentUser?.updateEmail(...)`) — Apple
> won't share it again on subsequent sign-ins.

> **Use `.fullScreenCover`, not `.sheet`.** SwiftUI tends to dismiss a
> `.sheet` when an iOS system picker (e.g. `UIDocumentPicker`,
> `PHPickerViewController`) tries to present over it. The chat itself
> is text-only today, so this isn't currently a problem the visitor
> can hit — but the recommendation stands so future host integrations
> (e.g. attaching diagnostics from a long-press menu inside the sheet)
> don't get a surprise dismissal.

### Request timeout

`LfhHelpClient`'s `issueSignature(...)` inherits Foundation's 60-second
request timeout by default. Tighten it if you'd rather show a "try again"
UI sooner than that on a stalled cold start:

```swift
let client = LfhHelpClient(requestTimeout: 15)
```

## Programmatic send (no UI)

`LfhHelpClient.sendMessage` posts a message on the visitor's behalf
without opening the help sheet. Two big use cases:

1. **"Send Diagnostics" menu items** that ship a body + log files when
   the user reports trouble. This is the recommended path for sending
   files from iOS — the chat sheet itself is text-only, so any flow
   that needs to attach files must go through `sendMessage`.
2. **Background nudges** like "thanks for completing onboarding" that
   the host app wants to log into the customer's existing thread.

```swift
import FirebaseAuth
import LfhHelpWidget

@MainActor
func sendCrashReport(logFile: URL) async throws {
    guard let user = Auth.auth().currentUser else { return }
    let token = try await user.getIDToken()
    let result = try await LfhHelpClient().sendMessage(
        appId: "app1",
        idToken: token,
        body: "App crashed on the rides screen. Log attached.",
        attachments: [logFile],
        name: user.displayName
    )
    print("posted to conversation \(result.conversationId)")
}
```

### Text-only message (no attachments)

```swift
let result = try await LfhHelpClient().sendMessage(
    appId: "app1",
    idToken: token,
    body: "Heads-up — saw the same sync error twice today."
)
```

### Multiple files

```swift
let result = try await LfhHelpClient().sendMessage(
    appId: "app1",
    idToken: token,
    body: "Crash report + relevant config",
    attachments: [logURL, configURL]
)
```

### Appending to a specific thread

By default, `sendMessage` finds the customer's most-recent conversation
(or starts a new one). If you've stashed a `conversationId` from a prior
call and want to keep the new message on that thread, pass it through:

```swift
let result = try await LfhHelpClient().sendMessage(
    appId: "app1",
    idToken: token,
    body: "Follow-up after restart",
    conversationId: lastSavedConversationId
)
```

### How it works

For each file URL, the client mints a v4-signed Firebase Storage PUT
URL via the helpdesk backend (`widgetSignedUploadURL`), streams the
bytes directly to Storage, then calls `widgetSendAsCustomer` with the
uploaded paths + body. No Firebase iOS SDK needed — pure `URLSession`.

The host app's Firebase project ID must be on
`/apps/{appId}.trustedProjects[]` in the helpdesk Firestore (same
requirement as Secure Mode — set via `/admin/settings/<appId>`).

### Limits

- Per-attachment: **25 MB** (declared `size` ≤ 25 MiB; enforced both
  on the signed-URL mint and inside the message-write callable)
- Per message: **10 attachments**
- Files larger than 25 MB will fail at the URL mint with a
  `callable(status: "invalid-argument", ...)` error.

### Errors

`sendMessage` throws `LfhHelpClient.Error`:

- `.callable(status:, message:)` — backend rejected the call. Common
  statuses: `unauthenticated` (bad / expired ID token), `permission-denied`
  (project not on `trustedProjects[]`), `invalid-argument` (over the size
  cap, missing fields).
- `.httpStatus(Int)` — non-2xx response that wasn't a structured callable
  error (network or infra issue).
- `.malformedResponse` — response wasn't a recognised HTTP envelope.

Files are uploaded one at a time before the message write fires, so a
mid-flight failure leaves earlier uploads as orphans in Storage. Treat
the call as all-or-nothing from the user's perspective and retry on
error.

## Low-level: `LfhHelpWidget` directly

If `HelpSheet`'s chrome doesn't fit your presentation style, skip it and
compose `LfhHelpWidget` yourself:

```swift
LfhHelpWidget(appId: "app1", identity: .anonymous, onClose: { dismiss() })
    .ignoresSafeArea(.keyboard)
```

## iOS version support

- iOS 16+
- Swift 5.9+

## Closing the widget from inside the iframe

Not yet wired on the iframe side. When the iframe is updated to emit
`window.webkit.messageHandlers.lfhHelp.postMessage({type: "close"})`,
the `onClose` closure you pass to `LfhHelpWidget` will fire.

## Testing

```bash
cd packages/ios-widget
swift test   # runs Identity + LfhHelpClient tests (macOS)
```

`LfhHelpWidget` itself is `#if canImport(UIKit)`-guarded and not part of the
macOS build. Verify rendering via the `#Preview` blocks in Xcode.
