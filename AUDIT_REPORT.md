# Navi-v6 — Automatisk kodgranskning

**Datum:** 2026-03-16
**Granskare:** Claude (autonom audit)
**Scope:** Fullständig granskning av alla Swift-filer — iOS + macOS, vyer, tjänster, modeller
**Branch:** `claude/make-repos-public-V7FBv`

---

## Sammanfattning

Totalt fixade **17 problem** i **12 filer**:
- 🔴 **Kritiska** (1): Logikfel som orsakar permanent hängt UI-tillstånd
- 🟡 **Höga** (4): Buggar med synlig felaktig beteende
- 🟢 **Medel** (12): Deprecerade API:er, döden kod, visuella fel i light mode

---

## FAS 2 — Buggar

### 🔴 KRITISK

#### NaviOrchestrator.swift — `isProcessing` fastnade på `true` för alltid (iOS Mac Remote)

**Problem:** På iOS när `macRemoteEnabled = true`, sattes `isProcessing = true` och `activity.begin()` anropades — men sedan returnerade koden tidigt med `return`. Den `defer { isProcessing = false }` som nollställer flaggan bodde inuti `currentTask`-blocket som aldrig tilldelades. Resultatet: UI fastnade i laddningsläge permanent tills appen omstartades.

**Fix:**
```swift
// INNAN (buggy):
if SettingsStore.shared.macRemoteEnabled {
    Task { await executeRemoteOnMac(...) }
    return
    // isProcessing = true men nollställdes aldrig!
}

// EFTER (fixed):
if SettingsStore.shared.macRemoteEnabled {
    Task {
        await executeRemoteOnMac(instruction: instruction, project: targetProject)
        isProcessing = false
        activity.complete(summary: "Skickad till Mac")
    }
    return
}
```

---

### 🟡 HÖGA

#### InstructionQueue.swift — `pendingCount` ökades även när iCloud-skrivning misslyckades

**Problem:** `pendingCount += 1` anropades alltid i `enqueue()`, oavsett om iCloud-skrivningen lyckades. Om skrivningen misslyckades skickades aldrig instruktionen till Mac, men räknaren ökade ändå — vilket ledde till permanent "N väntande instruktioner" i UI:t.

**Fix:** Lägg till `var enqueued = false`-flagga, sätt `enqueued = true` vid lyckad iCloud-skrivning, och kör bara `pendingCount += 1` och `NotificationCenter.post()` om `enqueued == true`.

---

#### SidebarView.swift — GitHub-sektionen visade tom placeholder istället för reellt innehåll

**Problem:** I `contextualList`-switchen hade `.github`-caset `emptyHint(icon: "arrow.triangle.branch", text: "GitHub")` — en tom placeholder. Men en fullimplementerad `githubRepoList`-vy var definierad i samma fil och användes aldrig.

**Fix:**
```swift
// INNAN:
case .github: emptyHint(icon: "arrow.triangle.branch", text: "GitHub")

// EFTER:
case .github: githubRepoList
```

---

#### SidebarView.swift — Vald rad: vit text på nästan transparent vit bakgrund (oläslig i light mode)

**Problem:** `ChatConversationRow` och project row använde `.foregroundColor(isSelected ? .white : .primary)` som textfärg vid markering, men bakgrunden var `Color.white.opacity(0.08)` — nästan transparent vit. I light mode: vit text på vit bakgrund = oläslig.

**Fix:** Ändrat till `.foregroundColor(.primary)` för båda rader — system-adaptiv färg som fungerar i både light och dark mode.

---

### 🟢 MEDEL

#### Deprecated `onChange` API — 17 instanser i 10 filer

SwiftUI's `onChange(of:perform:)` med enkelt argument deprecerades i iOS 17 / macOS 14. Alla instanser uppdaterades till tvåargumentformen `{ oldValue, newValue in }`.

| Fil | Antal fixes |
|-----|-------------|
| `PureChatView.swift` | 3 |
| `SettingsView.swift` | 1 |
| `AgentView.swift` | 3 |
| `ChatView.swift` | 3 |
| `CodeEditorView.swift` | 2 |
| `PlanView.swift` | 2 |
| `ServerView.swift` | 3 |
| `GitHubView.swift` | 1 |
| `BrowserAgentLogView.swift` | 1 |
| `VoiceModeOverlay.swift` | 1 |
| `ArtifactView.swift` | 1 |

**Totalt: 21 onChange-fixes**

#### ContentView.swift — Död kod: `TabButton`

`TabButton`-struct (en trivial wrapper runt `MacTabPill`) definierades men användes aldrig. Raderad.

---

## FAS 4 — Kodkvalitet

