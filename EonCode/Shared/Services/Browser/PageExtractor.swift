import Foundation
import WebKit

// MARK: - PageExtractor
// Extracts structured page content via JavaScript injection (text-first, cheap approach).

struct PageContent {
    let title: String
    let url: String
    let visibleText: String
    let links: [PageLink]
    let inputs: [PageInput]
    let buttons: [PageButton]

    struct PageLink: Codable {
        let index: Int
        let text: String
        let href: String
    }

    struct PageInput: Codable {
        let index: Int
        let type: String
        let name: String
        let placeholder: String
        let label: String
        let selector: String
    }

    struct PageButton: Codable {
        let index: Int
        let text: String
        let selector: String
    }

    // Formatted for Claude
    var summary: String {
        var parts: [String] = []
        parts.append("URL: \(url)")
        parts.append("Titel: \(title)")
        if !visibleText.isEmpty {
            parts.append("Text:\n\(visibleText.prefix(4000))")
        }
        if !links.isEmpty {
            let linkLines = links.prefix(30).map { "[\($0.index)] \($0.text) → \($0.href)" }
            parts.append("Länkar:\n" + linkLines.joined(separator: "\n"))
        }
        if !inputs.isEmpty {
            let inputLines = inputs.map { "[\($0.index)] \($0.type) '\($0.label.isEmpty ? $0.placeholder : $0.label)' sel=\($0.selector)" }
            parts.append("Inmatningsfält:\n" + inputLines.joined(separator: "\n"))
        }
        if !buttons.isEmpty {
            let btnLines = buttons.prefix(20).map { "[\($0.index)] '\($0.text)' sel=\($0.selector)" }
            parts.append("Knappar:\n" + btnLines.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }
}

@MainActor
struct PageExtractor {

    static let extractionScript = """
    (function() {
        function generateSelector(el) {
            if (!el || el === document.body) return 'body';
            if (el.id) return '#' + CSS.escape(el.id);
            if (el.name) return el.tagName.toLowerCase() + '[name="' + el.name + '"]';
            let path = [];
            let current = el;
            while (current && current !== document.body) {
                let siblings = Array.from(current.parentNode ? current.parentNode.children : []);
                let idx = siblings.indexOf(current);
                path.unshift(current.tagName.toLowerCase() + ':nth-child(' + (idx + 1) + ')');
                current = current.parentNode;
                if (path.length > 5) break;
            }
            return path.join(' > ');
        }

        function isVisible(el) {
            const style = window.getComputedStyle(el);
            return style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0';
        }

        const result = {
            title: document.title || '',
            url: window.location.href,
            text: (document.body ? document.body.innerText : '').substring(0, 8000),
            links: Array.from(document.querySelectorAll('a[href]'))
                .filter(a => isVisible(a))
                .map((a, i) => ({
                    index: i,
                    text: (a.innerText || a.textContent || '').trim().substring(0, 80),
                    href: a.href
                }))
                .filter(l => l.text.length > 0 && !l.href.startsWith('javascript'))
                .slice(0, 40),
            inputs: Array.from(document.querySelectorAll('input:not([type=hidden]), textarea, select'))
                .filter(el => isVisible(el))
                .map((el, i) => ({
                    index: i,
                    type: el.type || el.tagName.toLowerCase(),
                    name: el.name || '',
                    placeholder: el.placeholder || '',
                    label: (el.labels && el.labels[0] ? el.labels[0].innerText : '') ||
                           el.getAttribute('aria-label') ||
                           el.name ||
                           el.placeholder ||
                           (el.type ? el.type + ' fält ' + (i+1) : 'Fält ' + (i+1)),
                    selector: generateSelector(el)
                })),
            buttons: Array.from(document.querySelectorAll('button, input[type=submit], input[type=button], [role=button]'))
                .filter(b => isVisible(b))
                .map((b, i) => ({
                    index: i,
                    text: (b.innerText || b.value || b.getAttribute('aria-label') || '').trim().substring(0, 60),
                    selector: generateSelector(b)
                }))
                .filter(b => b.text.length > 0)
                .slice(0, 30)
        };
        return JSON.stringify(result);
    })()
    """

    static func extract(from webView: WKWebView) async throws -> PageContent {
        return try await withCheckedThrowingContinuation { cont in
            webView.evaluateJavaScript(extractionScript) { result, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8) else {
                    cont.resume(throwing: BrowserError.extractionFailed)
                    return
                }
                do {
                    let raw = try JSONDecoder().decode(RawPage.self, from: data)
                    let content = PageContent(
                        title: raw.title,
                        url: raw.url,
                        visibleText: raw.text,
                        links: raw.links.map { PageContent.PageLink(index: $0.index, text: $0.text, href: $0.href) },
                        inputs: raw.inputs.map { PageContent.PageInput(index: $0.index, type: $0.type, name: $0.name, placeholder: $0.placeholder, label: $0.label, selector: $0.selector) },
                        buttons: raw.buttons.map { PageContent.PageButton(index: $0.index, text: $0.text, selector: $0.selector) }
                    )
                    cont.resume(returning: content)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Click / Type / Scroll via JS

    static func clickElement(selector: String, in webView: WKWebView) async throws {
        let js = """
        (function() {
            var el = document.querySelector(\(jsString(selector)));
            if (!el) return 'not_found';
            el.click();
            return 'clicked';
        })()
        """
        let result = try await webView.evaluateJavaScriptAsync(js) as? String
        if result == "not_found" { throw BrowserError.elementNotFound(selector) }
    }

    static func typeInField(selector: String, text: String, in webView: WKWebView) async throws {
        let js = """
        (function() {
            var el = document.querySelector(\(jsString(selector)));
            if (!el) return 'not_found';
            el.focus();
            el.value = \(jsString(text));
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            return 'typed';
        })()
        """
        let result = try await webView.evaluateJavaScriptAsync(js) as? String
        if result == "not_found" { throw BrowserError.elementNotFound(selector) }
    }

    static func scroll(_ direction: String, in webView: WKWebView) async throws {
        let amount = direction == "up" ? -400 : 400
        let js = "window.scrollBy(0, \(amount));"
        try await webView.evaluateJavaScriptAsync(js)
    }

    private static func jsString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    // Internal raw decode types
    private struct RawPage: Decodable {
        let title: String; let url: String; let text: String
        let links: [RawLink]; let inputs: [RawInput]; let buttons: [RawButton]
    }
    private struct RawLink: Decodable { let index: Int; let text: String; let href: String }
    private struct RawInput: Decodable { let index: Int; let type: String; let name: String; let placeholder: String; let label: String; let selector: String }
    private struct RawButton: Decodable { let index: Int; let text: String; let selector: String }
}

// MARK: - WKWebView async helpers

extension WKWebView {
    @discardableResult
    func evaluateJavaScriptAsync(_ js: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { cont in
            evaluateJavaScript(js) { result, error in
                if let error = error { cont.resume(throwing: error) }
                else { cont.resume(returning: result) }
            }
        }
    }
}

enum BrowserError: LocalizedError {
    case extractionFailed
    case elementNotFound(String)
    case navigationFailed(String)
    case screenshotFailed

    var errorDescription: String? {
        switch self {
        case .extractionFailed: return "Kunde inte extrahera sidans innehåll"
        case .elementNotFound(let s): return "Element hittades inte: \(s)"
        case .navigationFailed(let u): return "Navigering misslyckades: \(u)"
        case .screenshotFailed: return "Skärmbild misslyckades"
        }
    }
}
