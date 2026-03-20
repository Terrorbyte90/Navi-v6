import SwiftUI
import WebKit

#if os(iOS)
// MARK: - MarkdownWebView
// WKWebView-based markdown renderer. Uses marked.js + highlight.js from CDN.
// Streaming-safe: updates via JS evaluateJavaScript, no full reload.

struct MarkdownWebView: UIViewRepresentable {
    let text: String
    var fontSize: CGFloat = 16

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(htmlTemplate(text: "", fontSize: fontSize), baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastText != text else { return }
        context.coordinator.lastText = text
        // Escape backticks and backslashes for JS template literal
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        webView.evaluateJavaScript("updateContent(`\(escaped)`)", completionHandler: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastText = ""
    }
}

// MARK: - HTML template

private func htmlTemplate(text: String, fontSize: CGFloat) -> String {
    let dark = UITraitCollection.current.userInterfaceStyle == .dark
    let fg         = dark ? "#e2e2e2" : "#1a1a1a"
    let codeBg     = dark ? "#1a1a2e" : "#f3f3f6"
    let codeColor  = dark ? "#cdd6f4" : "#2d2d2d"
    let quoteBg    = dark ? "rgba(255,255,255,0.04)" : "rgba(0,0,0,0.04)"
    let quoteLine  = dark ? "#555" : "#d0d0d0"
    let tableBdr   = dark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.1)"
    let tableHead  = dark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.04)"
    let hrColor    = dark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.1)"
    let link       = "#FF8C42"

    let escaped = text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "`", with: "\\`")
        .replacingOccurrences(of: "$", with: "\\$")

    return """
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/\(dark ? "github-dark" : "github").min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.0/marked.min.js"></script>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, "SF Pro Text", "Helvetica Neue", sans-serif;
  font-size: \(Int(fontSize))px;
  line-height: 1.65;
  color: \(fg);
  background: transparent;
  word-break: break-word;
  overflow-wrap: break-word;
  -webkit-text-size-adjust: none;
  -webkit-font-smoothing: antialiased;
}
h1, h2, h3, h4 {
  font-weight: 650;
  letter-spacing: -0.3px;
  margin: 1em 0 0.4em;
}
h1 { font-size: 1.45em; }
h2 { font-size: 1.2em; }
h3 { font-size: 1.05em; }
h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
p { margin: 0.5em 0; }
p:first-child { margin-top: 0; }
p:last-child { margin-bottom: 0; }
ul, ol { padding-left: 1.4em; margin: 0.5em 0; }
li { margin: 0.2em 0; }
li > p { margin: 0; }
a { color: \(link); text-decoration: none; }
a:hover { text-decoration: underline; }
strong { font-weight: 650; }
em { font-style: italic; }
code {
  font-family: "SF Mono", "Fira Code", Menlo, monospace;
  font-size: 0.875em;
  background: \(codeBg);
  color: \(codeColor);
  padding: 1px 5px;
  border-radius: 4px;
  white-space: pre-wrap;
}
pre {
  background: \(codeBg);
  border-radius: 10px;
  padding: 14px 16px;
  margin: 0.7em 0;
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
}
pre code {
  background: none;
  padding: 0;
  font-size: 0.85em;
  line-height: 1.55;
  color: inherit;
  border-radius: 0;
}
blockquote {
  border-left: 3px solid \(quoteLine);
  background: \(quoteBg);
  padding: 8px 14px;
  margin: 0.6em 0;
  border-radius: 0 6px 6px 0;
}
blockquote p { margin: 0; }
table {
  border-collapse: collapse;
  width: 100%;
  margin: 0.7em 0;
  font-size: 0.9em;
}
th, td {
  border: 1px solid \(tableBdr);
  padding: 7px 12px;
  text-align: left;
}
th { font-weight: 600; background: \(tableHead); }
hr { border: none; border-top: 1px solid \(hrColor); margin: 1em 0; }
img { max-width: 100%; border-radius: 8px; }
</style>
</head>
<body>
<div id="md"></div>
<script>
marked.use({ gfm: true, breaks: true });
function updateContent(md) {
  document.getElementById('md').innerHTML = marked.parse(md || '');
  document.querySelectorAll('pre code').forEach(function(el) {
    hljs.highlightElement(el);
  });
}
updateContent(`\(escaped)`);
</script>
</body>
</html>
"""
}
#endif
