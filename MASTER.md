# MASTER.md — Navi-v6

---

## Vision

Navi is a unified AI-assisted development environment built for one person: a developer who wants to code from anywhere — including from iPhone — and have a persistent, intelligent agent continue working even when the app is closed. It replaces Claude Code CLI, Cursor, and GitHub as separate tools by bringing them into a single, beautiful native experience.

The finished product is a professional-grade coding companion that runs on both iOS and macOS, powered by a persistent Node.js server backend (Navi Brain) on DigitalOcean. The iOS app is a display layer: it streams agent thoughts, tool executions, and code output in real time. When you close the app, the agent keeps working. When you reopen it, everything is right where you left it.

The app is for one user — a solo developer who builds multiple iOS apps and wants an intelligent assistant that knows his projects deeply, can execute code autonomously, commit to GitHub, and respond to natural language instructions from a phone screen.

At its best, Navi looks like this: you open it on your iPhone, type a task, watch the agent spin up and begin executing — reading files, running commands, writing code, committing to git — all in real time, streamed beautifully to your screen. You can close the app, make coffee, and come back to a finished feature.

**What makes Navi different:**
- Persistent server-side agents that survive app closure
- Seamless iPhone ↔ Mac workflow via iCloud sync
- Native multi-provider AI routing (Anthropic, xAI, OpenRouter) with real cost tracking in SEK
- Voice, media generation, and GitHub all under one roof
- Warm, Claude-inspired design — not a cold developer tool

---

## UI/UX Standards

### Visual Language

**Color Palette:**
- Primary accent: Terra Cotta `#da7756` — used for buttons, active states, selection indicators
- Accent light: Warm Tan `#e8a08a` — hover states, secondary highlights
- Accent background: `#da7756` at 10% opacity — chip/badge fills
- Code backgrounds: Warm Sand `rgb(245,240,235)` (light) / Soft Slate `rgb(36,36,41)` (dark)
- User bubbles: warm gray fill; assistant messages: transparent (no background)
- Glass tint: white/black at 3–6% opacity for frosted surfaces

**Typography:**
- Body text: `.serif` (New York) 15.5–16pt — warm, readable, non-generic
- Headings: `.rounded` (System) 17pt semibold
- Display: `.rounded` 28pt bold
- Code/mono: `.monospaced` 13pt
- Labels and captions: System 13pt / 11pt

**Spacing system:** 2 / 4 / 8 / 16 / 24 / 32 / 48pt — nothing deviates from this scale.

**Corner radii:** 4 / 8 / 12 / 16 / 20 / 24pt — chat bubbles at 20pt, pills at 24pt.

**Shadows:** Small (4px blur, 2px offset), Medium (8px, 4px), Large (16px, 8px).

### Screen Behavior

**Chat / Pure Chat:** User messages are warm gray pills, right-aligned. Assistant messages are left-aligned, no background, clean serif text. The input bar lives at the bottom with a model picker and send button. The conversation feels like Claude.ai, not a terminal.

**Code View:** Full-screen streaming experience. A phase strip at the top shows the current agent state (thinking → tools → done), iteration count, and live tool name. A collapsible TODO panel shows horizontal scrollable pills with checkmarks. Tool events expand into cards showing name, parameters, execution time, and result. Git commits appear inline as badges with hash + message + file count.

**Sidebar / Navigation:** Icon-based navigation with an underline indicator. The sidebar shows project list, colored and tagged. Switching projects is instant.

**Settings:** Clean grouped form layout. API key fields are masked. Cost totals are shown in SEK, prominent but not intrusive.

### Interaction Principles

- **Quick Spring** (response 0.2, damping 0.85) for snappy UI updates — tab switches, button presses
- **Responsive** (response 0.3, damping 0.8) for smooth modal transitions
- **Bouncy** (response 0.35, damping 0.7) for playful moments — new chat, agent start
- Streaming text appears token-by-token, never dumps content
- All destructive actions require confirmation
- The app never blocks the user — loading states are always communicated

### What Premium Means for Navi

Premium means the experience of watching a capable agent work is beautiful, not clinical. Code blocks have syntax highlighting with a warm sandstone background. The activity pill pulses gently when the agent is thinking. Tool executions expand with a satisfying spring. The streaming text never jumps or flickers. Cost display is precise but unobtrusive. The font choice (New York serif) makes reading long AI output a pleasure rather than a chore.

---

## Daily Improvement Loop

* Pull latest from git, verify local is fully synced before touching anything
* Read all project files, git log, and any DECISIONS.md to understand current state
* Review /agents folder and invoke relevant agents in parallel for today's tasks
* Research what competitors have shipped recently and what users are currently requesting
* Identify the 3-5 highest value tasks today: new features, UI polish, bug fixes, performance
* Create a detailed execution plan and carry it out fully and autonomously
* After each major change — build and verify it compiles
* Commit with descriptive messages after each logical unit of work
* Push to git when session is complete
* Write a short summary of what was done today to PROGRESS.md

---

## Feature Backlog

Prioritized by value and feasibility:

1. **Unit tests for AgentEngine and WorkerPool** — zero test coverage on the most critical logic; one bad memory leak or race condition can corrupt sessions
2. **PromptQueue / CheckedContinuation timeout** — currently hangs indefinitely; add a 30-second timeout with graceful error
3. **AgentPool memory management** — agents are never removed; implement an LRU eviction policy with a cap of ~20 sessions
4. **SelfHealingLoop project context** — currently doesn't pass the active project to the agent; self-healing builds have no file context
5. **ChatView image picker sheet** — image attachment UI is incomplete; the `.sheet` modifier is missing
6. **ExchangeRateService staleness check** — SEK rate is fetched once and never refreshed; add a 24h expiry
7. **macOS background daemon improvements** — BackgroundDaemon should wake up on iCloud changes, not just on a polling timer
8. **OpenRouter model list refresh** — models are hardcoded; should fetch live from OpenRouter API
9. **VoiceView button spinners** — TTS generation has no loading feedback; add spinner during synthesis
10. **Localization via .xcstrings** — all Swedish strings are hardcoded; migrate to String Catalogs for future localization

---

## Known Issues

| Priority | Issue | Notes |
|----------|-------|-------|
| **Critical** | `isProcessing` flag hangs on Mac Remote path | iOS sends instruction but processing state never resets if Mac doesn't respond |
| **High** | AgentPool agents never evicted | Unbounded memory growth over long sessions |
| **High** | CheckedContinuation hangs without timeout | Can freeze the app indefinitely on slow server responses |
| **High** | No unit tests on agent logic | Any regression in AgentEngine or WorkerPool is invisible until runtime |
| **Medium** | `onChange` deprecated API in multiple views | Causes Xcode warnings throughout; migrate to two-parameter form |
| **Medium** | Duplicated message builder logic across providers | Anthropic, xAI, and OpenRouter each have their own copy; extract shared builder |
| **Medium** | SelfHealingLoop missing project context | Build repair agent works blind; doesn't know what files belong to the project |
| **Medium** | ChatView missing image picker `.sheet` | Image attachment button visible but sheet never presented |
| **Low** | VoiceView buttons lack spinner feedback | No indication that TTS is generating |
| **Low** | ExchangeRateService never refreshes | SEK/USD rate gets stale after first fetch |
