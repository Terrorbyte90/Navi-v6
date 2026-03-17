# Navi Code Agent — Arkitektur & Implementation

> Dokumentation för den server-side autonoma kodagenten som byggdes i mars 2026.
> Agenten kör på Navi Brain-servern och fortsätter arbeta även när iOS-appen stängs.

---

## Varför server-side?

Tidigare körde hela ReAct-loopen lokalt på enheten (iOS/macOS) i `CodeAgent.swift`. Det hade tre problem:

1. **Agenten dog när appen stängdes** — pågående byggen avbröts
2. **Kontextfönstret delades** med UI-tråden och begränsades av enhetens minne
3. **Terminalkomandon** (git, npm, pip, bash) är inte tillgängliga på iOS

Lösningen: flytta all agentlogik till servern. iOS-appen är nu enbart ett display-lager som ansluter via WebSocket.

---

## Systemöversikt

```
iOS App (display)
    │
    │  WebSocket  ws://209.38.98.107:3001/code/ws
    │
    ▼
Navi Brain Server (DigitalOcean, Ubuntu)
    │
    ├── code-agent.js     ← ny modul, autonom ReAct-loop
    ├── server.js         ← Express + WebSocket-server
    └── /root/navi-brain/data/
        ├── code-sessions.json   ← sessioner persisteras
        └── workspaces/<id>/     ← agentens arbetskatalog
```

---

## Filer som skapades / ändrades

### Server

| Fil | Vad som gjordes |
|-----|----------------|
| `navi-brain/code-agent.js` | **Ny.** Hela code agent-modulen (1 170 rader) |
| `navi-brain/server.js` | Lade till `ws`-import, WebSocket-server, `httpServer`, `/code/*`-routes |
| `navi-brain/package.json` | Lade till dependency `"ws": "^8.18.0"` |
| `navi-brain/deploy.sh` | Uppdaterad att kopiera `code-agent.js` och bumpa till v3.4 |

### iOS

| Fil | Vad som gjordes |
|-----|----------------|
| `EonCode/Shared/Services/Code/ServerCodeSession.swift` | **Ny.** iOS WebSocket-klient (587 rader) |
| `EonCode/Shared/Views/Code/CodeView.swift` | **Omskriven.** Premium UI som använder `ServerCodeSession` (914 rader) |

---

## `code-agent.js` — hur agenten fungerar

### WebSocket-protokoll

Klienten ansluter till `ws://server:3001/code/ws?key=<api-key>`.

**Klient → Server:**

| Meddelande | Beskrivning |
|-----------|-------------|
| `{ type: "START", task, model, openrouterKey?, anthropicKey? }` | Skapa ny session, starta agent |
| `{ type: "SUBSCRIBE", sessionId, lastSeq }` | Återanslut till befintlig session. Servern replayer alla events från `lastSeq` |
| `{ type: "SEND", text }` | Skicka nytt meddelande i pågående session |
| `{ type: "STOP" }` | Avbryt agenten |
| `{ type: "PONG" }` | Svar på PING (keepalive) |

**Server → Klient (AG-UI-protokoll):**

| Event | Beskrivning |
|-------|-------------|
| `CONNECTED` | Anslutning bekräftad, returnerar `sessionId` |
| `STATE_SNAPSHOT` | Nuvarande sessionstatus (skickas vid återanslutning) |
| `RUN_STARTED` | Agenten börjar köra |
| `TEXT_DELTA` | En token av text från modellen (streaming) |
| `TEXT_COMMIT` | Ett helt textblock är klart (sparas som meddelande) |
| `TOOL_START` | Agenten börjar köra ett verktyg |
| `TOOL_RESULT` | Verktygsresultat klart (med `isError`, `durationMs`) |
| `PHASE` | Fasbyte — t.ex. `"thinking"`, `"tools"`, `"done"` |
| `TODO` | Agenten uppdaterade sin TODO-lista |
| `GIT_COMMIT` | En commit gjordes (hash, message, filesChanged) |
| `ITERATION` | Agenten är på steg N av max M |
| `RUN_FINISHED` | Uppgiften klar |
| `RUN_ERROR` | Fel uppstod |
| `LINT_WARN` | En fil har syntaxfel efter skrivning |
| `COMPACTING` | Kontext komprimeras |
| `PING` | Keepalive var 20:e sekund |

Varje event har ett `seq`-nummer och `ts`-timestamp. Klienten håller reda på `lastSeq` så att vid återanslutning replays alla missade events.

### ReAct-loopen

