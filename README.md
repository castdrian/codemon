# codemon

Menu bar app that tracks your Claude and Codex usage — session, weekly, and credits — with a small floating widget. No sign-in: it reads the credentials the `claude` and `codex` CLIs already store on your Mac.

<p align="center">
  <img src="https://adriancastro.dev/rel05geam3lp.png" alt="codemon screenshot 1" width="260" />
  <img src="https://adriancastro.dev/io8jo6y8lkjj.png" alt="codemon screenshot 2" width="260" />
  <img src="https://adriancastro.dev/sym94u6buj56.png" alt="codemon screenshot 3" width="260" />
</p>

## Features

- One floating widget per provider, each with its own draggable position, showing only the limits that provider actually has
- No sign-in flow: Claude usage comes from the `claude` CLI's Keychain credentials, Codex from `~/.codex/auth.json`
- Menu bar dropdown with per-provider usage percentages
- Customizable global shortcut to toggle the widget
- Auto-updates via GitHub releases

## Requirements

macOS 13 Ventura or later.

Sign in with the CLIs you want tracked — run `claude` for Claude and `codex` for Codex. codemon reads those existing credentials and never asks for them itself. The first Claude read triggers a macOS Keychain prompt; choose **Always Allow** so it does not ask again.

## Installation

Download the latest release from [Releases](https://github.com/castdrian/codemon/releases), unzip, and move `codemon.app` to Applications.

## Building from source

1. Clone this repository.
2. Open `codemon.xcodeproj` in Xcode 15+.
3. Build and run (⌘R).

## Support

If codemon is useful to you, consider [buying me a coffee](https://ko-fi.com/castdrian).
