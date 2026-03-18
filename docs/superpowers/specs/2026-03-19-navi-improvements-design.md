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
| `fetch_url` (uppgradering) | Befintligt verktyg uppgraderas: strippar HTML till ren text, hanterar redirects, 30s timeout, retry x2 vid timeout. |
| `memory_write` / `memory_read` | Persistent nyckel-värde-minne per session. Agenten kan spara t.ex. "arkitektur", "kända buggar", "beslut" och läsa tillbaka dem senare i sessionen. |

### 1.2 Specialist sub-agenter på servern

Två interna sub-agenter som MiniMax-huvudagenten kan anropa som verktyg:

**PlannerAgent** (`planner_agent`-verktyg)
- Anropas automatiskt i fas 1 av varje ny uppgift
- Analyserar codebase (läser README, package.json, filstruktur)
- Bryter ner task i konkreta, ordnade steg med riskestimering
- Returnerar strukturerad plan (JSON + markdown) som huvudagenten följer
- Förhindrar agenten från att "dyka rakt in" utan förståelse

**ReviewerAgent** (`reviewer_agent`-verktyg)
- Anropas av MiniMax efter fas 4 (testa/verifiera)
- Kör Claude Sonnet 4.6 (bättre reviewer-kapacitet) på ändrade filer
- Letar efter: säkerhetshål, logikfel, platshållare (`// TODO`, `pass`, stub-funktioner), inkonsistenser med resten av kodebasen
- Returnerar strukturerad feedback; MiniMax kan åtgärda eller motivera avvikelse

### 1.3 System prompt-uppgradering

Nuvarande system prompt är välstrukturerad men saknar:

**Output quality directives:**
- Explicit chain-of-thought-instruktion: tänk steg-för-steg innan kod skrivs
- Self-correction loop: efter varje kodblock, läs det och fråga "Är detta produktionsklar kod?"
- Längd-direktiv: aldrig truncka förklaringar, ge alltid fullständig kontext

**Kommunikationskvalitet (minst ChatGPT-nivå):**
- Svara med precision och djup som en senior ingenjör
- Förklara *varför*, inte bara *vad*
- Strukturera svar med tydliga rubriker och punktlistor
- Undvik generiska formuleringar — var specifik om filnamn, radnummer, exakt felmeddelande

### 1.4 Sessionsförbättringar (iOS)

- **Sessions-search**: sökfält i Code-vyn för att filtrera sessioner på task-text
- **Projekt-gruppering**: sessioner grupperas visuellt per repo/projekt
- **"Återuppta med ny kontext"**: starta ny session som ärver filstruktur + git-state från en tidigare session (skickas som kontext i START-meddelandet)

---

## Sektion 2: Markdown & Textformatering

### 2.1 Problemanalys

Nuvarande `MarkdownTextView` (i `PureChatView.swift`) har tre svagheter:
1. Streaming renderas i chunks, inte smooth token-for-token
2. Kodblock saknar syntax highlighting
3. Typografi är inte på ChatGPT-nivå

### 2.2 Ny arkitektur: `MarkdownRenderer.swift`

Centraliserad fil som ersätter direkt användning av `MarkdownTextView` i `PureChatView`, `ChatView` och `CodeView`. Förhindrar framtida divergens.

**StreamingMarkdownBuffer**
- Håller intern textbuffer, parsar inkrementellt
- Renderar tecken-för-tecken med 0.008s timer-driven animation
- Avbryter animationen direkt vid nytt innehåll (aldrig lagging)
- Historiska meddelanden renderas direkt utan animation

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
- API-nyckel-status med grön/röd indikator per nyckel

---

## Sektion 4: Claude Code Agents

Fyra subagent-filer skapas i `~/.claude/agents/`:

### `navi-server-dev.md`
Expert på `navi-brain/` — Node.js, Express, WebSocket, AG-UI-protokollet, sessions-modellen, code-agent.js arkitekturen. Används för alla server-side ändringar.

### `navi-ios-dev.md`
Expert på Swift/SwiftUI-appen. Känner NaviTheme, befintliga komponenter (`MarkdownTextView`, `GlassCard`, `NaviActivityPill`), och appens arkitektur (AgentPool, ProjectStore, ConversationStore, etc.). Används för alla iOS/macOS-ändringar.

### `navi-ui-reviewer.md`
Granskar SwiftUI-kod mot ChatGPT/premium UI-standard. Kontrollerar: spacing, typografi, animationer, dark mode, accessibility. Dispatcas efter varje UI-ändring.

### `navi-spec-reviewer.md`
Granskar spec-dokument för fullständighet och teknisk korrekthet. Används i spec review-loopen.

---

## Tekniska beroenden och risker

| Risk | Mitigation |
|---|---|
| MiniMax M2.5 kanske inte hanterar `planner_agent`/`reviewer_agent` tool calls optimalt | Testa med enkelt fall först; fallback till inline reasoning om tool calls inte fungerar |
| Smooth streaming-animation kan orsaka performance-problem på äldre enheter | Animation är opt-out via `reduceMotion`; alltid synkron render om `isHistorical == true` |
| Centralisering av MarkdownRenderer kan bryta befintliga vyer | Migrera en vy i taget, testa kompilering efter varje |
| ReviewerAgent (Claude Sonnet) ökar kostnaden per session | Anropas max 1 gång per fas-4, inte per iteration |

---

## Leveransgränser (out of scope)

- Docker per session (sandbox) — för komplex, hanteras separat
- React Native / WebKit-baserad markdown-rendering
- Ny onboarding-flow / App Store-material
- Multi-user / team features
