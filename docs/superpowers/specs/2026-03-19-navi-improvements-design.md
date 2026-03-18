# Navi-v6 — Förbättringsspec
**Datum:** 2026-03-19
**Branch:** dev/next-200-changes
**Scope:** Code Agent (server), Markdown/Text, App UI, Claude Code Agents

---

## Bakgrund

Navi-v6 är en iOS/macOS AI-assistent med en server-side autonom kodagent (`code-agent.js`) som körs på DigitalOcean. Appen har tre primära förbättringsområden identifierade:

1. Code Agent saknar verktyg, har suboptimal kodkvalitet och sessionshantering
2. Markdown-renderingen är funktionell men inte på ChatGPT-nivå
3. App-UI:t har polish-brister i chat-bubblor, code-vyn och navigation

Standard-modell för agenten är **MiniMax M2.5** (kostnadsskäl, 80.2% SWE-bench).

---

## Sektion 1: Code Agent (server-side)

### 1.1 Nya verktyg

Fem nya verktyg läggs till i `code-agent.js`:

| Verktyg | Beskrivning |
|---|---|
| `run_tests` | Kör testsvit automatiskt baserat på projekt-typ (`npm test`, `pytest`, `go test ./...`, `swift test`). Returnerar strukturerat resultat: pass-count, fail-count, felmeddelanden. |
| `install_package` | Isolerad paketinstallation: `npm install <pkg>`, `pip install <pkg>`, `cargo add <crate>`. Loggas separat från `run_command`. |
| `diff_file` | Returnerar `git diff HEAD -- <file>` för en specifik fil. Agenten kan granska sina egna ändringar innan commit. |
| `fetch_url` (uppgradering) | Nuvarande implementation har: 15s timeout, max 3 redirects, HTML strippas redan (script/style-taggar + alla HTML-taggar). **Delta som implementeras:** höj timeout till 30s, höj max redirects till 5, lägg till retry ×2 **enbart vid timeout** (ej vid HTTP 4xx/5xx). Befintlig HTML-strippning rörs ej. |
| `memory_write` / `memory_read` | Nyckel-värde-minne per session. **Schemas:** `memory_write: { key: string (required), value: string (required) }` — returnerar `"saved"`. `memory_read: { key: string (required) }` — returnerar värdet eller `"(not found)"` om nyckeln saknas. **Implementation:** Lägg till `this.memory = data.memory \|\| {}` i `CodeSession`-konstruktorn, inkludera `memory` i `toJSON()` och återställ i `fromJSON()` så att minnet överlever serveromstarter. |

### 1.2 Specialist sub-agenter på servern

Två interna sub-agenter som MiniMax-huvudagenten kan anropa som verktyg. Båda är **synkrona blocking tool calls** — verktyget returnerar inte förrän sub-agentens LLM-anrop är klart.

**PlannerAgent** (`planner_agent`-verktyg)
- Modell: MiniMax M2.5 via OpenRouter (samma nyckel som huvudagenten, max 4 000 output-tokens)
- **Trigger:** Anropas **exakt en gång per session**, styrt av `iter === 0` (inte av PHASE). Implementeras som en explicit `if (iter === 0)` check **innan** det första LLM-anropet i run-loopen — inte via tool call från modellen. PHASE är alltid `"thinking"` vid iter 0 vilket är korrekt, men triggern är koden, inte PHASE.
- Analyserar codebase (läser README, package.json, filstruktur via befintliga verktyg internt)
- Bryter ner task i konkreta, ordnade steg med riskestimering
- Returnerar strukturerad plan (markdown) som läggs in som ett `system`-meddelande i sessionens konversationshistorik
- **Fallback:** Om anropet misslyckas (nätverksfel, timeout) fortsätter huvudagenten utan plan — loggat som `{ type: "INFO", message: "planner_agent failed, proceeding without plan" }`

