//
//  HTMLMessageView.swift
//  Kagi Assistant
//

import SwiftUI
import WebKit

private class NonScrollableWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

struct HTMLMessageView: NSViewRepresentable {
    let html: String
    @Binding var dynamicHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false

        let webView = NonScrollableWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        context.coordinator.webView = webView

        // Load the shell page once; content will be injected via JS
        let shell = Self.shellHTML()
        webView.loadHTMLString(shell, baseURL: nil)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        print("[HTMLMessageView] updateNSView called, html length: \(html.count)")
        context.coordinator.parent = self
        context.coordinator.updateContent(html)
    }

    /// The page shell — loaded once. Contains the height observer
    /// and a `setContent()` JS function for incremental updates.
    /// Styles are loaded from `message.css` in the app bundle.
    static func shellHTML() -> String {
        let css: String = {
            guard let url = Bundle.main.url(forResource: "message", withExtension: "css"),
                  let contents = try? String(contentsOf: url, encoding: .utf8) else {
                return ""
            }
            return contents
        }()

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        </head>
        <body>
        <div id="content"></div>
        <script>
            function notifyHeight() {
                const h = document.body.scrollHeight;
                window.webkit.messageHandlers.heightChanged.postMessage(h);
            }
            const observer = new MutationObserver(notifyHeight);
            observer.observe(document.body, { childList: true, subtree: true, characterData: true });
            window.addEventListener('load', notifyHeight);

            function setContent(html) {
                document.getElementById('content').innerHTML = html;
                notifyHeight();
            }
        </script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: HTMLMessageView
        private var pageReady = false
        private var pendingHTML: String?

        weak var webView: WKWebView? {
            didSet {
                webView?.configuration.userContentController.add(self, name: "heightChanged")
            }
        }

        init(_ parent: HTMLMessageView) {
            self.parent = parent
        }

        deinit {
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "heightChanged")
        }

        func updateContent(_ html: String) {
            print("[HTMLMessageView] updateContent called, pageReady: \(pageReady), html length: \(html.count)")
            if pageReady {
                injectHTML(html)
            } else {
                pendingHTML = html
            }
        }

        private func injectHTML(_ html: String) {
            print("[HTMLMessageView] injectHTML called, html length: \(html.count)")
            guard let webView else {
                print("[HTMLMessageView] injectHTML — webView is nil!")
                return
            }
            // Escape for JS string literal
            let escaped = html
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "${", with: "\\${")
            webView.evaluateJavaScript("setContent(`\(escaped)`)") { _, _ in }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("[HTMLMessageView] didFinish — page is now ready")
            pageReady = true
            // Inject any content that arrived before the page was ready
            if let pending = pendingHTML {
                pendingHTML = nil
                injectHTML(pending)
            } else {
                injectHTML(parent.html)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "heightChanged",
                  let height = message.body as? CGFloat,
                  height > 0 else { return }
            DispatchQueue.main.async {
                self.parent.dynamicHeight = height
            }
        }
    }
}
