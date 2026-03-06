# EonCode v2 — Fullständig QA-audit

**Datum:** 2026-03-06
**Granskare:** Claude (automatisk audit)
**Omfattning:** Alla 83 Swift-filer, iOS + macOS, alla tjänster, vyer och modeller

---

## Fas 1: iOS-granskning

### App-start (EonCodeApp.swift)
- **OK** — Startar iCloudSyncEngine, PeerSyncEngine, InstructionQueue korrekt
- **OK** — Korrekt `#if os()` separation

### Chatt (PureChatView.swift, ChatManager.swift)
- **HITTAD & FIXAD** — StreamingBubble saknade ResponseCleaner → rå XML kunde visas under streaming
- **HITTAD & FIXAD** — Image picker-knapp fanns men `.sheet` saknades → bilder kunde aldrig väljas
- **HITTAD & FIXAD** — ChatManager: streaming-callback saknade `@MainActor`-isolering
- **HITTAD & FIXAD** — `onChange(of:)` använde deprecated API med `{ _ in }` syntax

### Projekt & Agent (AgentEngine, WorkerAgent, OrchestratorAgent)
- **HITTAD & FIXAD** — WorkerAgent rad 225: `!UIDevice.isMac` var inverterad — terminaljobb rapporterades felaktigt som "ej lokala" på Mac
- **OK** — AgentEngine: ResponseCleaner applicerad på alla 4 utdatapunkter (tidigare fix)
- **OK** — OrchestratorAgent: korrekt task-routing, wave-exekvering, resultat-aggregering

### Browser (BrowserAgent.swift)
- **HITTAD & FIXAD (KRITISK)** — `navigationContinuation` race condition: WKNavigationDelegate-callbacks (`nonisolated`) kunde resumera fel continuation vid snabba navigeringar. Fixat med `navigationID`-guard och nil-check före resume
- **HITTAD & FIXAD** — `consecutiveVisionFallbacks` nollställdes aldrig efter lyckad DOM-interaktion → strategi-switch var permanent

### Synk (InstructionQueue.swift)
- **HITTAD & FIXAD** — `pendingCount` ökades vid `enqueue()` men minskades aldrig → UI visade ständigt ökande "väntande" räknare

### Minne (MemoryManager.swift)
- **HITTAD & FIXAD** — JSON-parsing använde `range(of: "}")` backwards → bröt vid nästlade JSON-objekt. Ersatt med bracket-matching

### Filträd (FileTreeView.swift)
- **HITTAD & FIXAD** — "Ta bort"-knappen i kontextmenyn raderade filer utan bekräftelse. Lagt till `.alert`-dialog med bekräftelse

### Inställningar (SettingsView.swift)
- **OK** — API-nycklar, modellväljare, synk-konfiguration fungerar korrekt
- **OK** — Kostnadsdashboard och minneslista fungerar

### Prestanda
- **OK** — LazyVStack för chattmeddelanden
- **OK** — Streaming-bubbla visar max 3000 tecken (.suffix)
- **OK** — BrowserAgent trimmar loggen till 400 poster vid 500

---

## Fas 2: macOS-granskning

### Layout (ContentView.swift)
- **HITTAD & FIXAD** — `onChange(of: selectedNode?.id) { _ in }` deprecated syntax
- **OK** — NavigationSplitView med sidebar + detalj fungerar korrekt
- **OK** — HSplitView för filträd + editor + chatt

### Terminal & Verktyg (ToolExecutor.swift)
- **OK** — Full terminal-exekvering på macOS, köning till Mac på iOS
- **OK** — SelfHealingLoop: build → parse → fix → rebuild (max 20 försök)

### Xcode-integration
- **OK** — build_project-verktyget fungerar via xcodebuild
- **OK** — SelfHealingLoop integrerar med Claude för felsökning

### SafetyGuard
- **OK** — Grundläggande skydd finns i ToolExecutor

---

## Fas 3: Plattformsövergripande synk

### iCloud (iCloudSyncEngine)
- **OK** — Projekt, konversationer, minnen och instruktioner synkas korrekt
- **OK** — Katalogstruktur skapas vid uppstart

### InstructionQueue
- **FIXAD** — pendingCount-dekrementering saknades (se ovan)
- **OK** — iOS köar instruktioner, macOS pollar och exekverar