**ReviewerAgent** (`reviewer_agent`-verktyg)
- Modell: Claude Sonnet 4.6 via Anthropic API (kräver `anthropicKey` i sessionen)
- **Trigger:** Anropas **max 1 gång per session** (`session.reviewerHasRun = false` flagg på session-objektet). Triggas i `executeTool()`, **efter** att `run_tests` returnerat och `failCount === 0`, innan tool-resultatet läggs tillbaka i konversationshistoriken. Implementeras som: `if (name === 'run_tests' && result.failCount === 0 && !session.reviewerHasRun) { session.reviewerHasRun = true; await runReviewerAgent(session); }`. `session.reviewerHasRun` läggs till på `CodeSession` (persisteras ej — nollställs vid sessionsstart).
- **Ny PHASE:** Emittera `PHASE: "reviewing"` när ReviewerAgent startar — ny fas som läggs till i AG-UI-protokollet och i iOS-`phaseLabel`-mappningen.
- Läser filer som ändrats sedan senaste `git_commit` via `git diff HEAD --name-only`
- Max 8 000 output-tokens
- Letar efter: säkerhetshål, logikfel, platshållare (`// TODO`, `pass`, stub-funktioner), inkonsistenser
- Returnerar strukturerad feedback som läggs till i konversationshistoriken; MiniMax itererar vid behov
- **Fallback:** Om `anthropicKey` saknas i sessionen — hoppa över tyst, ingen error

### 1.3 System prompt-uppgradering

Nuvarande system prompt är välstrukturerad men saknar:

**Output quality directives:**
- Explicit chain-of-thought-instruktion: tänk steg-för-steg **i text** innan kod skrivs — skriv ut resonemanget som del av svaret
- Self-correction loop: efter varje kodblock, explicit instruktion att läsa det och fråga "Är detta produktionsklar kod? Finns det edge cases jag missade?"
- Längd-direktiv: aldrig truncka förklaringar, ge alltid fullständig kontext, inga ellipser (`...`) i kod

**Kommunikationskvalitet (minst ChatGPT-nivå, helst bättre):**
- Svara med precision och djup som ett senior-ingenjörsteam
- Förklara *varför*, inte bara *vad* — motivera varje arkitekturellt val
- Strukturera svar med tydliga rubriker och punktlistor
- Var specifik: ange filnamn, radnummer, exakt felmeddelande — aldrig generiska formuleringar
- Skriv som om du dokumenterar för en kollega som ska ta över projektet

### 1.4 Sessionsförbättringar (iOS)

- **Sessions-search:** sökfält i Code-vyn för att filtrera sessioner på task-text
- **Projekt-gruppering:** sessioner grupperas visuellt per repo/projekt (baserat på `workDir`-basename)
- **"Återuppta med ny kontext":** starta ny session som ärver kontext från en tidigare session

  **Ny REST endpoint på servern** (läggs till i `server.js`, kräver `X-Api-Key`-header):
  ```
  GET /code/sessions/:id/snapshot
  Response: {
    "fileTree": "<output från find . -type f | head -100>",
    "gitLog": "<output från git log --oneline -10>",
    "gitStatus": "<output från git status>"
  }
  ```
  Servern kör dessa kommandon live mot sessionens `workDir`. Returnerar 404 om session inte finns, 400 om `workDir` inte existerar.

  **iOS-flöde:** Vid "Återuppta"-action hämtar iOS `/code/sessions/:id/snapshot` och lägger resultatet i START-meddelandets `contextSnapshot`. Fallback (om endpoint ej svarar): skicka START utan `contextSnapshot`.

  **Utökat START-meddelande:**
  ```json
  {
    "type": "START",
    "task": "...",
    "model": "minimax",
    "inheritSessionId": "<uuid>",
    "contextSnapshot": {
      "fileTree": "...",
      "gitLog": "...",
      "gitStatus": "..."
    }
  }
  ```
  Servern lägger `contextSnapshot` som ett system-meddelande i starten av den nya sessionens konversationshistorik om det finns. `inheritSessionId` lagras på den nya sessionen som `session.parentSessionId` (sträng, persisteras i JSON) för linjespårning — ingen annan serverlogik triggas av det.

---

## Sektion 2: Markdown & Textformatering

### 2.1 Problemanalys

Nuvarande `MarkdownTextView` och `MarkdownCodeBlock` (definierade i `PureChatView.swift`, raderna 804 resp. 1239) används i `PureChatView`, `ChatView`, `CodeView`, och `ServerView`. Tre svagheter:
1. Streaming renderas i chunks, inte smooth token-for-token
2. Kodblock saknar syntax highlighting
3. Typografi är inte på ChatGPT-nivå

### 2.2 Ny arkitektur: `MarkdownRenderer.swift`

