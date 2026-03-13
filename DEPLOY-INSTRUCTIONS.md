# Navi Brain — Deploy & Setup-instruktioner för ny Claude-session

**Datum:** 2026-03-13
**Repo:** https://github.com/Terrorbyte90/Navi-v5
**Branch:** `claude/audit-enhance-ai-models-ou8Vn`
**Server:** `root@209.38.98.107` (SSH port 22, app port 3001)

---

## BAKGRUND

Allt kodarbete är klart och pushat till git. Servern (`209.38.98.107`) kör Navi Brain — en Node.js-server med Express. Problemet: **servern har aldrig blivit deployad** från denna branch. Koden finns i `/navi-brain/` i repot men är inte installerad/körd på servern ännu.

---

## STEG 1: SSH-ÅTKOMST

SSH-nyckel (ed25519, användare: root):

```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACAxPDd8OqPZA4ACxYWW9OBAxSNZoytCB93zcrUcHeCt3gAAAJjqQ3mC6kN5
ggAAAAtzc2gtZWQyNTUxOQAAACAxPDd8OqPZA4ACxYWW9OBAxSNZoytCB93zcrUcHeCt3g
AAAED3y7OiXkmEWlp5z6Ewkm/h/WQVddhnUdAehLcSElGHNzE8N3w6o9kDgALFhZb04EDF
I1mjK0IH3fNytRwd4K3eAAAAE3Jvb3RAVGVkLXNlcnZlcjIwMjYBAg==
-----END OPENSSH PRIVATE KEY-----
```

Spara nyckeln och anslut:

```bash
mkdir -p ~/.ssh
cat > ~/.ssh/navi_server << 'KEYEOF'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACAxPDd8OqPZA4ACxYWW9OBAxSNZoytCB93zcrUcHeCt3gAAAJjqQ3mC6kN5
ggAAAAtzc2gtZWQyNTUxOQAAACAxPDd8OqPZA4ACxYWW9OBAxSNZoytCB93zcrUcHeCt3g
AAAED3y7OiXkmEWlp5z6Ewkm/h/WQVddhnUdAehLcSElGHNzE8N3w6o9kDgALFhZb04EDF
I1mjK0IH3fNytRwd4K3eAAAAE3Jvb3RAVGVkLXNlcnZlcjIwMjYBAg==
-----END OPENSSH PRIVATE KEY-----
KEYEOF
chmod 600 ~/.ssh/navi_server
```

Testa anslutning:

```bash
ssh -i ~/.ssh/navi_server -o StrictHostKeyChecking=no root@209.38.98.107 "echo OK"
```

---

## STEG 2: DEPLOYA NAVI BRAIN TILL SERVERN

Kopiera filer, installera, starta med PM2:

```bash
SERVER="root@209.38.98.107"
KEY="~/.ssh/navi_server"
SSH="ssh -i $KEY -o StrictHostKeyChecking=no"
SCP="scp -i $KEY -o StrictHostKeyChecking=no"
REMOTE="/root/navi-brain"

# Klona repot (om inte redan gjort)
git clone https://github.com/Terrorbyte90/Navi-v5.git /tmp/navi-deploy
cd /tmp/navi-deploy
git checkout claude/audit-enhance-ai-models-ou8Vn

# Skapa mapp på servern
$SSH $SERVER "mkdir -p $REMOTE"

# Kopiera server-filer
$SCP navi-brain/server.js $SERVER:$REMOTE/server.js
$SCP navi-brain/package.json $SERVER:$REMOTE/package.json

# Installera Node.js-beroenden
$SSH $SERVER "cd $REMOTE && npm install --production"

# Skapa .env-fil (VIKTIGT: fyll i OPENROUTER_KEY och ANTHROPIC_API_KEY)
$SSH $SERVER "cat > $REMOTE/.env << 'ENVEOF'
PORT=3001
API_KEY=navi-brain-2026
OPENROUTER_KEY=ANGE_DIN_OPENROUTER_KEY_HÄR
ANTHROPIC_API_KEY=ANGE_DIN_ANTHROPIC_KEY_HÄR
NTFY_TOPIC=navi-brain-prod
ENVEOF"

# Skapa PM2-konfiguration
$SSH $SERVER "cat > $REMOTE/ecosystem.config.js << 'PMEOF'
module.exports = {
  apps: [{
    name: 'navi-brain',
    script: 'server.js',
    cwd: '/root/navi-brain',
    node_args: '--env-file=.env',
    max_memory_restart: '512M',
    autorestart: true,
    watch: false,
    instances: 1,
    exec_mode: 'fork',
  }]
};
PMEOF"

# Starta/starta om med PM2
$SSH $SERVER "cd $REMOTE && pm2 delete navi-brain 2>/dev/null || true && pm2 start ecosystem.config.js && pm2 save"

# Verifiera
$SSH $SERVER "pm2 status"
```

---

## STEG 3: VERIFIERA ATT SERVERN FUNGERAR

