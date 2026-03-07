import Foundation
import WebKit

// MARK: - PageContent

struct PageContent {
    let title: String
    let url: String
    let visibleText: String
    let links: [PageLink]
    let inputs: [PageInput]
    let buttons: [PageButton]
    let hasOverlay: Bool

    struct PageLink: Codable { let index: Int; let text: String; let href: String }
    struct PageInput: Codable { let index: Int; let type: String; let name: String; let placeholder: String; let label: String; let selector: String }
    struct PageButton: Codable { let index: Int; let text: String; let selector: String }

    var summary: String {
        var parts: [String] = []
        parts.append("URL: \(url)")
        parts.append("Titel: \(title)")
        if !visibleText.isEmpty { parts.append("Text:\n\(visibleText.prefix(5000))") }
        if !links.isEmpty {
            parts.append("Länkar:\n" + links.prefix(40).map { "[\($0.index)] \($0.text) → \($0.href)" }.joined(separator: "\n"))
        }
        if !inputs.isEmpty {
            parts.append("Fält:\n" + inputs.map { "[\($0.index)] \($0.type) '\($0.label.isEmpty ? $0.placeholder : $0.label)' sel=\($0.selector)" }.joined(separator: "\n"))
        }
        if !buttons.isEmpty {
            parts.append("Knappar:\n" + buttons.prefix(25).map { "[\($0.index)] '\($0.text)' sel=\($0.selector)" }.joined(separator: "\n"))
        }
        if hasOverlay { parts.append("[OBS: Popup/overlay upptäckt]") }
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - PageExtractor

@MainActor
struct PageExtractor {

    static let extractionScript = """
    (function() {
        function genSel(el) {
            if (!el || el === document.body) return 'body';
            if (el.id) return '#' + CSS.escape(el.id);
            if (el.name && el.tagName) {
                var byName = document.querySelectorAll(el.tagName + '[name="' + el.name + '"]');
                if (byName.length === 1) return el.tagName.toLowerCase() + '[name="' + el.name + '"]';
            }
            if (el.getAttribute && el.getAttribute('data-testid'))
                return '[data-testid="' + el.getAttribute('data-testid') + '"]';
            if (el.getAttribute && el.getAttribute('aria-label'))
                return '[aria-label="' + CSS.escape(el.getAttribute('aria-label')) + '"]';
            var path = [];
            var cur = el;
            while (cur && cur !== document.body && path.length < 6) {
                var tag = cur.tagName.toLowerCase();
                if (cur.id) { path.unshift('#' + CSS.escape(cur.id)); break; }
                var siblings = cur.parentNode ? Array.from(cur.parentNode.children).filter(function(c){return c.tagName===cur.tagName}) : [];
                if (siblings.length > 1) tag += ':nth-of-type(' + (siblings.indexOf(cur) + 1) + ')';
                path.unshift(tag);
                cur = cur.parentNode;
            }
            return path.join(' > ');
        }
        function isVis(el) {
            if (!el) return false;
            var r = el.getBoundingClientRect();
            if (r.width === 0 && r.height === 0) return false;
            var s = window.getComputedStyle(el);
            return s.display !== 'none' && s.visibility !== 'hidden' && parseFloat(s.opacity) > 0;
        }
        function hasOverlay() {
            var all = document.querySelectorAll('[class*=cookie],[class*=consent],[class*=modal],[class*=overlay],[class*=popup],[class*=banner],[id*=cookie],[id*=consent],[id*=gdpr],[role=dialog]');
            for (var i = 0; i < all.length; i++) {
                var s = window.getComputedStyle(all[i]);
                if (s.display !== 'none' && s.visibility !== 'hidden' && parseFloat(s.opacity) > 0) {
                    var r = all[i].getBoundingClientRect();
                    if (r.width > 200 && r.height > 50) return true;
                }
            }
            return false;
        }
        var result = {
            title: document.title || '',
            url: window.location.href,
            text: (document.body ? document.body.innerText : '').substring(0, 10000),
            hasOverlay: hasOverlay(),
            links: Array.from(document.querySelectorAll('a[href]'))
                .filter(function(a){ return isVis(a) })
                .map(function(a, i){return { index: i, text: (a.innerText||a.textContent||a.getAttribute('aria-label')||'').trim().substring(0,100), href: a.href }})
                .filter(function(l){ return l.text.length > 0 && !l.href.startsWith('javascript') })
                .slice(0, 50),
            inputs: Array.from(document.querySelectorAll('input:not([type=hidden]), textarea, select'))
                .filter(function(el){ return isVis(el) })
                .map(function(el, i){
                    var lbl = '';
                    if (el.labels && el.labels[0]) lbl = el.labels[0].innerText;
                    if (!lbl) lbl = el.getAttribute('aria-label') || '';
                    if (!lbl) lbl = el.name || '';
                    if (!lbl) lbl = el.placeholder || '';
                    if (!lbl) lbl = (el.type || 'fält') + ' ' + (i+1);
                    return { index: i, type: el.type || el.tagName.toLowerCase(), name: el.name || '', placeholder: el.placeholder || '', label: lbl.trim().substring(0,80), selector: genSel(el) }
                }),
            buttons: Array.from(document.querySelectorAll('button, input[type=submit], input[type=button], [role=button], a[class*=btn], a[class*=button]'))
                .filter(function(b){ return isVis(b) })
                .map(function(b, i){return { index: i, text: (b.innerText||b.value||b.getAttribute('aria-label')||'').trim().substring(0,80), selector: genSel(b) }})
                .filter(function(b){ return b.text.length > 0 })
                .slice(0, 35)
        };
        return JSON.stringify(result);
    })()
    """

    static func extract(from webView: WKWebView) async throws -> PageContent {
        return try await withCheckedThrowingContinuation { cont in
            webView.evaluateJavaScript(extractionScript) { result, error in
                if let error = error { cont.resume(throwing: error); return }
                guard let jsonString = result as? String, let data = jsonString.data(using: .utf8) else {
                    cont.resume(throwing: BrowserError.extractionFailed); return
                }
                do {
                    let raw = try JSONDecoder().decode(RawPage.self, from: data)
                    cont.resume(returning: PageContent(
                        title: raw.title, url: raw.url, visibleText: raw.text,
                        links: raw.links.map { .init(index: $0.index, text: $0.text, href: $0.href) },
                        inputs: raw.inputs.map { .init(index: $0.index, type: $0.type, name: $0.name, placeholder: $0.placeholder, label: $0.label, selector: $0.selector) },
                        buttons: raw.buttons.map { .init(index: $0.index, text: $0.text, selector: $0.selector) },
                        hasOverlay: raw.hasOverlay
                    ))
                } catch { cont.resume(throwing: error) }
            }
        }
    }

    // MARK: - Popup dismissal

    static func detectAndDismissOverlays(in webView: WKWebView) async throws -> Bool {
        let js = """
        (function() {
            var sels = [
                '[class*=cookie] button[class*=accept]', '[class*=cookie] button[class*=agree]',
                '[class*=cookie] button[class*=allow]', '[class*=cookie] button[class*=ok]',
                '[class*=consent] button[class*=accept]', '[class*=consent] button[class*=agree]',
                '[class*=consent] button[class*=allow]',
                '[id*=cookie] button[class*=accept]', '[id*=cookie] button[class*=agree]',
                '[id*=consent] button[class*=accept]', '[id*=consent] button[class*=agree]',
                '#onetrust-accept-btn-handler', '#onetrust-pc-btn-handler',
                '.cc-accept', '.cc-dismiss', '.cc-allow', '.cc-btn.cc-accept-all',
                '#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll',
                '#CybotCookiebotDialogBodyButtonAccept',
                '#didomi-notice-agree-button', '.didomi-continue-without-agreeing',
                '#hs-eu-confirmation-button', '#truste-consent-button',
                'button[data-testid*=accept]', 'button[data-testid*=cookie]',
                'button[data-cookiefirst-action=accept]',
                '[class*=gdpr] button[class*=accept]', '[class*=gdpr] button',
                '[aria-label*=Accept]', '[aria-label*=accept]', '[aria-label*=Godkänn]',
                '[aria-label*=Acceptera]', '[aria-label*=Tillåt]', '[aria-label*=Allow]',
                '[aria-label*="Accept all"]', '[aria-label*="Acceptera alla"]',
                '[class*=banner] button[class*=accept]', '[class*=banner] button[class*=agree]',
                '[class*=notice] button[class*=accept]', '[class*=notice] button[class*=agree]',
                '[role=dialog] button[class*=accept]', '[role=dialog] button[class*=agree]',
                '[role=dialog] button[class*=close]', '[role=dialog] button[aria-label*=close]',
                '[role=dialog] button[aria-label*=Close]',
                '[class*=modal] button[class*=close]', '[class*=popup] button[class*=close]',
                '.modal .close', '.modal-close', 'button.close[data-dismiss]',
                'button[class*=cookie-accept]', 'button[id*=cookie-accept]',
                'a[class*=cookie-accept]', 'a[id*=cookie-accept]'
            ];
            for (var i = 0; i < sels.length; i++) {
                try {
                    var els = document.querySelectorAll(sels[i]);
                    for (var j = 0; j < els.length; j++) {
                        var s = window.getComputedStyle(els[j]);
                        if (s.display !== 'none' && s.visibility !== 'hidden' && s.opacity !== '0') {
                            els[j].click(); return 'dismissed';
                        }
                    }
                } catch(e) {}
            }
            // Text-based fallback: find buttons containing accept-like text
            var btns = document.querySelectorAll('button, a[role=button], [class*=btn]');
            var acceptWords = ['acceptera', 'godkänn', 'tillåt', 'accept', 'agree', 'allow', 'ok', 'got it', 'i agree', 'accept all', 'acceptera alla', 'tillåt alla'];
            for (var b = 0; b < btns.length; b++) {
                try {
                    var txt = btns[b].textContent.trim().toLowerCase();
                    if (txt.length > 50) continue;
                    var bs = window.getComputedStyle(btns[b]);
                    if (bs.display === 'none' || bs.visibility === 'hidden') continue;
                    for (var w = 0; w < acceptWords.length; w++) {
                        if (txt === acceptWords[w] || txt.indexOf(acceptWords[w]) !== -1) {
                            btns[b].click(); return 'dismissed';
                        }
                    }
                } catch(e) {}
            }
            // Check iFrames for cookie consent
            var iframes = document.querySelectorAll('iframe');
            for (var fi = 0; fi < iframes.length; fi++) {
                try {
                    var iDoc = iframes[fi].contentDocument || iframes[fi].contentWindow.document;
                    if (!iDoc) continue;
                    for (var si = 0; si < sels.length; si++) {
                        try {
                            var iEls = iDoc.querySelectorAll(sels[si]);
                            for (var ij = 0; ij < iEls.length; ij++) {
                                var is2 = iDoc.defaultView.getComputedStyle(iEls[ij]);
                                if (is2.display !== 'none' && is2.visibility !== 'hidden') {
                                    iEls[ij].click(); return 'dismissed';
                                }
                            }
                        } catch(e2) {}
                    }
                } catch(e3) {}
            }
            // Force-remove fixed overlays
            var overlays = document.querySelectorAll(
                '[class*=overlay][style*=fixed],[class*=cookie],[id*=cookie-banner],' +
                '[class*=consent-banner],[id*=consent],[class*=cookie-banner],' +
                '[class*=cookie-wall],[class*=cookie-notice],[class*=gdpr]'
            );
            for (var k = 0; k < overlays.length; k++) {
                var os = window.getComputedStyle(overlays[k]);
                if (os.position === 'fixed' || os.position === 'absolute' || os.position === 'sticky') {
                    overlays[k].style.display = 'none';
                    document.body.style.overflow = 'auto';
                    document.documentElement.style.overflow = 'auto';
                    return 'removed';
                }
            }
            return 'none';
        })()
        """
        let result = try await webView.evaluateJavaScriptAsync(js) as? String
        return result == "dismissed" || result == "removed"
    }

    // MARK: - Actions

    static func clickElement(selector: String, in webView: WKWebView) async throws {
        let js = """
        (function() {
            var el = document.querySelector(\(jsString(selector)));
            if (!el) return 'not_found';
            el.scrollIntoView({block:'center',behavior:'smooth'});
            setTimeout(function(){ el.click(); }, 200);
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
            el.scrollIntoView({block:'center',behavior:'smooth'});
            el.focus();
            var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
            if (setter && setter.set) { setter.set.call(el, \(jsString(text))); }
            else { el.value = \(jsString(text)); }
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            el.dispatchEvent(new KeyboardEvent('keyup', {bubbles: true}));
            return 'typed';
        })()
        """
        let result = try await webView.evaluateJavaScriptAsync(js) as? String
        if result == "not_found" { throw BrowserError.elementNotFound(selector) }
    }

    static func submitForm(selector: String, in webView: WKWebView) async throws {
        let js = """
        (function() {
            var el = document.querySelector(\(jsString(selector)));
            if (!el) return 'not_found';
            if (el.tagName === 'BUTTON' || el.type === 'submit') { el.click(); return 'clicked'; }
            if (el.tagName === 'FORM') { el.submit(); return 'submitted'; }
            var form = el.closest('form');
            if (form) { form.submit(); return 'submitted'; }
            el.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));
            return 'enter';
        })()
        """
        let result = try await webView.evaluateJavaScriptAsync(js) as? String
        if result == "not_found" { throw BrowserError.elementNotFound(selector) }
    }

    static func scroll(_ direction: String, in webView: WKWebView) async throws {
        let amount = direction == "up" ? -500 : 500
        try await webView.evaluateJavaScriptAsync("window.scrollBy({top:\(amount),behavior:'smooth'})")
    }

    private static func jsString(_ s: String) -> String {
        let e = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(e)\""
    }

    private struct RawPage: Decodable {
        let title: String; let url: String; let text: String; let hasOverlay: Bool
        let links: [RawLink]; let inputs: [RawInput]; let buttons: [RawButton]
    }
    private struct RawLink: Decodable { let index: Int; let text: String; let href: String }
    private struct RawInput: Decodable { let index: Int; let type: String; let name: String; let placeholder: String; let label: String; let selector: String }
    private struct RawButton: Decodable { let index: Int; let text: String; let selector: String }
}

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
        case .extractionFailed: return "Kunde inte läsa sidan"
        case .elementNotFound(let s): return "Element ej funnet: \(s)"
        case .navigationFailed(let u): return "Navigation misslyckades: \(u)"
        case .screenshotFailed: return "Skärmbild misslyckades"
        }
    }
}