**Ny centraliserad fil** som innehåller: `MarkdownTextView`, `MarkdownCodeBlock`, `SyntaxHighlighter`, och `StreamingMarkdownBuffer`. Hela den gamla `MarkdownTextView`+`MarkdownCodeBlock` i `PureChatView.swift` tas bort och ersätts med import från `MarkdownRenderer.swift`.

**Migrationsordning (kompilera efter varje steg):**
1. Skapa `MarkdownRenderer.swift` med all ny implementation
2. Migrera `PureChatView.swift` — ta bort gammal `MarkdownTextView` + `MarkdownCodeBlock`
3. Migrera `ChatView.swift`
4. Migrera `CodeView.swift`
5. Migrera `ServerView.swift`

**StreamingMarkdownBuffer — integration med SwiftUI**

```swift
@MainActor
class StreamingMarkdownBuffer: ObservableObject {
    @Published private(set) var displayText: String = ""
    private var targetText: String = ""
    private var timer: Timer?

    func update(text: String, animated: Bool) {
        // animated=false för historiska meddelanden — synkron render, ingen timer
        if !animated {
            self.displayText = text
            return
        }
        self.targetText = text
        if timer == nil { startTimer() }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { [weak self] _ in
            // Timer fires on main run loop (Timer.scheduledTimer default).
            // Since class is @MainActor, access is safe — use MainActor.assumeIsolated
            // to satisfy strict concurrency without a Task hop.
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.displayText.count < self.targetText.count {
                    let nextIdx = self.targetText.index(self.targetText.startIndex, offsetBy: self.displayText.count + 1)
                    self.displayText = String(self.targetText[..<nextIdx])
                } else {
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }
        }
    }
}
```

`MarkdownTextView` tar en `isStreaming: Bool`-parameter. När `isStreaming: true`, skapar den en intern `@StateObject StreamingMarkdownBuffer` och anropar `buffer.update(text:, animated: true)`. När `isStreaming: false`, anropar den `buffer.update(text:, animated: false)`.

**SyntaxHighlighter**
- Stödda språk: Swift, JavaScript/TypeScript, Python, Bash, JSON, YAML, Markdown
- Färgschema: ChatGPT-inspirerat mörkt (`#1e1e2e` bakgrund, token-baserade färger)
- Kopiera-knapp uppe till höger (haptic feedback på iOS)
- Språk-label (t.ex. "swift", "python") uppe till vänster
- Radnummer för kodblock > 10 rader

### 2.3 Typografispec

| Element | Spec |
|---|---|
| Brödtext | SF Pro Text 16pt, lineHeight 1.6, letterSpacing -0.1 |
| H1 | SF Pro Display 22pt bold, 24pt top margin |
| H2 | SF Pro Display 19pt semibold, 16pt top margin |
| H3 | SF Pro Text 16pt semibold, 12pt top margin |
| Listor | 8pt item-spacing, 16pt left indent, custom bullet `·` |
| Inline-kod | SF Mono 14.5pt, `#2a2a3a` bakgrund, 4pt horiz padding, 2pt border-radius |
| Blockquote | 3pt left border (accent-color), 12pt left padding, italic, 80% opacity |
| Tabeller | Full-width, alternating row colors, rounded corners, bold header |

---

## Sektion 3: App UI

### 3.1 Chat-bubblor

**Assistant-meddelanden**
- Tar bort bubbla-form (som ChatGPT): full-width, vänsterjusterad text mot bakgrunden
- Avatar (Navi-ikon, 28pt) uppe till vänster
- Text börjar vid 44pt från vänsterkant
- 24pt spacing mellan meddelanden + subtil divider

**User-meddelanden**
- Behåller bubbla, uppgraderad: `#1c1c2e` bakgrund, 16pt corner radius, max 85% bredd
- SF Pro 16pt text
- Tid visas on-tap (fade-in under bubblan)

**Streaming-cursor**
- Ersätter blinkande I-beam med 6×14pt vertikal bar i accent-färg
- Fade in/out 600ms (ChatGPT-känsla)
- Försvinner utan animation när streaming slutar

### 3.2 Code-vyn

**Tool cards (komprimering)**
- Standard: en pill per tool (`✓ write_file server.js · 1.2s`)
- Tap expanderar till full output
- Stack > 3 pills kollapsas till `N verktyg` pill