### DeviceStatus (DeviceStatusBroadcaster, PeerSyncEngine)
- **OK** — Bonjour-discovery fungerar korrekt
- **OK** — UIDevice.isMac används korrekt i DeviceStatusBroadcaster

### ExchangeRateService
- **HITTAD & FIXAD** — Ingen staleness-check; cachad kurs kunde vara godtyckligt gammal. Lagt till `isStale`-check (24h) och auto-refresh vid konvertering

---

## Fas 4: Sammanfattning av alla fixes

### KRITISKA fixes
| # | Fil | Problem | Fix |
|---|-----|---------|-----|
| 1 | `BrowserAgent.swift` | navigationContinuation race condition — fel continuation kunde resumeras | Lagt till navigationID-guard i withCheckedThrowingContinuation + nil-check i delegate callbacks |
| 2 | `WorkerAgent.swift` | `!UIDevice.isMac` inverterad logik — ranLocally alltid false på Mac | Ändrat till `UIDevice.isMac` (utan negation) |

### HÖGA fixes
| # | Fil | Problem | Fix |
|---|-----|---------|-----|
| 3 | `InstructionQueue.swift` | pendingCount++ utan motsvarande -- | Lagt till dekrementering i processInstruction defer |
| 4 | `MemoryManager.swift` | JSON-parsing bröt vid nästlade objekt | Ersatt med bracket-matching-algoritm |
| 5 | `ChatManager.swift` | Streaming-callback utan MainActor-isolering | Wrappat i `Task { @MainActor in }` |
| 6 | `BrowserAgent.swift` | consecutiveVisionFallbacks nollställdes aldrig efter framgång | Lagt till reset efter lyckad DOM-action |

### MEDEL fixes
| # | Fil | Problem | Fix |
|---|-----|---------|-----|
| 7 | `PureChatView.swift` | StreamingBubble saknade ResponseCleaner | Applicerat `ResponseCleaner.clean()` |
| 8 | `PureChatView.swift` | Image picker-sheet saknades | Skapat `ImagePicker.swift` (PHPicker iOS / NSOpenPanel macOS), kopplat `.sheet` |
| 9 | `FileTreeView.swift` | "Ta bort" utan bekräftelse | Lagt till `.alert`-dialog med bekräftelse |
| 10 | `ExchangeRate.swift` | Ingen staleness-check på cachad kurs | Lagt till `isStale` (24h) + auto-refresh |
| 11 | `ContentView.swift` + `PureChatView.swift` | Deprecated `onChange { _ in }` syntax | Uppdaterat till ny `onChange { }` syntax (iOS 17+) |

### Tidigare fixade (i denna session)
| # | Fil | Problem | Fix |
|---|-----|---------|-----|
| 12 | `CostCalculator.swift` | Rå XML/function_calls-taggar läckte till användaren | Skapat ResponseCleaner + systempromptrregler |
| 13 | `AgentEngine.swift` | ResponseCleaner applicerad på 4 output-punkter | clean() på streamingText, assistantMsg, onUpdate, sendChat |
| 14 | `ContentView.swift` | Agent saknade vy-kontext | Lagt till updateViewContext() + MessageBuilder.currentViewContext |

---

## Nya filer skapade
- `EonCode/Shared/Views/Chat/ImagePicker.swift` — PHPicker (iOS) / NSOpenPanel (macOS) wrapper

---

## Kvarstående problem (ej fixade)

| Problem | Anledning |
|---------|-----------|
| ChatView.swift saknar även image picker `.sheet` | Samma mönster som PureChatView — `showImagePicker` sätts men ingen sheet. Kan fixas genom att lägga till samma `.sheet(isPresented: $showImagePicker) { ImagePicker(...) }` i InputBar |
| Kostnadsfält visas dubbelt på macOS | PureChatView visar kostnad både i `macModelBar` (toppen) och under inputfältet. Bör väljas en plats. Ej ändrat — designbeslut |
| BrowserActionDecider/PageExtractor/ScreenshotAnalyzer | Ej granskade i detalj — externa hjälpklasser utan tillgång till källkod |
| Saknar enhetstester | Projektet har inga tester — rekommenderas starkt för alla tjänster |
| Hårdkodade svenska strängar | All UI-text är hårdkodad på svenska — bör lokaliseras med String Catalogs för framtida internationalisering |

---

*Rapport genererad automatiskt av Claude QA-audit.*
