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

    /// The page shell — loaded once. Contains styles, the height observer,
    /// and a `setContent()` JS function for incremental updates.
    static func shellHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            :root {
                color-scheme: light dark;
            }
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }
            body {
                font: -apple-system-body;
                font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
                font-size: 13px;
                line-height: 1.5;
                color: -apple-system-label;
                background: transparent;
                overflow: hidden;
                -webkit-user-select: text;
                word-wrap: break-word;
                overflow-wrap: break-word;
                padding: 0;
            }
            p { margin-bottom: 0.6em; }
            p:last-child { margin-bottom: 0; }
            pre {
                background: rgba(128,128,128,0.12);
                border-radius: 6px;
                padding: 8px 10px;
                overflow-x: auto;
                margin: 0.6em 0;
                font-size: 12px;
                line-height: 1.4;
            }
            code {
                font-family: "SF Mono", Menlo, monospace;
                font-size: 0.92em;
            }
            :not(pre) > code {
                background: rgba(128,128,128,0.12);
                padding: 1px 4px;
                border-radius: 3px;
            }
            a {
                color: -apple-system-blue;
                text-decoration: none;
            }
            a:hover { text-decoration: underline; }
            ul, ol {
                padding-left: 1.4em;
                margin: 0.4em 0;
            }
            li { margin-bottom: 0.2em; }
            blockquote {
                border-left: 3px solid rgba(128,128,128,0.3);
                padding-left: 10px;
                margin: 0.6em 0;
                color: rgba(128,128,128,0.8);
            }
            h1, h2, h3, h4, h5, h6 {
                margin: 0.8em 0 0.3em;
                line-height: 1.3;
            }
            h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
            h1 { font-size: 1.4em; }
            h2 { font-size: 1.2em; }
            h3 { font-size: 1.1em; }
            table {
                border-collapse: collapse;
                margin: 0.6em 0;
                font-size: 12px;
            }
            th, td {
                border: 1px solid rgba(128,128,128,0.3);
                padding: 4px 8px;
                text-align: left;
            }
            th { font-weight: 600; }
            img { max-width: 100%; height: auto; }
            hr {
                border: none;
                border-top: 1px solid rgba(128,128,128,0.3);
                margin: 0.8em 0;
            }
        </style>
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