**Progress-strip**
- Nuvarande `phaseStrip` ersätts med 3pt progressbar högst upp i vyn
- Fylls baserat på `iteration / maxIteration`
- Fas-label + steg-räknare flyttas till topBar
- Ny fas `"reviewing"` mappas till label "Granskar kod..."

**Git checkpoint**
- Tap expanderar till syntax-highlightat diff (grön/röd rad-markup, GitHub-stil)

### 3.3 Navigation

**iOS sidebar**
- "Senaste sessioner" direkt i sidebaren — de 5 senaste code-sessionerna med status-dot (grön = klar, grå = avslutad, orange = körande)

**Tomma tillstånd**
- Inget projekt valt: centrerad Navi-logotyp + tre förslag-chips som pre-fyller input
- Exempel: "Bygg en webbapp", "Debugga min kod", "Förklara en codebase"

**Settings**
- Modell-selector per vy (Chat vs Code, separata val)
- Kostnadsdashboard: total kostnad denna månad i SEK

  **Implementation:** `CostTracker.record()` är i nuläget en no-op (disabled). Som del av detta arbete:
  1. Aktivera `record()` igen
  2. Lägg till `monthlyUSD: Double = 0` och `monthlyResetDate: Date = Date()` på `CostTracker`
  3. I `record()`, kontrollera om `Calendar.current.isDate(monthlyResetDate, equalTo: Date(), toGranularity: .month)` — om ej, nollställ `monthlyUSD` och uppdatera `monthlyResetDate`
  4. Kostnader från Code Agent-sessioner (OpenRouter) spåras **via ett nytt `usage`-fält i `RUN_FINISHED`-eventet** på servern: `{ type: "RUN_FINISHED", usage: { inputTokens: N, outputTokens: N, model: "minimax" } }`. Servern summerar token-count från alla LLM-anrop i sessionen. iOS läser detta i `handleEvent()` och anropar en ny `CostCalculator.calculateOpenRouter(inputTokens:outputTokens:model:)` — separat från den befintliga Anthropic-specifika `calculate(usage:model:)` metoden. OpenRouter-priser för MiniMax M2.5 läggs till som konstanter i `CostCalculator`.

- API-nyckel-status med grön/röd indikator per nyckel

---

## Sektion 4: Claude Code Agents

Fyra subagent-filer skapas i `~/.claude/agents/` (lokalt på utvecklarens maskin, **ej committade till repot**). Format: markdown med YAML front matter.

### `navi-server-dev.md`
```markdown
---
name: navi-server-dev
description: Expert on Navi-v6 server-side code (navi-brain/). Use for all changes to code-agent.js, server.js, WebSocket protocol, session management, and AG-UI events.
model: claude-sonnet-4-6
---

You are an expert on the Navi Brain server — a Node.js/Express/WebSocket server running on DigitalOcean Ubuntu.

Key files:
- navi-brain/code-agent.js — autonomous ReAct loop (~1582 lines)
- navi-brain/server.js — Express + WebSocket server, AG-UI protocol
- navi-brain/package.json — dependencies (ws, uuid, express, dotenv)

AG-UI protocol events (server → client): CONNECTED, STATE_SNAPSHOT, RUN_STARTED, TEXT_DELTA, TEXT_COMMIT, TOOL_START, TOOL_RESULT, PHASE, TODO, GIT_COMMIT, ITERATION, RUN_FINISHED, RUN_ERROR, LINT_WARN, COMPACTING, PING.
New phase added in this spec: "reviewing" (emitted when ReviewerAgent runs).

Session model: CodeSession class, persists to /root/navi-brain/data/code-sessions.json via save(). Fields: id, task, model, status, messages[], events[], memory{} (new), workDir.

Models: minimax (MiniMax M2.5, default), qwen (Qwen3-Coder free), deepseek, claude (Sonnet 4.6).

Always verify with 'node --check navi-brain/code-agent.js' before declaring changes done.
```