```bash
# Hälsokontroll
curl -H "x-api-key: navi-brain-2026" http://209.38.98.107:3001/

# Testa MiniMax-modellen
curl -X POST http://209.38.98.107:3001/ask \
  -H "Content-Type: application/json" \
  -H "x-api-key: navi-brain-2026" \
  -d '{"message": "Hej, fungerar du?"}'

# Testa Qwen-modellen
curl -X POST http://209.38.98.107:3001/qwen/ask \
  -H "Content-Type: application/json" \
  -H "x-api-key: navi-brain-2026" \
  -d '{"message": "Hej!"}'

# Testa Claude/Opus-modellen
curl -X POST http://209.38.98.107:3001/opus/ask \
  -H "Content-Type: application/json" \
  -H "x-api-key: navi-brain-2026" \
  -d '{"message": "Hej!"}'

# Kolla loggar
curl -H "x-api-key: navi-brain-2026" http://209.38.98.107:3001/logs

# Kolla kostnader
curl -H "x-api-key: navi-brain-2026" http://209.38.98.107:3001/costs
```

---

## STEG 4: FELSÖKNING (OM NÅGOT INTE FUNGERAR)

### Servern startar inte
```bash
$SSH $SERVER "cd $REMOTE && pm2 logs navi-brain --lines 50"
```

### Node.js saknas på servern
```bash
$SSH $SERVER "curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs"
```

### PM2 saknas på servern
```bash
$SSH $SERVER "npm install -g pm2"
```

### Port 3001 blockerad av brandvägg
```bash
$SSH $SERVER "ufw allow 3001/tcp && ufw reload"
# Eller om iptables:
$SSH $SERVER "iptables -A INPUT -p tcp --dport 3001 -j ACCEPT"
```

### API-nycklar
Användaren (Ted) behöver ge dig sina API-nycklar:
- **OPENROUTER_KEY** — för MiniMax, Qwen, DeepSeek (hämtas på https://openrouter.ai)
- **ANTHROPIC_API_KEY** — för Claude-endpointen (hämtas på https://console.anthropic.com)

Uppdatera på servern:
```bash
$SSH $SERVER "nano /root/navi-brain/.env"   # eller sed
$SSH $SERVER "cd /root/navi-brain && pm2 restart navi-brain"
```

---

## STEG 5: SAKER SOM ÅTERSTÅR ATT GÖRA (UTÖVER DEPLOY)

### 5a. Sätt upp GitHub Actions auto-deploy (valfritt)
Skapa `.github/workflows/deploy.yml` som deployar automatiskt vid push till main. Kräver att SSH-nyckeln läggs som GitHub Secret (`SSH_PRIVATE_KEY`).

### 5b. Öppna issues från audit (lägre prioritet)
Dessa finns dokumenterade i `AUDIT-REPORT.md`:
1. ChatView image picker `.sheet` saknas
2. AgentPool — agenter rensas aldrig när projekt tas bort
3. PromptQueue — kan hänga om callback failar
4. SelfHealingLoop — kör utan projektkontext
5. Stränglokaliseringar — allt UI-text hårdkodat på svenska
6. Noll tester — ingen testtäckning
7. Duplicerade kostnadsfält i UI

### 5c. Rotera SSH-nyckeln
SSH-nyckeln har delats i klartext i en chatt. **Rekommendation: generera ny nyckel efter deploy.**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/navi_server_new -N ""
$SSH $SERVER "cat >> ~/.ssh/authorized_keys" < ~/.ssh/navi_server_new.pub
# Testa ny nyckel, ta sedan bort den gamla från authorized_keys
```

---

## SAMMANFATTNING

| Vad | Status | Åtgärd |
|-----|--------|--------|
| Server-kod (server.js) | ✅ Klar | Finns i repo |
| Deploy-script | ✅ Klar | `navi-brain/deploy.sh` |
| package.json | ✅ Klar | Express + UUID |
| Git push | ✅ Klar | Branch `claude/audit-enhance-ai-models-ou8Vn` |
| Deploy till server | ❌ Ej gjord | Kör steg 2 ovan |
| API-nycklar i .env | ❌ Ej gjord | Ted måste ange OPENROUTER_KEY + ANTHROPIC_API_KEY |
| Verifiera endpoints | ❌ Ej gjord | Kör steg 3 ovan |
| GitHub Actions | ❌ Ej gjord | Valfritt, steg 5a |
| Rotera SSH-nyckel | ❌ Ej gjord | Rekommenderat, steg 5c |

---

## SNABBREFERENS — ALLA ENDPOINTS

```
GET  /                       → Hälsokontroll
GET  /logs                    → Serverloggar
GET  /costs                   → Token-kostnader
GET  /brain/live-status       → Realtidsstatus alla modeller
GET  /ntfy-topic              → Aktuellt ntfy-topic
GET  /tasks                   → Lista bakgrundsuppgifter
GET  /task/status/:id         → Status för specifik uppgift
GET  /opus/status             → Claude-specifik status

POST /exec                    → Kör terminal-kommando
POST /ask                     → Fråga MiniMax M2.5
POST /minimax/history/clear   → Rensa MiniMax-historik
POST /qwen/ask                → Fråga Qwen3-Coder (fallback: DeepSeek R1)
POST /qwen/history/clear      → Rensa Qwen-historik
POST /opus/ask                → Fråga Claude Sonnet 4.6
POST /opus/history/clear      → Rensa Claude-historik
POST /task/start              → Starta bakgrundsuppgift
POST /task/cancel/:id         → Avbryt uppgift
```

**Auth:** Header `x-api-key: navi-brain-2026` (krävs på alla endpoints)
**Server:** `http://209.38.98.107:3001`
