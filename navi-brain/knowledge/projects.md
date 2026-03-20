# NAVI — AKTIVA PROJEKT

## Navi-v6 (huvud-app)
- **Typ:** iOS/macOS AI-assistent (SwiftUI)
- **iOS-källkod:** EonCode/ (iOS/, macOS/, Shared/)
- **Server:** navi-brain/ (Node.js, Express, WebSocket)
- **iCloud:** ~/Library/Mobile Documents/com~apple~CloudDocs/Navi-v6/
- **Server-path:** /root/navi-brain/
- **Server-IP:** 209.38.98.107:3001
- **API-nyckel:** navi-brain-2026
- **PM2-process:** navi-brain

### Nyckelarkitektur iOS
- NaviTheme — designsystem (färger, typsnitt, spacing)
- @StateObject / @Observable — tillståndshantering
- ServerCodeSession.shared — code agent WebSocket-klient
- CodeSessionsStore — pollning av aktiva servrar
- NotificationManager — APNs + ntfy.sh-notiser
- NaviBrainService — general chat med servern

### Nyckelarkitektur Server
- server.js — REST API + WebSocket-server + generell chat
- code-agent.js — autonom ReAct-kodagent (WebSocket streaming)
- apns.js — APNs push-sändare
- data/ — sessioner, tasks, costs (JSON-persistence)
- data/workspaces/ — per-session arbetskataloger

### Kodkonventioner
- Svenska i UI-strängar och kommentarer OK
- NaviTheme.* för alla färger/typsnitt
- Commit-stil: "feat(scope): beskrivning"
- Inga force unwraps, inga placeholder-implementationer
- iOS 17+, Swift 5.9+

## Andra aktiva projekt (GitHub: Terrorbyte90)
- **Lifetoken** — Dystopisk survival-spel (SwiftUI, Time as currency)
- **Lillajag3** — Premium KBT-välmående-app (svenska, SwiftUI)
- **Lunaflix-v2** — Personlig videostreaming (Mux, iOS 26-design)
- **BabyCare** — Babycare-app med graviditetsveckovideor

## Serverinfrastruktur
- **Provider:** DigitalOcean (Amsterdam)
- **OS:** Ubuntu Linux
- **Process manager:** PM2
- **Node.js:** 20+
- **Pakethanterare:** npm, pip3, cargo, apt
- **Internet:** Ja via web_search och fetch_url
- **Git:** Installerat, GitHub-token i miljövariabel
- **Modeller:** MiniMax M2.5, Qwen3-Coder, DeepSeek R1, Claude Sonnet 4.6
