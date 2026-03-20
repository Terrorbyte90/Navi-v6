import SwiftUI
import WebKit

#if os(iOS)
// MARK: - MarkdownWebView
// WKWebView markdown renderer — used for streaming (no height management needed).
// For completed messages, use MarkdownWebViewAutoHeight.

struct MarkdownWebView: UIViewRepresentable {
    let text: String
    var fontSize: CGFloat = 16

    func makeCoordinator() -> MarkdownCoordinator { MarkdownCoordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView(coordinator: context.coordinator)
        webView.loadHTMLString(htmlTemplate(text: "", fontSize: fontSize), baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        pushText(text, to: webView, coordinator: context.coordinator)
    }
}

// MARK: - MarkdownWebViewAutoHeight
// Self-sizing WKWebView markdown renderer.
// Measures content height via JS->Swift message handler and applies it as frame.

struct MarkdownWebViewAutoHeight: View {
    let text: String
    var fontSize: CGFloat = 16
    @State private var height: CGFloat = 44

    var body: some View {
        _MarkdownHeightBridge(text: text, fontSize: fontSize, height: $height)
            .frame(height: height)
    }
}

// MARK: - Internal bridge

private struct _MarkdownHeightBridge: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    @Binding var height: CGFloat

    func makeCoordinator() -> MarkdownCoordinator {
        MarkdownCoordinator(onHeight: { h in height = h })
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView(coordinator: context.coordinator)
        webView.loadHTMLString(htmlTemplate(text: "", fontSize: fontSize), baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        pushText(text, to: webView, coordinator: context.coordinator)
    }
}

// MARK: - Shared coordinator

class MarkdownCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var lastText = ""
    var pendingText: String?
    var isLoaded = false
    weak var webView: WKWebView?
    var onHeight: ((CGFloat) -> Void)?

    init(onHeight: ((CGFloat) -> Void)? = nil) {
        self.onHeight = onHeight
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        if let pending = pendingText {
            pendingText = nil
            let escaped = escape(pending)
            webView.evaluateJavaScript("updateContent(`\(escaped)`)", completionHandler: nil)
            lastText = pending
        }
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        guard message.name == "heightUpdate" else { return }
        let h: CGFloat
        if let d = message.body as? Double { h = CGFloat(d) }
        else if let i = message.body as? Int { h = CGFloat(i) }
        else { return }
        guard h > 4 else { return }
        DispatchQueue.main.async { self.onHeight?(h) }
    }

    func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "`", with: "\\`")
         .replacingOccurrences(of: "$", with: "\\$")
    }
}

// MARK: - Shared helpers

private func makeWebView(coordinator: MarkdownCoordinator) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.userContentController.add(coordinator, name: "heightUpdate")
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.isScrollEnabled = false
    webView.scrollView.showsVerticalScrollIndicator = false
    webView.scrollView.bounces = false
    webView.navigationDelegate = coordinator
    coordinator.webView = webView
    return webView
}

private func pushText(_ text: String, to webView: WKWebView, coordinator: MarkdownCoordinator) {
    guard coordinator.lastText != text else { return }
    if coordinator.isLoaded {
        let escaped = coordinator.escape(text)
        webView.evaluateJavaScript("updateContent(`\(escaped)`)", completionHandler: nil)
        coordinator.lastText = text
    } else {
        coordinator.pendingText = text
    }
}

// MARK: - HTML template

func htmlTemplate(text: String, fontSize: CGFloat) -> String {
    let escaped = text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "`", with: "\\`")
        .replacingOccurrences(of: "$", with: "\\$")

    return """
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.0/marked.min.js"></script>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
  font-size: \(Int(fontSize))px;
  line-height: 1.65;
  color: #D4E8DC;
  background: transparent;
  padding: 0 2px;
  word-wrap: break-word;
  overflow-wrap: break-word;
}
p { margin-bottom: 0.85em; }
p:last-child { margin-bottom: 0; }
h1,h2,h3,h4 { color: #FFFFFF; font-weight: 600; margin: 1em 0 0.4em; }
h1 { font-size: 1.3em; } h2 { font-size: 1.15em; } h3 { font-size: 1.05em; }
a { color: #1ECC9A; text-decoration: none; }
strong { color: #FFFFFF; font-weight: 600; }
em { color: #A8C4B0; }
code {
  font-family: 'SF Mono', Menlo, monospace;
  font-size: 0.875em;
  background: rgba(30,204,154,0.12);
  color: #5EDDB8;
  padding: 0.15em 0.35em;
  border-radius: 4px;
}
pre { margin: 0.75em 0; border-radius: 10px; overflow: hidden; border: 1px solid rgba(30,204,154,0.15); }
pre code { background: none; color: inherit; padding: 14px 16px; display: block; overflow-x: auto; font-size: 0.85em; }
blockquote { border-left: 3px solid rgba(30,204,154,0.4); padding-left: 12px; color: #7A9A84; margin: 0.75em 0; }
ul,ol { padding-left: 1.4em; margin: 0.5em 0; }
li { margin-bottom: 0.25em; }
table { border-collapse: collapse; width: 100%; margin: 0.75em 0; font-size: 0.9em; }
th,td { border: 1px solid rgba(255,255,255,0.1); padding: 6px 12px; text-align: left; }
th { background: rgba(30,204,154,0.1); color: #FFFFFF; }
hr { border: none; border-top: 1px solid rgba(255,255,255,0.08); margin: 1em 0; }
</style>
</head>
<body>
<div id="content"></div>
<script>
marked.setOptions({
  highlight: function(code, lang) {
    if (lang && hljs.getLanguage(lang)) return hljs.highlight(code, { language: lang }).value;
    return hljs.highlightAuto(code).value;
  },
  breaks: true,
  gfm: true
});

function reportHeight() {
  var h = document.body.scrollHeight;
  if (h > 0 && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.heightUpdate) {
    window.webkit.messageHandlers.heightUpdate.postMessage(h);
  }
}

function updateContent(md) {
  document.getElementById('content').innerHTML = marked.parse(md || '');
  document.querySelectorAll('pre code').forEach(function(el) {
    if (!el.dataset.highlighted) hljs.highlightElement(el);
  });
  setTimeout(reportHeight, 80);
  setTimeout(reportHeight, 300);
  setTimeout(reportHeight, 800);
}

\(escaped.isEmpty ? "" : "updateContent(`\(escaped)`);")
</script>
</body>
</html>
"""
}
#endif