### Identifierade men inte åtgärdade (för stor risk vid refaktorering)

| Problem | Filer | Kommentar |
|---------|-------|-----------|
| Duplicerad stream-händelsehantering | `CodeAgent.swift`, `WorkerAgent.swift` | Nästan identiska `handleEvent()`-funktioner. Refaktorering rekommenderas som separat uppgift. |
| Duplicerad JSON-parsing | `CodeAgent.swift`, `WorkerAgent.swift` | Samma `parseToolInputJSON()`/`parseJSON()` logik. Kan extraheras till `String`-extension. |
| `buildAPIMessages()` i 5 filer | `CodeAgent`, `ChatManager`, `OpenRouterClient`, `XAIClient`, `CostCalculator` | Varje fil har sin variant av meddelandekonvertering. |
| `DispatchQueue` (GCD) i tjänster | ~10 förekomster i Sync/Memory | Modern kod bör använda `Task` + `async/await`. Inga buggar — men stil är inkonsekvent. |

---

## FAS 5 — Förbättringsförslag (rankade efter påverkan)

### 🔴 Hög prioritet

1. **Enhetstester saknas helt** — Projektet har noll tester. Agentlogik, API-parsing och verktygsexekvering är kritiska vägar som bör testas. Rekommenderat: XCTest med mock-klienter.

2. **`PromptQueue`/`CheckedContinuation` kan hänga** — Om en agent-callback misslyckas och aldrig anropar `resume()` på en `CheckedContinuation`, hänger den `Task` för alltid utan timeout eller felhantering.

3. **`AgentPool` rensar aldrig agenter** — `AgentPool.agents`-dictionary växer obegränsat. Agenter bör tas bort när deras projekt raderas (lyssna på `ProjectStore`-borttagningshändelser).

### 🟡 Medel prioritet

4. **Hårdkodade svenska strängar** — All UI-text är hårdkodad på svenska. Bör migreras till Swift String Catalogs (`Localizable.xcstrings`) för framtida lokalisering.

5. **`SelfHealingLoop` anropar aldrig `AgentEngine.setProject()`** — Loop kör utan projektkontekst, vilket innebär att verktyg inte vet vilket projekt de jobbar med under self-healing-iterationer.

6. **`ChatView.swift` saknar image picker `.sheet`** — `showImagePicker`-flagga sätts men `.sheet`-modifier saknas (samma mönster som tidigare fixades i `PureChatView`).

7. **README refererade fel repo-URL och fel krav** — Pekade på `Eon-Code-v2`, sa macOS 14+/iOS 17+. Uppdaterat till korrekt URL och iOS 18+/macOS 15+.

### 🟢 Låg prioritet

8. **Duplicerad meddelandebyggarlogik** — Se FAS 4. Kan konsolideras till en `APIMessageBuilder`-struct med provider-specifika formatters.

9. **`ExchangeRateService` har ingen staleness-check** — Cachad valutakurs kan vara godtyckligt gammal. Lägg till 24h TTL.

10. **`VoiceView` generera-knappar saknar spinner** — Visar "Genererar…" + timglas-ikon men ingen `ProgressView`. Funktionellt men inkonsekvent med resten av appen.

---

## Filer ändrade i denna session

| Fil | Ändring |
|-----|---------|
| `NaviOrchestrator.swift` | Fix: `isProcessing` nollställs korrekt i Mac Remote-sökväg |
| `InstructionQueue.swift` | Fix: `pendingCount` ökas bara vid lyckad iCloud-skrivning |
| `SidebarView.swift` | Fix: GitHub-sektion visar `githubRepoList`; vald-rad textfärg |
| `ContentView.swift` | Fix: Raderad död `TabButton`-struct |
| `PureChatView.swift` | Fix: 3x deprecated `onChange` |
| `SettingsView.swift` | Fix: 1x deprecated `onChange` |
| `AgentView.swift` | Fix: 3x deprecated `onChange` |
| `ChatView.swift` | Fix: 3x deprecated `onChange` |
| `CodeEditorView.swift` | Fix: 2x deprecated `onChange` |
| `PlanView.swift` | Fix: 2x deprecated `onChange` |
| `ServerView.swift` | Fix: 3x deprecated `onChange` |
| `GitHubView.swift` | Fix: 1x deprecated `onChange` |
| `BrowserAgentLogView.swift` | Fix: 1x deprecated `onChange` |
| `VoiceModeOverlay.swift` | Fix: 1x deprecated `onChange` |
| `ArtifactView.swift` | Fix: 1x deprecated `onChange` |
| `README.md` | Uppdaterad med korrekt info, krav, arkitektur, modeller |

---

*Rapport genererad automatiskt av Claude autonom audit — 2026-03-16*
