# Navi

> AI-driven kodningsagent och utvecklingsmiljö för iOS + macOS

Navi ersätter Claude Code CLI + Cursor + GitHub med en enhetlig app som körs på iPhone och Mac med delad kodbas. Koda på iPhone, kör på Mac — sömlöst via iCloud.

---

## Krav

- **iOS 18.0+** / **macOS 15.0+**
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Minst en API-nyckel: Anthropic, xAI eller OpenRouter

## Installation

```bash
git clone https://github.com/Terrorbyte90/Navi-v6.git
cd Navi-v6
chmod +x generate-xcode.sh
./generate-xcode.sh
open EonCode.xcodeproj
```

Manuellt utan script:
```bash
brew install xcodegen
xcodegen generate --spec project.yml
open EonCode.xcodeproj
```

### Signing & Capabilities
1. Välj target `EonCode-iOS` → Signing & Capabilities → lägg till ditt Team ID
2. Aktivera: **iCloud** (CloudKit + iCloud Drive), **Keychain Sharing**
3. Upprepa för `EonCode-macOS`

### API-nycklar
Starta appen → Inställningar → API-nycklar

---

## Arkitektur

```
EonCode/
├── Shared/                   # Delad kod (iOS + macOS)
│   ├── Models/               # Datamodeller (NaviProject, ChatConversation, etc.)
│   ├── Services/
│   │   ├── Agent/            # NaviOrchestrator, AgentEngine, WorkerPool
│   │   ├── ClaudeAPI/        # Anthropic streaming-klient
│   │   ├── XAI/              # xAI/Grok API (OpenAI-kompatibelt format)
│   │   ├── OpenRouter/       # OpenRouter API (MiniMax, Kimi, Qwen)
│   │   ├── Sync/             # iCloud + Bonjour + lokal HTTP (3 redundanta kanaler)
│   │   ├── Chat/             # ChatManager, MessageBuilder, ModelRouter
│   │   ├── Memory/           # Minnessystem med AI-profilering
│   │   ├── Versioning/       # Automatiska projektsnapshots
│   │   ├── GitHub/           # GitHub API-integration
│   │   ├── Voice/            # ElevenLabs TTS + röstdesign
│   │   └── Keychain/         # Krypterad API-nyckellagring
│   ├── Views/                # SwiftUI-vyer
│   └── Utilities/            # Teman, konstanter, extensions
├── macOS/
│   ├── Terminal/             # Shell-exekvering (Process)
│   ├── Xcode/                # xcodebuild-integration + SelfHealingLoop
│   ├── FileSystem/           # Filhantering
│   └── Background/           # BackgroundDaemon (alltid på, pollar iCloud)
├── iOS/
│   └── InstructionComposer   # iOS → Mac kommandokö via iCloud
└── navi-brain/               # Node.js backend (Express, PM2) för server-LLM
```

## Agent-pipeline

```
Användare → NaviOrchestrator
              ├── createPlan()       (Haiku — billig planering)
              └── AgentEngine.run()
                    ├── WorkerPool (rate-limitad parallell exekvering)
                    │     └── WorkerAgent (ReAct-loop: Tänk → Verktyg → Resultat)
                    └── ToolExecutor
                          ├── read_file / write_file / move_file
                          ├── run_command (macOS) / build_project
                          ├── search_files / list_directory
                          └── get_api_key (Keychain)
```

## Synkronisering (3 redundanta kanaler)

| Prioritet | Metod | Beskrivning |
|-----------|-------|-------------|
| 1 | **iCloud Drive** | Primär, alltid aktiv, fungerar offline |
| 2 | **Bonjour/P2P** | Lokal WiFi, snabbt, ingen server |
| 3 | **Lokal HTTP** | REST-server på port 52731, iOS ansluter via IP |

## Modeller

### Anthropic
| Modell | Input | Output | Användning |
|--------|-------|--------|------------|
| Claude Haiku 4.5 | $1/MTok | $5/MTok | Planering, snabba svar |
| Claude Sonnet 4.5 | $3/MTok | $15/MTok | Standardkodning |
| Claude Sonnet 4.6 | $3/MTok | $15/MTok | Senaste Sonnet |
| Claude Opus 4.6 | $15/MTok | $75/MTok | Komplexa uppgifter |

### xAI / Grok
| Modell | Notat |
|--------|-------|
| Grok 3 | xAI:s flaggskeppsmodell |
| Grok 3 Mini | Snabb och kostnadseffektiv |

### OpenRouter
| Modell | Notat |
|--------|-------|
| MiniMax M2.5 | Snabb, lång kontextfönster |
| Kimi K2.5 | Kinesisk LLM via OpenRouter |
| Qwen3-Coder | Kodspecialiserad, 15s timeout + fallback |

## Funktioner

- **Multi-provider AI** — Anthropic, xAI/Grok och OpenRouter i en app
- **Autonom agent-motor** — Läs/skriv filer, kör terminal, bygg Xcode-projekt
- **Self-healing builds** — Bygg → fel → fixa → bygg (upp till 20 iterationer)
- **iOS → Mac-kö** — Koda på iPhone, exekvera på Mac via iCloud
- **Projektsnapshots** — Automatiska versioner vid varje agentändring
- **GitHub-integration** — Repos, branches, commits, PRs via GitHub API
- **Navi Brain** — Node.js-backend på din server för MiniMax/Qwen direkt
- **ElevenLabs TTS** — Uppläsning, röstkloning och röstdesign
- **Samtal** — Telefonväxelstatistik, samtalshistorik, schemaläggning, live-vy
- **Media** — Bildgenerering via xAI
- **AI-minnesprofil** — Syntetiserad användarprofil baserad på konversationsminnen
- **Kostnadsvisning** — Anthropic-kostnad i SEK per svar, session och historik
- **Syntax highlighting** — Swift, Python, JS/TS, HTML, CSS, JSON, Markdown
- **iCloud Keychain** — API-nycklar krypterade och synkade mellan enheter

---

## Navi Brain (server-backend)

Valfri Node.js-backend på egen server för direkt åtkomst till serverbaserade LLMs:

```bash
cd navi-brain
npm install
pm2 start ecosystem.config.js
```

Anslut via Navi → Server → Konfigurera serveradress.

---

## Licens
Privat projekt — Terrorbyte90
