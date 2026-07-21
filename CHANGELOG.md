# Changelog

## [1.1.1]

- Fix the update checker endlessly re-prompting for the same release — `CFBundleShortVersionString`/`CFBundleVersion` were hardcoded in Info.plist instead of using `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)`, so every build (including 1.1.0) shipped reporting itself as 1.0.0

## [1.1.0]

- Fix credit usage showing "—" when no monthly limit is set — the widget now shows the actual remaining prepaid credit balance and derives the progress bar from it

## [1.0.0]

Initial release.

- Menu bar app with a floating widget showing session, weekly, and extra-credit usage
- Sign in through an embedded browser window — no manual cookie copying
- Auto-updates via GitHub releases