```
START
  │
  ▼
[iteration 1..30]
  │
  ├── 1. Anropa LLM (streaming → TEXT_DELTA events)
  │
  ├── 2. Om inga tool calls → TEXT_COMMIT → DONE
  │
  ├── 3. Om tool calls:
  │       └── För varje tool:
  │             TOOL_START → executeTool() → TOOL_RESULT
  │             (lint check om write_file/edit_file)
  │
  ├── 4. Lägg till tool results i konversationshistorik
  │
  ├── 5. Context compaction om > 60 000 tokens
  │
  └── [nästa iteration]
```

### Doom-loop detection

Om agenten anropar exakt samma verktyg tre gånger i rad injiceras ett systemmeddelande som bryter mönstret.

### Context compaction

När konversationshistoriken överstiger ~60 000 tokens:
1. Behåll första 2 och sista 8 meddelanden
2. Summera mitten
3. Emittera `COMPACTING`-event

### Verktyg

| Verktyg | Beskrivning |
|---------|-------------|
| `read_file` | Läs fil med radnummer. Stöder `start_line`/`end_line` för stora filer |
| `write_file` | Skriv fil. Skapar kataloger. Kör lint-check efteråt |
| `edit_file` | Search/replace med fuzzy whitespace-fallback |
| `run_command` | Kör shell-kommando i sessionskatalogens kontext |
| `grep` | Regex-sökning i filer med context-rader |
| `list_files` | Lista katalog, optionellt rekursivt (max djup 3) |
| `todo_write` | Uppdatera TODO-lista → emiterar `TODO`-event till iOS |
| `git_commit` | `git add -A && git commit -m "..."` → emiterar `GIT_COMMIT` |
| `web_search` | DuckDuckGo instant answers |

### Lint guardrails

Efter varje `write_file` och `edit_file` körs:

| Filtyp | Kommando |
|--------|---------|
| `.js`, `.mjs` | `node --check <file>` |
| `.py` | `python3 -m py_compile <file>` |
| `.sh` | `bash -n <file>` |
| `.json` | `node -e "JSON.parse(...)"` |

Om lint misslyckas emiteras ett `LINT_WARN`-event — agenten kan se felet och rätta till det.

### Sessioner

- Varje session har ett unikt UUID
- Persisteras i `/root/navi-brain/data/code-sessions.json` (senaste 40 meddelanden + 200 events)
- Vid serveromstart markeras körande sessioner som `error`
- Arbetskataloger under `/root/navi-brain/data/workspaces/<sessionId>/`

### Modeller

| Nyckel | Modell | Notering |
|--------|--------|---------|
| `minimax` | MiniMax M2.5 via OpenRouter | Standard. 80.2% SWE-bench |
| `qwen` | Qwen3-Coder (free) via OpenRouter | Gratis, kodspecialist |
| `claude` | Claude Sonnet 4.6 via Anthropic | Kräver `anthropicKey` |

---

## `ServerCodeSession.swift` — iOS-klienten

### Anslutningsflöde

```
1. Ny session:
   startNewSession(task:model:)
   → connectAndStart()
   → URLSessionWebSocketTask till ws://server/code/ws?key=...
   → Skickar START-meddelande med task + API-nycklar

2. Återanslutning (app öppnas igen):
   resumeSession(id)
   → connect(sessionId:)
   → Skickar SUBSCRIBE { sessionId, lastSeq }
   → Servern skickar STATE_SNAPSHOT + alla missade events

3. Auto-reconnect vid tapp:
   listenForMessages() får .failure
   → scheduleReconnect() med exponentiell backoff (1s, 2s, 4s... max 30s)
```

### Published-state (driver SwiftUI)

```swift
@Published var connectionState: ServerConnectionState  // disconnected/connecting/connected/reconnecting
@Published var isRunning: Bool
@Published var phase: String
@Published var phaseLabel: String
@Published var streamingText: String       // live text under streaming
@Published var messages: [ServerChatMessage]
@Published var todos: [ServerTodoItem]
@Published var toolEvents: [ServerToolEvent]
@Published var liveToolName: String?
@Published var iteration: Int
@Published var gitCheckpoints: [ServerGitCheckpoint]
```

### Event → State

Events bearbetas i `handleEvent()`:
- `TEXT_DELTA` → ackumuleras i `streamingText` + `accumulatedText`
- `TEXT_COMMIT` → `accumulatedText` töms, sparas som `ServerChatMessage` i `messages`
- `TOOL_START` → läggs till i `toolEvents` och `pendingToolEvents`
- `TOOL_RESULT` → uppdaterar befintlig event med resultat + duration
- `TODO` → uppdaterar `todos`
- `GIT_COMMIT` → skapar `ServerGitCheckpoint`, committas med aktuellt textblock
- `RUN_FINISHED` / `RUN_ERROR` → `isRunning = false`

---

## `CodeView.swift` — premium UI

### Layout

