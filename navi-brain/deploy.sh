#!/bin/bash
# ============================================================
# Navi Brain — Deploy to server (209.38.98.107)
# Run from your Mac: ./deploy.sh
# ============================================================

set -e

SERVER="root@209.38.98.107"
REMOTE_DIR="/root/navi-brain"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🧠 Deploying Navi Brain v4.0 to ${SERVER}..."

# 1. Copy files to server
echo "📦 Kopierar filer..."
ssh $SERVER "mkdir -p $REMOTE_DIR"
scp "$SCRIPT_DIR/package.json"    "$SERVER:$REMOTE_DIR/package.json"
scp "$SCRIPT_DIR/server.js"       "$SERVER:$REMOTE_DIR/server.js"
scp "$SCRIPT_DIR/code-agent.js"   "$SERVER:$REMOTE_DIR/code-agent.js"
scp "$SCRIPT_DIR/telephony.js"    "$SERVER:$REMOTE_DIR/telephony.js"

# 2. Install dependencies
echo "📥 Installerar beroenden..."
ssh $SERVER "cd $REMOTE_DIR && npm install --production"

# 3. Set up environment (preserve existing .env if present)
echo "⚙️  Kontrollerar miljövariabler..."
ssh $SERVER "
  if [ ! -f $REMOTE_DIR/.env ]; then
    echo 'PORT=3001' > $REMOTE_DIR/.env
    echo 'API_KEY=navi-brain-2026' >> $REMOTE_DIR/.env
    echo 'OPENROUTER_KEY=ANGE_DIN_KEY_HÄR' >> $REMOTE_DIR/.env
    echo 'NTFY_TOPIC=navi-brain-\$(hostname)' >> $REMOTE_DIR/.env
    echo '⚠️  Ny .env skapad — redigera OPENROUTER_KEY!'
  else
    echo '✓ Befintlig .env bevarad'
  fi
"

# 4. Setup pm2 ecosystem
echo "🔄 Konfigurerar pm2..."
ssh $SERVER "cat > $REMOTE_DIR/ecosystem.config.js << 'PMEOF'
module.exports = {
  apps: [{
    name: 'navi-brain',
    script: 'server.js',
    cwd: '$REMOTE_DIR',
    env_file: '.env',
    node_args: '--env-file=.env',
    max_memory_restart: '512M',
    autorestart: true,
    watch: false,
    instances: 1,
    exec_mode: 'fork',
  }]
};
PMEOF"

# 5. Restart with pm2
echo "🚀 Startar om servern..."
ssh $SERVER "
  cd $REMOTE_DIR
  export \$(cat .env | xargs) 2>/dev/null
  pm2 delete navi-brain 2>/dev/null || true
  pm2 start ecosystem.config.js
  pm2 save
  echo ''
  pm2 status
"

echo ""
echo "✅ Navi Brain v4.0 deployad!"
echo "   URL: http://209.38.98.107:3001"
echo "   Loggar: ssh $SERVER 'pm2 logs navi-brain'"
echo ""
echo "Glöm inte:"
echo "  1. Fyll i OPENROUTER_KEY i /root/navi-brain/.env"
echo "  2. Verifiera: curl -H 'x-api-key: navi-brain-2026' http://209.38.98.107:3001/"
