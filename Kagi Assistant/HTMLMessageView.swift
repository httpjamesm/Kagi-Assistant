//
//  HTMLMessageView.swift
//  Kagi Assistant
//

import AppKit
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
    /// Styles are loaded from bundled CSS files.
    static func shellHTML() -> String {
        let css = ["message", "codehilite"]
            .compactMap { name in
                guard let url = Bundle.main.url(forResource: name, withExtension: "css"),
                      let contents = try? String(contentsOf: url, encoding: .utf8) else {
                    return nil
                }
                return contents
            }
            .joined(separator: "\n\n")

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

            function updateCopyButton(button, copied) {
                button.textContent = copied ? 'Copied' : 'Copy';
                button.dataset.copied = copied ? 'true' : 'false';
            }

            function requestCopy(button, getText) {
                const text = getText();
                if (!text) return;

                window.webkit.messageHandlers.copyToClipboard.postMessage(text);
                updateCopyButton(button, true);

                if (button._copyTimer) {
                    clearTimeout(button._copyTimer);
                }
                button._copyTimer = setTimeout(() => updateCopyButton(button, false), 1500);
            }

            function createCopyButton(getText) {
                const button = document.createElement('button');
                button.type = 'button';
                button.className = 'copy-button';
                updateCopyButton(button, false);
                button.addEventListener('click', (event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    requestCopy(button, getText);
                });
                return button;
            }

            function shouldEnhanceInlineCode(code) {
                const text = (code.innerText || '').trim();
                return text.length >= 24 || /[\\/]/.test(text);
            }

            function createCodeBlockHeader(label, getText) {
                const header = document.createElement('div');
                header.className = 'code-block-header';

                const title = document.createElement('span');
                title.className = 'code-block-title';
                title.textContent = label || 'Code';

                header.appendChild(title);
                header.appendChild(createCopyButton(getText));
                return header;
            }

            function codeHiliteLabel(pre) {
                const container = pre.parentElement;
                if (!container || !container.classList.contains('codehilite')) return '';

                const filename = Array.from(container.children).find((child) => child.classList && child.classList.contains('filename'));
                if (!filename) return '';

                const label = (filename.innerText || '').trim();
                filename.remove();
                return label;
            }

            function enhanceCodeBlocks() {
                document.querySelectorAll('pre').forEach((pre) => {
                    if (pre.dataset.copyEnhanced === 'true') return;

                    const code = pre.querySelector('code');
                    const target = code || pre;
                    const text = (target.innerText || '').trim();
                    if (!text) return;

                    const label = codeHiliteLabel(pre);
                    let container = pre.parentElement;

                    if (!container || !container.classList.contains('codehilite')) {
                        container = document.createElement('div');
                        container.className = 'code-block';
                        pre.parentNode.insertBefore(container, pre);
                        container.appendChild(pre);
                    } else {
                        container.classList.add('code-block');
                    }

                    const hasHeader = Array.from(container.children).some((child) => child.classList && child.classList.contains('code-block-header'));
                    if (!hasHeader) {
                        container.insertBefore(
                            createCodeBlockHeader(label, () => (target.innerText || '').trim()),
                            container.firstChild
                        );
                    }

                    pre.dataset.copyEnhanced = 'true';
                    pre.classList.add('copyable-pre');
                });

                document.querySelectorAll('code:not(pre code)').forEach((code) => {
                    if (code.dataset.copyEnhanced === 'true' || !shouldEnhanceInlineCode(code)) return;
                    if (!code.parentNode) return;

                    const wrapper = document.createElement('span');
                    wrapper.className = 'inline-code-copy';
                    code.parentNode.insertBefore(wrapper, code);
                    wrapper.appendChild(code);
                    wrapper.appendChild(createCopyButton(() => (code.innerText || '').trim()));
                    code.dataset.copyEnhanced = 'true';
                });
            }

            const observer = new MutationObserver(notifyHeight);
            observer.observe(document.body, { childList: true, subtree: true, characterData: true });
            window.addEventListener('load', notifyHeight);

            function setContent(html) {
                document.getElementById('content').innerHTML = html;
                enhanceCodeBlocks();
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
                webView?.configuration.userContentController.add(self, name: "copyToClipboard")
            }
        }

        init(_ parent: HTMLMessageView) {
            self.parent = parent
        }

        deinit {
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "heightChanged")
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "copyToClipboard")
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
            switch message.name {
            case "heightChanged":
                guard let height = message.body as? CGFloat, height > 0 else { return }
                DispatchQueue.main.async {
                    self.parent.dynamicHeight = height
                }
            case "copyToClipboard":
                guard let text = message.body as? String else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            default:
                break
            }
        }
    }
}