```
┌─────────────────────────────────────────┐
│  Kod  [SERVER ●]    [todo 2/5]  [⊞] [⏹] │  ← topBar
│  ● Thinking…  step 3    write_file       │  ← phaseStrip (synlig under körning)
│  ─────────────────────────────────────── │
│  ○ setup project  ○ write API  ✓ tests   │  ← todoPanelView (kollapsbar)
├─────────────────────────────────────────┤
│                                         │
│  [user bubble]         "Build a..."     │
│                                         │
│  ◉  ┌─ 3 verktyg ────────────────────┐  │
│     │ ✓ read_file  config.js  0.1s  ▼│  │
│     │ ✓ write_file server.js  1.2s  ▼│  │  ← ToolEventsSummary
│     │ ✓ run_command npm install 3s  ▼│  │
│     └───────────────────────────────┘  │
│     Implementation looks good...       │
│     [◈ abc1234 — initial structure]    │  ← GitCheckpointBadge
│                                         │
│  ◉  Writing tests...█                  │  ← ServerStreamingRow (live cursor)
│                                         │
│  ◉  Thinking… ●●●   write_file         │  ← ServerActivityRow
│                                         │
├─────────────────────────────────────────┤
│  [＋]  [ Beskriv ett projekt...   ] [↑] │  ← inputBar
│        Agent kör på Navi Brain · Ansluten│
└─────────────────────────────────────────┘
```

### Nyckelkomponenter

| Komponent | Funktion |
|-----------|---------|
| `serverBadge` | Visar SERVER med grön/orange/grå punkt beroende på anslutningsstatus |
| `phaseStrip` | Spinner + fas-label + steg-räknare + aktivt verktyg under körning |
| `todoPanelView` + `todoPill()` | Horisontellt scrollbar TODO-lista med checkmarks |
| `modelPicker` | MiniMax / Qwen3 / Claude — visar SWE-bench-poäng och kostnad |
| `ServerMessageRow` | Renderar meddelanden: user-bubbla eller assistent med tool-cards + git-badge |
| `ToolEventsSummary` | Kollapsbar pill som visar antal verktyg. Expanderar till `ToolEventRow` |
| `ToolEventRow` | Visar ikon, namn, nyckelparameter, duration. Expanderbar med resultat |
| `GitCheckpointBadge` | Inline commit-badge med hash + message + antal filer |
| `ServerStreamingRow` | Live text med blinkande I-beam-cursor (500ms toggle) |
| `ServerActivityRow` | Animerade punkter under tänkande + aktivt verktyg |

---

## Deploy

### Första gången

```bash
cd navi-brain
bash deploy.sh
```

### Uppdatera servern

```bash
cd navi-brain
bash deploy.sh
```

Skriptet kopierar `server.js`, `code-agent.js`, `telephony.js`, `package.json` → kör `npm install` → startar om via pm2.

### Verifiera

```bash
# Server live?
curl -H 'x-api-key: navi-brain-2026' http://209.38.98.107:3001/

# Sessioner?
curl -H 'x-api-key: navi-brain-2026' http://209.38.98.107:3001/code/sessions

# Loggar
ssh root@209.38.98.107 'pm2 logs navi-brain --lines 50 --nostream'
```

### Miljövariabler på servern (`/root/navi-brain/.env`)

```
PORT=3001
API_KEY=navi-brain-2026
OPENROUTER_KEY=<din openrouter-nyckel>
ANTHROPIC_API_KEY=<din anthropic-nyckel>   ← lägg till för Claude-support
NTFY_TOPIC=navi-brain-prod
```

---

## Säkerhet

- Alla HTTP-endpoints kräver `X-Api-Key`-header
- WebSocket-upgrades verifieras via `?key=`-parameter
- Agentens shell-kommandon körs i sessionens arbetskatalog (`/root/navi-brain/data/workspaces/<id>`)
- API-nycklar skickas från iOS vid sessionsstart och lagras aldrig i persisterat session-state

---

## Kända begränsningar

1. **Anthropic streaming** — Claude-modellen streamer korrekt men Anthropic's API kräver att `anthropic-beta: prompt-caching-2024-07-31` läggs till för att caching ska fungera optimalt på långa sessioner
2. **Workspace isolation** — agenten kan köra kommandon utanför sin arbetskatalog med `run_command`. Om hårdare sandboxing önskas, använd Docker per session
3. **Reconnect och långa sessioner** — events behålls bara de senaste 1 000 i minnet (200 på disk). Mycket långa sessioner kan missa tidig historik vid reconnect
4. **iOS WebSocket + bakgrund** — `URLSessionWebSocketTask` pausas av iOS när appen är i bakgrunden. Agenten fortsätter köra på servern; events replays när appen öppnas igen

---

*Skrivet: 2026-03-17*
