# Changelog

## [1.2.4]

- Fix the app crashing outright when clicking "Continue with Apple" in the sign-in window. WebKit routes Apple ID authorization to the system's extensible SSO (AppSSO) extension, which presents Sign in with Apple as a native out-of-process sheet. codemon ships ad-hoc signed with no team identifier, so that sheet can't be vended to it and its presentation throws an uncaught exception, aborting the process. The sign-in window now opts out of extensible SSO, so Apple ID stays an ordinary web sign-in inside the window — which is also what the original "Touch ID prompt that never finishes" was: the same native sheet, failing quietly instead of loudly

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
