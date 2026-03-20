// ============================================================
// APNs sender — native iOS push notifications
// Uses p8 key file (AuthKey.p8)
// ============================================================
const apn = require('@parse/node-apn');
const path = require('path');
const fs   = require('fs');

let provider = null;

function init() {
  const keyPath = process.env.APN_KEY_PATH || path.join(__dirname, 'AuthKey.p8');
  const keyId   = process.env.APN_KEY_ID   || '';
  const teamId  = process.env.APN_TEAM_ID  || '';

  if (!keyId || !teamId) {
    console.warn('[APNs] APN_KEY_ID or APN_TEAM_ID not set — APNs disabled, will use ntfy fallback');
    return;
  }

  if (!fs.existsSync(keyPath)) {
    console.warn(`[APNs] Key file not found at ${keyPath} — APNs disabled`);
    return;
  }

  try {
    provider = new apn.Provider({
      token: { key: keyPath, keyId, teamId },
      production: process.env.APN_PRODUCTION === 'true',
    });
    console.log(`[APNs] Provider initialized (keyId=${keyId}, team=${teamId}, production=${process.env.APN_PRODUCTION === 'true'})`);
  } catch (e) {
    console.error('[APNs] Failed to init provider:', e.message);
  }
}

async function sendPush({ tokens, title, body, data = {}, badge = 1 }) {
  if (!tokens || tokens.length === 0) return { sent: 0, failed: 0 };

  if (!provider) {
    // Fallback: log only (ntfy.sh still handles general notifications)
    console.log(`[APNs] No provider — skipping push: "${title}"`);
    return { sent: 0, failed: tokens.length };
  }

  const note = new apn.Notification();
  note.expiry    = Math.floor(Date.now() / 1000) + 3600;
  note.badge     = badge;
  note.sound     = 'default';
  note.alert     = { title, body };
  note.payload        = { ...data };
  note.contentAvailable = 1;
  note.pushType       = 'alert';
  note.topic     = process.env.APN_BUNDLE_ID || 'com.tedsvard.navi.ios';

  try {
    const result = await provider.send(note, tokens);
    if (result.failed.length > 0) {
      result.failed.forEach(f => console.error(`[APNs] Failed token: ${f.device?.slice(0,16)} — ${f.response?.reason || f.error}`));
    }
    console.log(`[APNs] Sent: ${result.sent.length}, Failed: ${result.failed.length}`);
    return { sent: result.sent.length, failed: result.failed.length };
  } catch (e) {
    console.error('[APNs] Send error:', e.message);
    return { sent: 0, failed: tokens.length };
  }
}

function shutdown() {
  if (provider) provider.shutdown();
}

module.exports = { init, sendPush, shutdown };