### `navi-ios-dev.md`
```markdown
---
name: navi-ios-dev
description: Expert on Navi-v6 iOS/macOS SwiftUI app. Use for all Swift/SwiftUI changes — views, services, models.
model: claude-sonnet-4-6
---

You are an expert on the Navi-v6 iOS/macOS SwiftUI app (EonCode/ directory).

Architecture:
- AgentPool.shared — manages ProjectAgent instances
- ProjectStore.shared, SettingsStore.shared, ConversationStore
- NaviOrchestrator — coordinates active view and project

Key components:
- MarkdownRenderer.swift — centralized markdown: MarkdownTextView, MarkdownCodeBlock, SyntaxHighlighter, StreamingMarkdownBuffer
- GlassCard, NaviActivityPill, PremiumComponents — shared UI components
- NaviTheme — colors (.accentNavi, .surfaceNavi, etc.), fonts (bodyFont, monoFont)
- ServerCodeSession — WebSocket client for code agent (@Published state drives SwiftUI)
- CostTracker.swift, CostCalculator.swift, ExchangeRate.swift — cost tracking

Views: PureChatView (main chat), CodeView (code agent UI), ChatView (project chat), ContentView (root), ServerView.

iOS-specific: ChatHistorySidebar, InstructionComposer, LocalAgentEngine.
macOS-specific: BackgroundDaemon, FileSystemAgent, TerminalExecutor, XcodeBuildManager, XcodeCrashHandler.

Always verify compilation after changes.
```

### `navi-ui-reviewer.md`
```markdown
---
name: navi-ui-reviewer
description: Reviews SwiftUI code against ChatGPT/premium UI standards. Dispatch after any UI change to verify spacing, typography, animations, and dark mode.
model: claude-sonnet-4-6
---

You are a premium UI/UX reviewer for SwiftUI. Your standard is ChatGPT or better.

Review checklist:
- Spacing: consistent 8pt grid, no magic numbers
- Typography: follows NaviTheme, correct font weights and sizes per spec (brödtext SF Pro 16pt lineHeight 1.6, H1 22pt bold, etc.)
- Colors: uses NaviTheme colors, works in dark mode
- Animations: smooth, uses SwiftUI standard durations (0.2–0.4s), respects reduceMotion
- Accessibility: minimum 44pt tap targets, VoiceOver labels on interactive elements
- Performance: no unnecessary redraws, LazyVStack/LazyHStack for long lists
- Streaming: cursor visible and smooth, no layout jumps during text animation

Return a bullet list of issues found, or "APPROVED" if everything meets standard.
```

### `navi-spec-reviewer.md`
```markdown
---
name: navi-spec-reviewer
description: Reviews spec documents for completeness, technical correctness, and actionability. Dispatch after writing any spec before implementation begins.
model: claude-sonnet-4-6
---

You are a technical spec reviewer. Your job is to catch gaps before implementation begins.

For each spec, check:
1. Are all features defined with enough detail to implement without asking questions?
2. Are there contradictions or ambiguities?
3. Are there missing technical details that would block implementation?
4. Are risks and mitigations realistic given the tech stack?
5. Is anything out of scope or technically infeasible?
6. Does the spec reference existing code correctly (filenames, function names, line numbers)?

Return either "APPROVED" with a brief summary, or "ISSUES FOUND" with a concrete numbered list.
```

---

## Tekniska beroenden och risker

| Risk | Mitigation |
|---|---|
| MiniMax M2.5 hanterar inte `planner_agent`/`reviewer_agent` tool calls optimalt | Testa med enkelt fall först; fallback: huvudagenten fortsätter utan planering/review |
| ReviewerAgent (Claude Sonnet) kräver Anthropic API-nyckel | Om nyckel saknas hoppar agenten tyst över — ingen error, loggat som INFO |
| Smooth streaming-animation orsakar performance-problem | Timer opt-out via `reduceMotion`; `isStreaming: false` renderar alltid synkront |
| Centralisering av MarkdownRenderer bryter befintliga vyer | Migrera en vy i taget, kompilera efter varje |
| `CostTracker.record()` är disabled — kräver återaktivering | Explicit del av spec (sektion 3.3), inkl. OpenRouter-kostnader via ServerCodeSession |
| iOS WebSocket pausas i bakgrunden | Befintlig reconnect-logik med exponentiell backoff hanterar detta |
| `/code/sessions/:id/snapshot` endpoint misslyckas | iOS skickar START utan contextSnapshot — graceful degradation |

---

## Leveransgränser (out of scope)

- Docker per session (sandbox) — hanteras separat
- React Native / WebKit-baserad markdown-rendering
- Ny onboarding-flow / App Store-material
- Multi-user / team features
