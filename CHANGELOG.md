# Changelog

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
