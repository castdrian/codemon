# Changelog

## [1.3.1]

- Bring back the Claude credits row. Claude reports extra usage as disabled when the balance is spent, which 1.3.0 read as "no credits section at all" and hid the row entirely; it is shown again whenever the provider has credits, falling back to a dash. Codex, which has no credits worth showing, no longer renders one
- Show the Codex account name rather than the email address, read from the `name` claim in the id_token that `~/.codex/auth.json` already stores

## [1.3.0]

- Drop the sign-in window entirely. codemon now reads the credentials the CLIs already keep on your Mac — Claude from the `claude` CLI's Keychain entry, Codex from `~/.codex/auth.json` — and calls each provider's OAuth API directly. The first Claude read raises a macOS Keychain prompt; choose **Always Allow**. If a provider has no credentials, codemon says so and points at the CLI to run
- Fix Codex usage never loading. The old cookie-based request was unauthorized no matter how the session was obtained, because that endpoint expects a bearer token rather than cookies
- Show only the limits a provider actually has. Codex reports a single weekly window plus credits and no session window, so it no longer displays an empty "Session" row, and windows are now labelled from the length the API reports rather than assumed from their position
- Keep each widget where you last dragged it. Positions were only written when a move landed after the mouse was already released, which is not what happens at the end of a drag, so the last position was usually lost
- Show the signed-in account name and plan again, and surface the reason in the widget when usage cannot be loaded

## [1.2.5]

- Bring back Sign in with Apple's Touch ID prompt. 1.2.4 turned off WebKit's extensible SSO to stop a crash, which also removed the native Apple sign-in sheet — that is why the prompt disappeared on release builds while local 1.2.3 builds still showed it
- Fix sign-in completing in the browser window but never activating in codemon: the window would land on chatgpt.com and just sit there. 1.2.3 had started gating capture on a live API call, and Codex's usage endpoint answers 401 to a cookie-only request no matter how good the session is, so a valid sign-in could never be accepted. Capture no longer waits on that call
- Recognise Codex session cookies whether or not they are split into chunks

## [1.2.4]

- Fix the app crashing outright when clicking "Continue with Apple" in the sign-in window. WebKit hands Apple ID authorization to the system's extensible SSO (AppSSO) extension, which presents Sign in with Apple as a native out-of-process sheet, and presenting that sheet threw an uncaught exception that aborted the process. The sign-in window opts out of extensible SSO so Apple ID stays an ordinary web sign-in (reverted in 1.2.5, which restores the native prompt)

## [1.2.3]

- Fix the Codex sign-in window opening blank and closing again straight away, and the menu being stuck on "Sign In to Codex Again…". A dead `__Secure-next-auth.session-token` left in the shared web data store by the earlier broken captures was matched and re-captured the instant the window loaded, so every sign-in attempt "succeeded" with an already-invalid session, and the resulting 401 flipped the account straight back to expired. Starting a sign-in now clears that provider's stored web data first, so the page loads from a clean signed-out state
- Only accept a captured session once it actually works — the sign-in window now stays open until the captured cookies return a real response from the provider's API, instead of closing on the first cookie that merely looks like a session
- Stop the passkey/Touch ID option being offered in the sign-in window at all — `PublicKeyCredential` and `navigator.credentials` are now removed outright rather than only having their methods stubbed, so the page falls back to password sign-in instead of a prompt the embedded window can never complete

## [1.2.2]

- Fix Codex sign-in failing with "Authentication Error — client_id_not_found_in_session" — 1.2.1's fix for the Apple ID Touch ID hang opened Apple's auth pages in the system browser, but the OAuth session state (`client_id`, PKCE verifier, etc.) lives in the embedded sign-in window's own isolated cookie store, so the callback landed in a browser with no matching session and failed for every sign-in, not just Apple ID. Reverted that handoff. Touch ID/passkey prompts are now prevented at the source instead: the sign-in window disables `navigator.credentials`/`PublicKeyCredential` via an injected script, so Apple's page falls back to password entry within the same window and session

## [1.2.1]

- Fix the Codex sign-in window closing immediately after it opens — `chatgpt.com` sets CSRF/PKCE cookies (e.g. `authjs.csrf-token`) as soon as the login page loads, and the old check treated any cookie with "auth" or "session" in its name as a signed-in session, capturing and closing the window before the user could sign in. Now only the actual `*session-token` cookie counts
- Fix the floating widget header showing the literal provider name ("Claude · Claude Pro") instead of the signed-in account's display name

## [1.2.0]

- Give the floating widget one overlay per coding client again (Claude and Codex each get their own panel with an independent saved position) instead of a single merged widget
- Fix Sign in with Apple ID hanging on the Touch ID prompt for Codex — the embedded browser window can't complete Face ID/Touch ID passkey assertions for Apple's own sign-in pages, so that step now opens in the default browser and the resulting link can be pasted back in
- Fix the update checker regressing back to hardcoded version literals — the Codex monitoring release reset `Info.plist` to `1.0.0`/`1` instead of `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)`, reintroducing the endless re-prompt bug fixed in 1.1.1

## [1.1.1]

- Fix the update checker endlessly re-prompting for the same release — `CFBundleShortVersionString`/`CFBundleVersion` were hardcoded in Info.plist instead of using `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)`, so every build (including 1.1.0) shipped reporting itself as 1.0.0

## [1.1.0]

- Fix credit usage showing "—" when no monthly limit is set — the widget now shows the actual remaining prepaid credit balance and derives the progress bar from it

## [1.0.0]

Initial release.

- Menu bar app with a floating widget showing session, weekly, and extra-credit usage
- Sign in through an embedded browser window — no manual cookie copying
- Auto-updates via GitHub releases
