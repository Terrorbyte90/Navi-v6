# Navi Mega Upgrade — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix UI bugs, add native APNs push, WebKit markdown rendering, Navi-brain MD injection + learning summaries, and make the Code agent smarter than Claude Code/Cursor.

**Architecture:** Six phases — quick UI fixes → WebKit markdown → native APNs → MD knowledge injection → hourly session learner → code agent tool expansion. iOS and server changes are decoupled; server changes deploy independently via PM2.

**Tech Stack:** SwiftUI + WKWebView (iOS), Node.js + HTTP/2 APNs (server), Markdown (navi-brain), WebSocket (code agent protocol).

---

## File Map

### iOS — Modified
- `EonCode/Shared/Views/Code/CodeView.swift` — remove phaseStrip from topBar
- `EonCode/Shared/Views/Components/MarkdownWebView.swift` — NEW: WKWebView markdown renderer
- `EonCode/Shared/Views/Code/CodeView.swift` — use MarkdownWebView in ServerMessageRow + ServerStreamingRow
- `EonCode/Shared/Views/Chat/ChatView.swift` — use MarkdownWebView in MessageBubble

### Server — Modified
- `navi-brain/code-agent.js` — filter XML tool calls from streamed text; add web_search, fetch_url, glob, create_directory tools; improve buildSystemPrompt to load MD files
- `navi-brain/server.js` — add APNs sender, trigger on session done/error, add hourly summarizer

### Navi-brain MD — Modified/Created
- `/Users/tedsvard/Library/Mobile Documents/com~apple~CloudDocs/Navi-brain/core.md` — enhance
- `/Users/tedsvard/Library/Mobile Documents/com~apple~CloudDocs/Navi-brain/develop.md` — enhance
- `/Users/tedsvard/Library/Mobile Documents/com~apple~CloudDocs/Navi-brain/server.md` — enhance
- `/Users/tedsvard/Library/Mobile Documents/com~apple~CloudDocs/Navi-brain/tools.md` — NEW: comprehensive tool guide
- `/Users/tedsvard/Library/Mobile Documents/com~apple~CloudDocs/Navi-brain/projects.md` — NEW: project context
- `/Users/tedsvard/Library/Mobile Documents/com~apple~CloudDocs/Navi-brain/learnings/` — NEW dir: hourly session summaries

---

## Phase 1 — Quick UI Fixes

### Task 1: Remove "Tänker" from top bar in CodeView

**Files:**
- Modify: `EonCode/Shared/Views/Code/CodeView.swift`

The `phaseStrip` view shows "Tänker..." + step counter at the top when `session.isRunning`. This duplicates the `ServerActivityRow` already shown inside the messages list. Remove the phaseStrip from the top, keep `ServerActivityRow` in chat.

- [ ] **Step 1: Read the topBar section** to find exact phaseStrip code

```
Read: EonCode/Shared/Views/Code/CodeView.swift lines 106-119
```

The block to remove is:
```swift
// Phase progress strip — visible while running
if session.isRunning {
    phaseStrip
        .transition(.move(edge: .top).combined(with: .opacity))
}
```

- [ ] **Step 2: Remove phaseStrip block from topBar**

In `CodeView.swift`, in the `topBar` computed var, remove:
```swift
// Phase progress strip — visible while running
if session.isRunning {
    phaseStrip
        .transition(.move(edge: .top).combined(with: .opacity))
}
```

Also remove from the `.animation` modifiers:
```swift
.animation(NaviTheme.Spring.smooth, value: session.isRunning)
```
(keep the one for `showTodoPanel`)

