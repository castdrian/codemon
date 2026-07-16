import AppKit
import WebKit

final class LoginWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var linkField: NSTextField!
    private let onCaptured: (String) -> Void
    private var pollTimer: Timer?
    private var lastHandledClipboard: String?

    init(dataStore: WKWebsiteDataStore, onCaptured: @escaping (String) -> Void) {
        self.onCaptured = onCaptured
        super.init()
        setUp(dataStore: dataStore)
    }

    private func setUp(dataStore: WKWebsiteDataStore) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        let instructions = NSTextField(wrappingLabelWithString:
            "Claude emails a sign-in link. Pasting it below is optional — you can also just click it normally; Claude will show a short code to enter here instead. Once signed in, macOS will ask permission to store your session in the Keychain — that's expected, claudemon uses it to keep you signed in.")
        instructions.font = .systemFont(ofSize: 11)
        instructions.textColor = .secondaryLabelColor
        instructions.translatesAutoresizingMaskIntoConstraints = false

        linkField = NSTextField()
        linkField.placeholderString = "Paste sign-in link here…"
        linkField.target = self
        linkField.action = #selector(submitLink)
        linkField.translatesAutoresizingMaskIntoConstraints = false

        let goButton = NSButton(title: "Open", target: self, action: #selector(submitLink))
        goButton.bezelStyle = .rounded
        goButton.translatesAutoresizingMaskIntoConstraints = false

        let linkRow = NSStackView(views: [linkField, goButton])
        linkRow.orientation = .horizontal
        linkRow.spacing = 8
        linkRow.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 720))
        container.addSubview(instructions)
        container.addSubview(linkRow)
        container.addSubview(separator)
        container.addSubview(webView)

        NSLayoutConstraint.activate([
            instructions.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            instructions.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            instructions.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            linkRow.topAnchor.constraint(equalTo: instructions.bottomAnchor, constant: 8),
            linkRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            linkRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            goButton.widthAnchor.constraint(equalToConstant: 60),

            separator.topAnchor.constraint(equalTo: linkRow.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            webView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
                           styleMask: [.titled, .closable, .miniaturizable],
                           backing: .buffered,
                           defer: false)
        window.title = "Sign in to Claude"
        window.contentView = container
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
    }

    func showWindow() {
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startPolling()
        checkClipboardForLink()
    }

    func close() {
        stopPolling()
        window.close()
    }

    @objc private func submitLink() {
        let text = linkField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme == "https",
              let host = url.host, isClaudeHost(host) else {
            NSSound.beep()
            return
        }
        webView.load(URLRequest(url: url))
        linkField.stringValue = ""
    }

    private func isClaudeHost(_ host: String) -> Bool {
        host.hasSuffix("claude.ai") || host.hasSuffix("anthropic.com")
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkCookies()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkCookies() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
            guard claudeCookies.contains(where: { $0.name == "sessionKey" }) else { return }
            let header = claudeCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            DispatchQueue.main.async {
                self.onCaptured(header)
            }
        }
    }

    /// Picks up a copied sign-in link automatically when the window regains
    /// focus, so pasting is usually unnecessary — the field still works as a
    /// manual fallback.
    private func checkClipboardForLink() {
        guard let text = NSPasteboard.general.string(forType: .string),
              text != lastHandledClipboard,
              let url = URL(string: text),
              url.scheme == "https",
              let host = url.host, isClaudeHost(host)
        else { return }
        lastHandledClipboard = text
        linkField.stringValue = text
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkCookies()
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        checkClipboardForLink()
    }

    func windowWillClose(_ notification: Notification) {
        stopPolling()
    }
}
