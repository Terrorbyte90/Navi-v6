# NAVI — SERVER MODE
**Trigger:** User wants to work on, understand, or develop the server infrastructure.

---

## WHEN THIS FILE IS ACTIVE

Load this when:
- "Utveckla servern"
- "Lägg till [endpoint/funktion] på servern"
- "Något är fel på servern"
- "Hur är servern uppsatt?"
- Questions about PM2, Node.js, nginx, APIs, server health

---

## SERVER DISCOVERY PROTOCOL

Before touching anything, understand what's there:

```bash
# Step 1: Understand running processes
pm2 list
pm2 status

# Step 2: Understand the directory structure
ls -la ~/
ls -la /var/www/ 2>/dev/null || ls -la /home/ 2>/dev/null

# Step 3: Find project directories
find / -name "package.json" -not -path "*/node_modules/*" 2>/dev/null | head -20
find / -name "*.py" -not -path "*/venv/*" 2>/dev/null | head -20  # If Python

# Step 4: Understand the main service
cat [main-service]/package.json  # or equivalent
cat [main-service]/README.md 2>/dev/null

# Step 5: Check networking
sudo netstat -tlpn 2>/dev/null || ss -tlpn
cat /etc/nginx/sites-enabled/* 2>/dev/null  # nginx config

# Step 6: Check logs for errors
pm2 logs --lines 50
journalctl -n 50 --no-pager

# Step 7: Environment
cat .env 2>/dev/null  # Note: never share contents, just acknowledge
ls /etc/nginx/
```

### Architecture Summary Format
```
## Serverarkitektur

**Provider:** DigitalOcean (Amsterdam)
**OS:** [Ubuntu version]
**Access:** Tailscale / SSH

**Tjänster som körs:**
| Namn | Port | Status | Beskrivning |
|------|------|--------|-------------|
| navi-brain | 3000 | online | AI-agent backend |
| ... | ... | ... | ... |

**Networking:**
- Nginx: [vilka domäner/ports proxyas]
- Öppna portar: [lista]

**Projektmappar:**
- /home/[user]/[service]: [vad det är]

**Miljövariabler (typer, ej värden):**
- API keys: [vilka tjänster]
- Config: [vad som konfigureras]
```

---

## SERVER DEVELOPMENT PROTOCOL

### Before making changes:
```
1. Understand current architecture (see discovery above)
2. Research the best way to implement what's needed
3. Plan the change — what files, what commands, what risks?
4. Test in isolation if possible
5. Have a rollback plan
```

### For adding new endpoints/features:
```bash
# 1. Read existing code patterns
cat [service]/src/[relevant-file]

# 2. Implement following existing patterns
# 3. Test locally before restarting service
node -e "require('./[module]')"  # syntax check

# 4. Restart service
pm2 restart [service-name]
pm2 logs [service-name] --lines 20  # verify no errors

# 5. Test the endpoint
curl -X POST http://localhost:[port]/[endpoint] \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
```

### For nginx changes:
```bash
# Test config before applying
sudo nginx -t

# Apply only if test passes
sudo systemctl reload nginx

# Never reload if test fails
```

---

## NAVI-BRAIN ARCHITECTURE

The AI service running on server:
```
Requests → [entry point] → Magnitude detection → MD file selection → 
→ Minimax 2.5 (OpenRouter) → Response → User
```

Key components to understand:
- How messages route to the AI
- How MD files are loaded and injected
- How tool calls are handled
- How responses are streamed back

---

## SAFE VS DANGEROUS OPERATIONS

### Safe (do without asking):
- Reading files, logs, configs
- Listing processes and services
- Testing endpoints (GET requests)
- Checking disk space, memory usage

### Ask before doing:
- Restarting any PM2 service
- Modifying nginx config
- Changing environment variables
- Installing new packages (npm, apt)
- Any `rm` command

### Never do without explicit confirmation:
- `rm -rf` anything
- Dropping databases
- Stopping services that might affect production
- Changing firewall rules

---

## MONITORING COMMANDS

```bash
# Health check
pm2 status && df -h && free -m

# Recent errors
pm2 logs --err --lines 50

# Resource usage  
pm2 monit  # Interactive
htop        # System resources

# Disk
du -sh /home/* 2>/dev/null | sort -rh | head -10
```

---

*Kombinera med debug.md om något är trasigt på servern.*
*Kombinera med develop.md för att lägga till ny serverlogik.*