The `phaseStrip` view definition itself can stay (it's used elsewhere) or be removed if unused — grep to verify.

- [ ] **Step 3: Verify build** — Open Xcode, build scheme `Navi-iOS`. Confirm 0 errors.

- [ ] **Step 4: Commit**
```bash
git add "EonCode/Shared/Views/Code/CodeView.swift"
git commit -m "fix(ui): remove duplicate Tänker indicator from CodeView top bar"
```

---

### Task 2: Filter XML tool call syntax from streamed text (server)

**Files:**
- Modify: `navi-brain/code-agent.js`

MiniMax sometimes outputs tool calls as `<invoke name="...">...</invoke>` XML tags in the text stream rather than as structured function calls. These raw XML strings flow into `TEXT_DELTA` events and appear verbatim in the iOS chat. Fix: strip these XML blocks from streamed text server-side.

- [ ] **Step 1: Find the TEXT_DELTA emit in code-agent.js**

```bash
grep -n "TEXT_DELTA\|onDelta\|fullText" navi-brain/code-agent.js | head -20
```

The delta callback is passed as `(delta) => session.emit({ type: 'TEXT_DELTA', delta })`.

- [ ] **Step 2: Add XML filter function at top of code-agent.js**

After the imports, add:
```javascript
// Strip raw XML tool call blocks from streamed text (MiniMax sometimes emits these)
function filterToolXML(text) {
  if (!text) return text;
  // Remove complete <invoke>...</invoke> blocks
  return text
    .replace(/<invoke[\s\S]*?<\/invoke>/g, '')
    .replace(/<minimax:tool_call[\s\S]*?<\/minimax:tool_call>/g, '')
    .replace(/<tool_call[\s\S]*?<\/tool_call>/g, '')
    .trim();
}
```

- [ ] **Step 3: Apply filter to TEXT_DELTA emit**

Find the `onDelta` callback passed to `streamOpenRouter` and `streamAnthropic`. Wrap the delta:

```javascript
// Before:
(delta) => session.emit({ type: 'TEXT_DELTA', delta }),

// After:
(delta) => {
  const clean = filterToolXML(delta);
  if (clean) session.emit({ type: 'TEXT_DELTA', delta: clean });
},
```

Also filter `TEXT_COMMIT`:
```javascript
// Before:
if (streamResult.fullText?.trim()) {
  session.emit({ type: 'TEXT_COMMIT', text: streamResult.fullText });
}

// After:
const cleanText = filterToolXML(streamResult.fullText);
if (cleanText?.trim()) {
  session.emit({ type: 'TEXT_COMMIT', text: cleanText });
}
```

- [ ] **Step 4: Restart server and test**
```bash
ssh root@209.38.98.107 "cd /root/navi-brain && pm2 restart navi-brain && pm2 logs navi-brain --lines 10"
```

- [ ] **Step 5: Commit**
```bash
git add navi-brain/code-agent.js
git commit -m "fix(agent): filter XML tool call syntax from streamed text"
```

---

## Phase 2 — WebKit Markdown Rendering

### Task 3: Create MarkdownWebView.swift

**Files:**
- Create: `EonCode/Shared/Views/Components/MarkdownWebView.swift`

Replace the current text-based markdown with a WKWebView renderer. Uses inline HTML with `highlight.js` (bundled as string constants — no network calls) and custom CSS matching Navi's design system. Supports: headers, bold, italic, inline code, code blocks with syntax highlighting, tables, blockquotes, lists, horizontal rules.

The view uses `updateUIView` (UIViewRepresentable) to update content when text changes, calling `appendDelta()` JS for streaming updates.

- [ ] **Step 1: Add WKWebKit import to Xcode target** — ensure `WebKit` framework is linked in the Navi-iOS target. Check in Xcode: Target → Frameworks, Libraries, and Embedded Content. If missing, add `WebKit.framework`.

- [ ] **Step 2: Create MarkdownWebView.swift**

```swift
import SwiftUI
import WebKit

#if os(iOS)
// MARK: - MarkdownWebView
// WKWebView-based markdown renderer with syntax highlighting.
// Streams updates via evaluateJavaScript for real-time display.

struct MarkdownWebView: UIViewRepresentable {
    let text: String
    var isStreaming: Bool = false
    var fontSize: CGFloat = 16

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(buildHTML(text: "", fontSize: fontSize), baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastText == text { return }
        context.coordinator.lastText = text
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        webView.evaluateJavaScript("updateContent(`\(escaped)`)", completionHandler: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastText = ""
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Sync height after load
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                // Parent handles sizing via intrinsic content size
            }
        }
    }
}

// MARK: - HTML Builder

private func buildHTML(text: String, fontSize: CGFloat) -> String {
    let isDark = UITraitCollection.current.userInterfaceStyle == .dark
    let bg = "transparent"
    let fg = isDark ? "#e8e8e8" : "#1a1a1a"
    let codeBg = isDark ? "#1e1e2e" : "#f5f5f7"
    let codeColor = isDark ? "#cdd6f4" : "#333"
    let blockquoteBg = isDark ? "rgba(255,255,255,0.04)" : "rgba(0,0,0,0.04)"
    let blockquoteBorder = isDark ? "#555" : "#ccc"
    let tableBorder = isDark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.1)"
    let linkColor = "#FF8C42"

    return """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/\(isDark ? "github-dark" : "github").min.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/marked/9.1.6/marked.min.js"></script>
    <style>
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body {
        font-family: -apple-system, "SF Pro Text", sans-serif;
        font-size: \(Int(fontSize))px;
        line-height: 1.65;
        color: \(fg);
        background: \(bg);
        word-break: break-word;
        -webkit-text-size-adjust: none;
        padding: 0;
      }
      h1 { font-size: 1.5em; font-weight: 700; margin: 18px 0 8px; }
      h2 { font-size: 1.25em; font-weight: 650; margin: 16px 0 6px; }
      h3 { font-size: 1.1em; font-weight: 600; margin: 14px 0 5px; }
      h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
      p { margin: 6px 0; }
      p + p { margin-top: 10px; }
      ul, ol { padding-left: 20px; margin: 6px 0; }
      li { margin: 3px 0; }
      a { color: \(linkColor); text-decoration: none; }
      strong { font-weight: 650; }
      em { font-style: italic; }
      code {
        font-family: "SF Mono", Menlo, monospace;
        font-size: 0.875em;
        background: \(codeBg);
        color: \(codeColor);
        padding: 1px 5px;
        border-radius: 4px;
      }
      pre {
        background: \(codeBg);
        border-radius: 10px;
        padding: 14px 16px;
        margin: 10px 0;
        overflow-x: auto;
        -webkit-overflow-scrolling: touch;
      }
      pre code {
        background: none;
        padding: 0;
        font-size: 0.85em;
        line-height: 1.55;
      }
      blockquote {
        border-left: 3px solid \(blockquoteBorder);
        background: \(blockquoteBg);
        padding: 8px 14px;
        margin: 8px 0;
        border-radius: 0 6px 6px 0;
      }
      table {
        border-collapse: collapse;
        width: 100%;
        margin: 10px 0;
        font-size: 0.9em;
      }
      th, td {
        border: 1px solid \(tableBorder);
        padding: 7px 12px;
        text-align: left;
      }
      th { font-weight: 600; background: \(codeBg); }
      hr { border: none; border-top: 1px solid \(tableBorder); margin: 14px 0; }
    </style>
    </head>
    <body>
    <div id="content"></div>
    <script>
      marked.setOptions({
        highlight: function(code, lang) {
          if (lang && hljs.getLanguage(lang)) {
            return hljs.highlight(code, { language: lang }).value;
          }
          return hljs.highlightAuto(code).value;
        }
      });
      function updateContent(md) {
        document.getElementById('content').innerHTML = marked.parse(md || '');
        document.querySelectorAll('pre code').forEach(el => hljs.highlightElement(el));
      }
      updateContent(`\(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`"))`);
    </script>
    </body>
    </html>
    """
}
#endif
```

**Note:** The CDN-loaded highlight.js and marked.js require internet. For offline use, bundle these as Swift string constants. For now CDN is acceptable given the app requires server connectivity anyway.

- [ ] **Step 3: Build and verify** — compile, fix any errors.

- [ ] **Step 4: Commit**
```bash
git add "EonCode/Shared/Views/Components/MarkdownWebView.swift"
git commit -m "feat(ui): add WKWebView-based MarkdownWebView with syntax highlighting"
```

---

### Task 4: Use MarkdownWebView in CodeView and ChatView

**Files:**
- Modify: `EonCode/Shared/Views/Code/CodeView.swift`
- Modify: `EonCode/Shared/Views/Chat/ChatView.swift`

Replace `MarkdownTextView(text:)` calls with `MarkdownWebView(text:)`.

- [ ] **Step 1: In CodeView.swift, find all MarkdownTextView usages**
```bash
grep -n "MarkdownTextView" "EonCode/Shared/Views/Code/CodeView.swift"
```

- [ ] **Step 2: Replace in ServerMessageRow.assistantRow**
```swift
// Before:
MarkdownTextView(text: message.text)
    .textSelection(.enabled)

// After:
MarkdownWebView(text: message.text)
    .frame(maxWidth: .infinity, alignment: .leading)
```

- [ ] **Step 3: Replace in ServerStreamingRow**
```swift
// Before:
MarkdownTextView(text: text)

// After:
MarkdownWebView(text: text, isStreaming: true)
```

- [ ] **Step 4: In ChatView.swift, find and replace MessageBubble markdown usage**
```bash
grep -n "MarkdownTextView\|markdownText" "EonCode/Shared/Views/Chat/ChatView.swift"
```
Replace similarly.

- [ ] **Step 5: Build and verify** — `0 errors, 0 warnings`.

- [ ] **Step 6: Commit**
```bash
git add "EonCode/Shared/Views/Code/CodeView.swift" "EonCode/Shared/Views/Chat/ChatView.swift"
git commit -m "feat(ui): use MarkdownWebView for ChatGPT-quality text rendering"
```

---

## Phase 3 — Native APNs Push Notifications

### Task 5: Server — APNs sender module

**Files:**
- Create: `navi-brain/apns.js`
- Modify: `navi-brain/package.json` (add `@parse/node-apn` or use raw HTTP/2)

APNs requires HTTP/2. Use `node-apn` package for simplicity.

- [ ] **Step 1: Install node-apn on server**
```bash
ssh root@209.38.98.107 "cd /root/navi-brain && npm install @parse/node-apn --save && pm2 restart navi-brain"
```

- [ ] **Step 2: Create apns.js**

```javascript
// ============================================================
// APNs sender — sends native iOS push notifications
// Uses p8 key (same AuthKey.p8 used for App Store Connect)
// ============================================================

const apn = require('@parse/node-apn');
const path = require('path');

let provider = null;

function init() {
  const keyPath = process.env.APN_KEY_PATH || path.join(__dirname, 'AuthKey.p8');
  const keyId   = process.env.APN_KEY_ID   || process.env.ASC_KEY_ID || '';
  const teamId  = process.env.APN_TEAM_ID  || process.env.ASC_ISSUER_ID?.split('.')[0] || '';

  if (!keyId || !teamId) {
    console.warn('[APNs] APN_KEY_ID or APN_TEAM_ID not set — APNs disabled');
    return;
  }

  try {
    provider = new apn.Provider({
      token: {
        key: keyPath,
        keyId,
        teamId,
      },
      production: false, // set to true for App Store builds
    });
    console.log('[APNs] Provider initialized');
  } catch (e) {
    console.error('[APNs] Failed to init provider:', e.message);
  }
}

async function sendPush({ tokens, title, body, data = {}, badge = 1 }) {
  if (!provider) return { sent: 0, failed: tokens.length };
  if (!tokens || tokens.length === 0) return { sent: 0, failed: 0 };

  const note = new apn.Notification();
  note.expiry = Math.floor(Date.now() / 1000) + 3600; // 1 hour TTL
  note.badge = badge;
  note.sound = 'default';
  note.alert = { title, body };
  note.payload = data;
  note.topic = process.env.APN_BUNDLE_ID || 'com.tedsvard.navi.ios';

  try {
    const result = await provider.send(note, tokens);
    console.log(`[APNs] Sent: ${result.sent.length}, Failed: ${result.failed.length}`);
    return { sent: result.sent.length, failed: result.failed.length };
  } catch (e) {
    console.error('[APNs] Send error:', e.message);
    return { sent: 0, failed: tokens.length };
  }
}

module.exports = { init, sendPush };
```

- [ ] **Step 3: Set env vars on server**

Add to PM2 ecosystem or `.env` on server:
```
APN_KEY_ID=your_key_id      # same as ASC_KEY_ID if same p8 file
APN_TEAM_ID=your_team_id    # 10-char Apple Team ID
APN_BUNDLE_ID=com.tedsvard.navi.ios
```

Check if ASC_KEY_ID and ASC_ISSUER_ID are already set:
```bash
ssh root@209.38.98.107 "pm2 env navi-brain | grep -E 'ASC|APN'"
```

- [ ] **Step 4: Commit**
```bash
git add navi-brain/apns.js navi-brain/package.json
git commit -m "feat(server): add APNs sender module"
```

---

### Task 6: Server — Send APNs when code session completes

**Files:**
- Modify: `navi-brain/server.js`
- Modify: `navi-brain/code-agent.js`

- [ ] **Step 1: In server.js, require and init APNs module**

Near the top of `server.js`:
```javascript
const apns = require('./apns');
// After config section:
apns.init();
```

- [ ] **Step 2: In code-agent.js, emit APNs event on session completion**

Find where sessions emit `RUN_FINISHED` and `RUN_ERROR`. After these events, trigger a callback. The cleanest approach: add an `onComplete` callback to the session that server.js registers.

In `code-agent.js`, where `RUN_FINISHED` is emitted:
```javascript
// After: session.emit({ type: 'RUN_FINISHED', ... })
if (typeof session.onComplete === 'function') {
  session.onComplete({ status: 'done', task: session.initialTask, summary: streamResult.fullText?.slice(0, 200) });
}
```

Similarly for `RUN_ERROR`:
```javascript
if (typeof session.onComplete === 'function') {
  session.onComplete({ status: 'error', task: session.initialTask, error: errorMessage });
}
```

- [ ] **Step 3: In server.js, register onComplete to send APNs**

In the code session start handler (where `codeAgent.createSession` is called or WebSocket SUBSCRIBE happens), add:
```javascript
session.onComplete = async ({ status, task, summary, error }) => {
  const tokens = Array.from(pushTokens);
  if (tokens.length === 0) return;

  const title = status === 'done' ? '✅ Navi — Klar' : '⚠️ Navi — Fel';
  const body = status === 'done'
    ? (summary || `Uppgiften "${task.slice(0, 60)}" är klar`)
    : `Fel under "${task.slice(0, 50)}"`;

  await apns.sendPush({
    tokens,
    title,
    body,
    data: { sessionId: session.id, deeplink: `navi://code/session/${session.id}` },
  });
  addLog('APNS', `Push skickat: ${status} — ${tokens.length} enheter`);
};
```

- [ ] **Step 4: Restart and test**
```bash
ssh root@209.38.98.107 "cd /root/navi-brain && pm2 restart navi-brain && pm2 logs navi-brain --lines 20"
```

- [ ] **Step 5: Commit**
```bash
git add navi-brain/server.js navi-brain/code-agent.js
git commit -m "feat(server): send APNs push notification when code session completes"
```

---

### Task 7: iOS — Handle notification tap to open session

**Files:**
- Modify: `EonCode/Shared/NaviApp.swift`
- Modify: `EonCode/Shared/Services/Notifications/NotificationManager.swift`

- [ ] **Step 1: In NotificationManager, handle notification response**

Find `UNUserNotificationCenterDelegate` or add it. Add:
```swift
func userNotificationCenter(_ center: UNUserNotificationCenter,
                             didReceive response: UNNotificationResponse,
                             withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo
    if let sessionId = userInfo["sessionId"] as? String {
        // Navigate to that session
        Task { @MainActor in
            ServerCodeSession.shared.resumeSession(sessionId)
            NotificationCenter.default.post(
                name: .navigateToCodeSession,
                object: nil,
                userInfo: ["sessionId": sessionId]
            )
        }
    }
    completionHandler()
}
```

- [ ] **Step 2: Add Notification.Name extension**
```swift
extension Notification.Name {
    static let navigateToCodeSession = Notification.Name("navigateToCodeSession")
}
```

- [ ] **Step 3: In ContentView or main navigation, listen for this notification and switch to Code tab**

Find the root navigation view (likely `ContentView.swift`). Add:
```swift
.onReceive(NotificationCenter.default.publisher(for: .navigateToCodeSession)) { _ in
    selectedTab = .code
    showSidebar = false
}
```

- [ ] **Step 4: Build and test** — send a test notification via curl from server, tap it.

- [ ] **Step 5: Commit**
```bash
git add "EonCode/Shared/NaviApp.swift" "EonCode/Shared/Services/Notifications/NotificationManager.swift"
git commit -m "feat(ios): handle APNs notification tap to open code session"
```

---

## Phase 4 — Navi-brain MD Enhancement + Server Injection

### Task 8: Enhance and expand Navi-brain MD files

**Files (on local machine, synced to iCloud):**
- `/Users/tedsvard/Library/Mobile Documents/com~apple~CloudDocs/Navi-brain/core.md`
- `/Users/tedsvard/Library/Mobile Documents/com~apple~CloudDocs/Navi-brain/develop.md`
- `/Users/tedsvard/Library/Mobile Documents/com~apple~CloudDocs/Navi-brain/server.md`
- Create: `tools.md` — complete tool reference for the code agent
- Create: `projects.md` — current project context (repos, tech stack, conventions)

- [ ] **Step 1: Enhance core.md**

Add to the existing `core.md`:
- Section on the agent's tool set (reference tools.md)
- Section on code quality expectations (production-grade, no placeholders)
- Section on current server environment (Ubuntu, PM2, /root/navi-brain/)
- Section on iCloud paths

- [ ] **Step 2: Enhance develop.md**

Add:
- SwiftUI/Swift best practices specific to this codebase (NaviTheme, @StateObject patterns)
- Server-side patterns (Express routes, WebSocket emit, PM2 restart)
- Testing protocol (build verification, swift build, pm2 logs)
- Git workflow (feature branches, commit style)

- [ ] **Step 3: Enhance server.md**

Add:
- Actual server layout: `/root/navi-brain/`, data dir, workspace dir
- PM2 commands: `pm2 list`, `pm2 restart navi-brain`, `pm2 logs navi-brain --lines 50`
- Current env vars available (OPENROUTER_KEY, ANTHROPIC_API_KEY, GITHUB_TOKEN etc.)
- How code sessions work (WebSocket, session files, workDir)

- [ ] **Step 4: Create tools.md**

```markdown
# NAVI — TOOL REFERENCE

## Available Tools (Code Agent)

### read_file(path, start_line?, end_line?)
Read file with line numbers. Always read before editing.

### write_file(path, content)
Write complete file. Creates parent dirs. Runs lint after.

### edit_file(path, old_text, new_text)
Exact search/replace. Read file first to get exact text.

### run_command(command, cwd?, timeout?)
Run shell command. Async-safe. Default timeout 120s.
Examples:
- `npm install && npm test`
- `swift build 2>&1 | tail -30`
- `pm2 restart navi-brain && pm2 logs navi-brain --lines 20`

### grep(pattern, path, file_pattern?, context_lines?)
Search with regex. Returns matching lines with context.

### list_files(path, recursive?)
List directory. Excludes node_modules, .git, .build.

### web_search(query)
Search the web. Use for: library docs, error messages, Stack Overflow.
Examples: `web_search("swiftui wkwebview intrinsic content size")`

### fetch_url(url)
Fetch URL content. Use for: GitHub raw files, official docs, APIs.
Examples: `fetch_url("https://raw.githubusercontent.com/user/repo/main/file.swift")`

### glob(pattern, base_path?)
Find files by pattern. Fast alternative to list_files.
Examples: `glob("**/*.swift", "/root/workspace/MyProject")`

### todo_write(todos)
Update task list. Call at start + when plan changes. Visible to user.

### git_commit(message, cwd?)
Stage all + commit. Use at meaningful milestones.

### create_directory(path)
Create directory + parents.

## Tool Selection Guide
| Need | Tool |
|------|------|
| Read part of a large file | read_file with start_line/end_line |
| Find where function is defined | grep("func functionName", path) |
| Find all Swift files | glob("**/*.swift", workDir) |
| Install a package | run_command("npm install package") |
| Check if code compiles | run_command("swift build 2>&1") |
| Look up API docs | fetch_url(official docs URL) |
| Debug error message | web_search("exact error message") |
| Edit a specific line | read_file → edit_file |
```

- [ ] **Step 5: Create projects.md**

```markdown
# NAVI — ACTIVE PROJECTS

## Navi-v6 (this repo)
- **iOS app:** EonCode/ — SwiftUI, NaviTheme design system, MVVM
- **Server:** navi-brain/ — Node.js, Express, WebSocket, PM2
- **iCloud:** ~/Library/Mobile Documents/com~apple~CloudDocs/Navi-v6/
- **Server path:** /root/navi-brain/
- **Server IP:** 209.38.98.107:3001
- **Key files:** code-agent.js (code agent loop), server.js (REST + general chat)

## GitHub Repos (Terrorbyte90)
- Navi-v6, Lifetoken, Lillajag3, Lunaflix2, BabyCare, Eon-Code-v2

## Tech Stack Norms
- iOS: Swift 5.9+, SwiftUI, iOS 17+, @Observable or @StateObject
- Server: Node.js 20+, Express, ws (WebSocket), pm2
- Models: MiniMax M2.5, Qwen3-Coder, DeepSeek R1, Claude Sonnet 4.6
- Routing: OpenRouter (minimax/qwen/deepseek), Anthropic API (claude)

## Code Conventions
- Swedish in UI strings, comments can be English
- NaviTheme.* for all colors/fonts
- Commit style: "feat(scope): description" or "fix(scope): description"
- No force unwraps, no placeholder implementations
```

- [ ] **Step 6: Commit MD changes**
```bash
git add "Navi-brain/" 2>/dev/null || true
git commit -m "docs(brain): enhance and expand Navi-brain knowledge base"
```

---

### Task 9: Load MD files into code agent system prompt

**Files:**
- Modify: `navi-brain/code-agent.js`

The `buildSystemPrompt()` function currently returns a hardcoded string. Extend it to load all MD files from the navi-brain knowledge base and prepend them as context.

- [ ] **Step 1: Find the MD files on the server**

The iCloud folder syncs to the server at:
```bash
ssh root@209.38.98.107 "ls /root/navi-brain/knowledge/ 2>/dev/null || ls /root/navi-brain/*.md 2>/dev/null"
```

If they're not on the server yet, add a sync step or copy them there. Create `/root/navi-brain/knowledge/` and copy the MD files there.

- [ ] **Step 2: Add MD loader to code-agent.js**

After the imports, add:
```javascript
const KNOWLEDGE_DIR = path.join(__dirname, 'knowledge');

function loadKnowledgeBase() {
  try {
    if (!fs.existsSync(KNOWLEDGE_DIR)) return '';
    const files = fs.readdirSync(KNOWLEDGE_DIR)
      .filter(f => f.endsWith('.md') && !f.startsWith('_'))
      .sort();
    const contents = files.map(f => {
      const content = fs.readFileSync(path.join(KNOWLEDGE_DIR, f), 'utf8');
      return `--- ${f} ---\n${content}`;
    }).join('\n\n');
    return contents;
  } catch (e) {
    console.error('[KNOWLEDGE] Failed to load:', e.message);
    return '';
  }
}

// Cache knowledge base (reload every 5 min if files change)
let _knowledgeCache = null;
let _knowledgeLoadedAt = 0;
function getKnowledge() {
  const now = Date.now();
  if (!_knowledgeCache || now - _knowledgeLoadedAt > 5 * 60 * 1000) {
    _knowledgeCache = loadKnowledgeBase();
    _knowledgeLoadedAt = now;
  }
  return _knowledgeCache;
}
```

- [ ] **Step 3: Inject knowledge into buildSystemPrompt**

In `buildSystemPrompt()`, prepend the knowledge base:
```javascript
function buildSystemPrompt(session) {
  const knowledge = getKnowledge();
  const knowledgeSection = knowledge
    ? `## Kunskapsbas (läs och följ dessa riktlinjer)\n\n${knowledge}\n\n---\n\n`
    : '';

  // ... rest of existing prompt
  return `${knowledgeSection}Du är Navi — världens mest avancerade autonoma kodagent...`;
}
```

- [ ] **Step 4: Copy MD files to server**
```bash
scp -r "/Users/tedsvard/Library/Mobile Documents/com~apple~CloudDocs/Navi-brain/"*.md root@209.38.98.107:/root/navi-brain/knowledge/
```

- [ ] **Step 5: Restart and verify**
```bash
ssh root@209.38.98.107 "pm2 restart navi-brain && pm2 logs navi-brain --lines 20"
```

- [ ] **Step 6: Commit**
```bash
git add navi-brain/code-agent.js
git commit -m "feat(agent): load Navi-brain knowledge base into system prompt"
```

---

## Phase 5 — Hourly Session Learning Summaries

### Task 10: Server — Hourly session summarizer

**Files:**
- Modify: `navi-brain/server.js`

Every hour, read the 5 most recently completed code sessions, ask the model to summarize each one (what was asked, what was done, output, lärdom), and write an MD file to `/root/navi-brain/knowledge/learnings/`. The model may also append relevant learnings to existing knowledge base files.

- [ ] **Step 1: Add summarizer function to server.js**

At the bottom of server.js (before the listen call), add:

```javascript
// ============================================================
// HOURLY SESSION SUMMARIZER
// ============================================================

const LEARNINGS_DIR = path.join(__dirname, 'knowledge', 'learnings');

async function summarizeSessions() {
  try {
    if (!fs.existsSync(LEARNINGS_DIR)) {
      fs.mkdirSync(LEARNINGS_DIR, { recursive: true });
    }

    // Get 5 most recent completed code sessions
    const sessionsData = codeAgent.getRecentCompletedSessions(5);
    if (!sessionsData || sessionsData.length === 0) {
      addLog('SUMMARIZER', 'Inga avslutade sessioner att sammanfatta');
      return;
    }

    const sessionsSummary = sessionsData.map((s, i) =>
      `### Session ${i + 1}\n**Uppgift:** ${s.task}\n**Status:** ${s.status}\n**Modell:** ${s.model}\n**Meddelanden:** ${s.messageCount}\n**Senaste output:**\n${s.lastOutput?.slice(0, 1000) || '(tom)'}`
    ).join('\n\n');

    const prompt = `Du är en lärande AI-agent. Analysera dessa nyligen avslutade kod-sessioner och skriv en strukturerad sammanfattning på svenska.

${sessionsSummary}

Skriv en Markdown-fil med exakt detta format:
# Session-lärdomar ${new Date().toISOString().slice(0, 13)}

## Sammanfattning per session

[För varje session:]
### [Kort titel på uppgiften]
- **Vad frågades:** [beskrivning]
- **Vad gjordes:** [steg som togs]
- **Output/Resultat:** [vad som producerades]
- **Lärdom:** [konkret lärdom att ta med sig]

## Generella mönster
[Om du ser återkommande mönster, problem eller förbättringsområden]

## Föreslagna uppdateringar till kunskapsbasen
[Om du bedömer att någon befintlig knowledge base-fil bör uppdateras, skriv exakt vad som ska läggas till och i vilken fil]`;

    // Call model
    const body = JSON.stringify({
      model: MODELS.minimax,
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 2000,
      temperature: 0.3,
    });

    const raw = await callOpenRouterSimple(
      [{ role: 'user', content: prompt }],
      OPENROUTER_KEY,
      MODELS.minimax
    );

    // Save to learnings dir
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 16);
    const filename = path.join(LEARNINGS_DIR, `${timestamp}.md`);
    fs.writeFileSync(filename, raw, 'utf8');
    addLog('SUMMARIZER', `Sammanfattning sparad: ${path.basename(filename)}`);

  } catch (e) {
    addLog('SUMMARIZER', `Fel vid sammanfattning: ${e.message}`);
  }
}

// Run every hour
setInterval(summarizeSessions, 60 * 60 * 1000);
// Also run 2 minutes after startup
setTimeout(summarizeSessions, 2 * 60 * 1000);
```

- [ ] **Step 2: Add getRecentCompletedSessions to code-agent.js**

In code-agent.js, add an exported function that returns recent sessions:
```javascript
function getRecentCompletedSessions(limit = 5) {
  return Object.values(sessions)
    .filter(s => s.status === 'done' || s.status === 'error')
    .sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))
    .slice(0, limit)
    .map(s => ({
      id: s.id,
      task: s.initialTask || s.task,
      status: s.status,
      model: s.model,
      messageCount: s.messages?.length || 0,
      lastOutput: s.messages?.filter(m => m.role === 'assistant')
        .map(m => typeof m.content === 'string' ? m.content : JSON.stringify(m.content))
        .slice(-1)[0] || '',
    }));
}

module.exports = { init, createSession, getSession, resumeSession, stopSession, getRecentCompletedSessions };
```

- [ ] **Step 3: Restart and verify**
```bash
ssh root@209.38.98.107 "pm2 restart navi-brain && sleep 130 && ls /root/navi-brain/knowledge/learnings/"
```

- [ ] **Step 4: Commit**
```bash
git add navi-brain/server.js navi-brain/code-agent.js
git commit -m "feat(server): hourly session summarizer writes learning MD files"
```

---

## Phase 6 — Code Agent Intelligence Expansion

### Task 11: Add web_search, fetch_url, glob, create_directory tools

**Files:**
- Modify: `navi-brain/code-agent.js`

- [ ] **Step 1: Add tool definitions to CODE_TOOLS array**

```javascript
{
  name: 'web_search',
  description: 'Search the web for information. Use for: error messages, library docs, Stack Overflow answers, current information.',
  parameters: {
    type: 'object',
    properties: {
      query: { type: 'string', description: 'Search query' },
    },
    required: ['query'],
  },
},
{
  name: 'fetch_url',
  description: 'Fetch content from a URL. Use for: GitHub raw files, official documentation, APIs, package READMEs.',
  parameters: {
    type: 'object',
    properties: {
      url: { type: 'string', description: 'URL to fetch' },
    },
    required: ['url'],
  },
},
{
  name: 'glob',
  description: 'Find files matching a glob pattern. Faster than list_files for finding specific file types.',
  parameters: {
    type: 'object',
    properties: {
      pattern: { type: 'string', description: 'Glob pattern e.g. "**/*.swift" or "src/**/*.ts"' },
      base_path: { type: 'string', description: 'Base directory to search in (default: workspace)' },
    },
    required: ['pattern'],
  },
},
{
  name: 'create_directory',
  description: 'Create a directory and all parent directories.',
  parameters: {
    type: 'object',
    properties: {
      path: { type: 'string', description: 'Directory path to create' },
    },
    required: ['path'],
  },
},
```

- [ ] **Step 2: Implement web_search in executeTool**

Find the `executeTool` or `handleToolCall` function in code-agent.js. Add cases:

```javascript
case 'web_search': {
  const query = encodeURIComponent(args.query);
  // Use DuckDuckGo API (no key needed) or Brave Search
  const url = `https://api.duckduckgo.com/?q=${query}&format=json&no_redirect=1&no_html=1`;
  try {
    const res = await fetchURL(url);
    const data = JSON.parse(res);
    const results = [
      data.AbstractText ? `**Abstract:** ${data.AbstractText}` : '',
      ...(data.RelatedTopics || []).slice(0, 5).map(t => t.Text || '').filter(Boolean),
    ].filter(Boolean).join('\n\n');
    return results || 'Inga resultat hittades. Prova fetch_url med en specifik URL.';
  } catch (e) {
    return `web_search misslyckades: ${e.message}`;
  }
}

case 'fetch_url': {
  try {
    const content = await fetchURL(args.url);
    // Truncate to avoid context overflow
    return content.length > 8000 ? content.slice(0, 8000) + '\n\n[...trunkerad]' : content;
  } catch (e) {
    return `fetch_url misslyckades: ${e.message}`;
  }
}

case 'glob': {
  const base = args.base_path || session.workDir;
  try {
    const result = await asyncExec(
      `find "${base}" -path "*/.git" -prune -o -path "*/node_modules" -prune -o -name "${args.pattern.replace('**/', '')}" -print 2>/dev/null | head -100`
    );
    return result.trim() || '(inga filer hittade)';
  } catch (e) {
    return `glob misslyckades: ${e.message}`;
  }
}

case 'create_directory': {
  try {
    fs.mkdirSync(args.path, { recursive: true });
    return `Katalog skapad: ${args.path}`;
  } catch (e) {
    return `create_directory misslyckades: ${e.message}`;
  }
}
```

- [ ] **Step 3: Add fetchURL helper if missing**

```javascript
function fetchURL(url) {
  return new Promise((resolve, reject) => {
    const lib = url.startsWith('https') ? https : http;
    const req = lib.get(url, { headers: { 'User-Agent': 'Navi-Agent/1.0' } }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve(data));
    });
    req.on('error', reject);
    req.setTimeout(10000, () => { req.destroy(); reject(new Error('Timeout')); });
  });
}
```

- [ ] **Step 4: Restart and test**
```bash
ssh root@209.38.98.107 "pm2 restart navi-brain && pm2 logs navi-brain --lines 10"
```

- [ ] **Step 5: Commit**
```bash
git add navi-brain/code-agent.js
git commit -m "feat(agent): add web_search, fetch_url, glob, create_directory tools"
```

---

### Task 12: Improve system prompt for Claude Code/Cursor-level intelligence

**Files:**
- Modify: `navi-brain/code-agent.js` — `buildSystemPrompt()`

- [ ] **Step 1: Add project auto-discovery section to prompt**

In `buildSystemPrompt`, add after the work process section:
```javascript
const projectContext = `
## Auto-discovery protocol (alltid vid projektstart)
\`\`\`
1. run_command("find . -maxdepth 2 -name 'package.json' -o -name 'Cargo.toml' -o -name 'go.mod' -o -name '*.xcodeproj' -o -name 'pubspec.yaml' 2>/dev/null | head -10")
2. run_command("ls -la && git log --oneline -5 2>/dev/null")
3. read_file("README.md") eller read_file("CLAUDE.md") om de finns
4. glob("**/*.swift", workDir) om iOS-projekt
5. Förstå arkitekturen HELT innan du skriver KOD
\`\`\`

## Felsöknings-superkraft
När du fastnar:
1. web_search("exact error message site:stackoverflow.com")
2. fetch_url(officiell dokumentation för biblioteket)
3. fetch_url("https://raw.githubusercontent.com/[repo]/main/[relevant-file]")
4. Prova HELT ANNAT tillvägagångssätt
5. Skriv ett minimal repro-test för att isolera problemet

## Kvalitetsmål — bättre än Claude Code & Cursor
- Förstå HELA kodbasen innan du rör något
- Läs alltid filen innan du editerar (exakt text-match)
- Kör alltid bygget/testerna och verifiera grönt
- Committa vid varje fungerande milestone
- Förklara ditt resonemang tydligt på svenska
- Leverera produktionsklar kod — aldrig "detta är ett exempel"
- Håll track record av vad du gjort via todo_write
`;
```

- [ ] **Step 2: Add intelligent error recovery section**

```javascript
const errorRecovery = `
## Intelligent felåterställning
Om ett kommando misslyckas:
1. Läs felmeddelandet NOGA — det berättar exakt vad som är fel
2. Kör INTE samma sak igen utan att förstå felet
3. Isolera felet: är det syntax, typ, import, beroende eller logik?
4. För Swift-fel: kör \`swift build 2>&1 | grep error:\` för att se alla fel på en gång
5. För npm-fel: kör \`npm install\` om moduler saknas, kolla \`node_modules/\`
6. För git-fel: \`git status && git log --oneline -5\` för att förstå tillståndet

## Minnesstrategi
- Använd todo_write för att hålla full kontext
- Referera alltid tillbaka till originaluppgiften
- Om en fil är lång: använd grep och read_file med start/end_line
- Kompaktera inte kontext manuellt — det sker automatiskt
`;
```

- [ ] **Step 3: Deploy and test with a real task**

Start a code session and ask it to build something real. Verify it:
- Uses web_search when encountering errors
- Runs builds and tests
- Follows the enhanced protocol

- [ ] **Step 4: Commit**
```bash
git add navi-brain/code-agent.js
git commit -m "feat(agent): supercharge system prompt for Claude Code/Cursor-level intelligence"
```

---

## Final Steps

- [ ] **Deploy all server changes**
```bash
ssh root@209.38.98.107 "cd /root/navi-brain && git pull && npm install && pm2 restart navi-brain && pm2 logs navi-brain --lines 30"
```

- [ ] **Build iOS app in Xcode** — confirm 0 errors, 0 warnings

- [ ] **End-to-end test:**
  1. Start a code session in the iOS app
  2. Close the app
  3. Wait for session to complete
  4. Receive APNs push notification
  5. Tap notification → opens Navi → Code tab shows session
  6. Markdown renders beautifully with syntax highlighting
  7. No "Tänker" at top of screen
  8. No raw XML tool calls visible in chat

- [ ] **Final commit**
```bash
git add -A
git commit -m "feat: Navi mega upgrade — APNs, WebKit markdown, knowledge injection, smarter agent"
```
