import AppKit
import WebKit

final class LoginWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var linkField: NSTextField!
    private let provider: UsageProvider
    private let onCaptured: (String) -> Void
    private var pollTimer: Timer?
    private var lastHandledClipboard: String?
    private var instructions: NSTextField!

    private static let disableWebAuthnScriptSource = """
    (function () {
        if (window.PublicKeyCredential) {
            Object.defineProperty(window, 'PublicKeyCredential', { value: undefined, configurable: true });
        }
        if (window.navigator && window.navigator.credentials) {
            var reject = function () { return Promise.reject(new DOMException('WebAuthn is not available', 'NotSupportedError')); };
            window.navigator.credentials.get = reject;
            window.navigator.credentials.create = reject;
        }
    })();
    """

    init(provider: UsageProvider, dataStore: WKWebsiteDataStore, onCaptured: @escaping (String) -> Void) {
        self.provider = provider
        self.onCaptured = onCaptured
        super.init()
        setUp(dataStore: dataStore)
    }

    private func setUp(dataStore: WKWebsiteDataStore) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.disableWebAuthnScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        instructions = NSTextField(wrappingLabelWithString: "Sign in to \(provider.displayName). codemon securely stores this provider session in your Keychain so it can refresh your usage.")
        instructions.font = .systemFont(ofSize: 11)
        instructions.textColor = .secondaryLabelColor
        instructions.translatesAutoresizingMaskIntoConstraints = false

        linkField = NSTextField()
        linkField.placeholderString = "Paste a \(provider.displayName) sign-in link…"
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

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 720), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Sign in to \(provider.displayName)"
        window.contentView = container
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
    }

    func showWindow() {
        webView.load(URLRequest(url: provider.loginURL))
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
        guard let url = URL(string: text), url.scheme == "https", let host = url.host, isProviderHost(host) else {
            NSSound.beep()
            return
        }
        webView.load(URLRequest(url: url))
        linkField.stringValue = ""
    }

    private func isProviderHost(_ host: String) -> Bool {
        provider.cookieDomains.contains { host.hasSuffix($0) }
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
            let providerCookies = cookies.filter { cookie in
                self.provider.cookieDomains.contains { cookie.domain.contains($0) }
            }
            guard self.hasAuthenticatedCookie(providerCookies) else { return }
            let header = providerCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            DispatchQueue.main.async {
                self.onCaptured(header)
            }
        }
    }

    private func hasAuthenticatedCookie(_ cookies: [HTTPCookie]) -> Bool {
        switch provider {
        case .claude:
            return cookies.contains { $0.name == "sessionKey" }
        case .codex:
            return cookies.contains { $0.name.lowercased().hasSuffix("session-token") }
        }
    }

    private func checkClipboardForLink() {
        guard let text = NSPasteboard.general.string(forType: .string), text != lastHandledClipboard, let url = URL(string: text), url.scheme == "https", let host = url.host, isProviderHost(host) else { return }
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
