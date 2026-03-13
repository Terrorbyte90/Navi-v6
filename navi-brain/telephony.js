// ============================================================
// Navi Telephony Module
// Flow: 46elks → ElevenLabs Conversational AI
// Handles: incoming calls, outbound queue, transcripts, iOS API
// ============================================================

'use strict';

const https = require('https');
const fs = require('fs');
const path = require('path');

// ── Config ──────────────────────────────────────────────────

const ELEVENLABS_KEY   = process.env.ELEVENLABS_API_KEY  || '';
const ELKS_USER        = process.env.FORTYSIX_ELKS_USER  || '';
const ELKS_PASS        = process.env.FORTYSIX_ELKS_PASS  || '';
const ELKS_NUMBER      = process.env.FORTYSIX_ELKS_NUMBER || '+4600110357';
const SERVER_URL       = process.env.SERVER_URL           || 'http://209.38.98.107:3001';
const DATA_DIR         = process.env.DATA_DIR             || path.join(__dirname, 'data');

const CALLS_FILE       = path.join(DATA_DIR, 'calls.json');
const SCHEDULED_FILE   = path.join(DATA_DIR, 'scheduled_calls.json');
const TEL_CONFIG_FILE  = path.join(DATA_DIR, 'telephony_config.json');

// ── State ───────────────────────────────────────────────────

let calls        = {};          // callId → call object
let scheduled    = [];          // outbound call queue
let telConfig    = {            // persisted ElevenLabs IDs
  agentId:       null,
  phoneNumberId: null,
  sipUri:        null,
};

// ── Persistence ─────────────────────────────────────────────

function loadAll() {
  try { if (fs.existsSync(CALLS_FILE))      calls     = JSON.parse(fs.readFileSync(CALLS_FILE,      'utf8')); } catch {}
  try { if (fs.existsSync(SCHEDULED_FILE))  scheduled = JSON.parse(fs.readFileSync(SCHEDULED_FILE,  'utf8')); } catch {}
  try { if (fs.existsSync(TEL_CONFIG_FILE)) telConfig = { ...telConfig, ...JSON.parse(fs.readFileSync(TEL_CONFIG_FILE, 'utf8')) }; } catch {}
}

function saveCalls()     { try { fs.writeFileSync(CALLS_FILE,      JSON.stringify(calls,     null, 2)); } catch {} }
function saveScheduled() { try { fs.writeFileSync(SCHEDULED_FILE,  JSON.stringify(scheduled, null, 2)); } catch {} }
function saveTelConfig() { try { fs.writeFileSync(TEL_CONFIG_FILE, JSON.stringify(telConfig, null, 2)); } catch {} }

// ── ElevenLabs API ───────────────────────────────────────────

function elvRequest(apiPath, method = 'GET', body = null) {
  return new Promise((resolve, reject) => {
    const bodyStr = body ? JSON.stringify(body) : null;
    const opts = {
      hostname: 'api.elevenlabs.io',
      path:     apiPath,
      method,
      headers: {
        'xi-api-key':   ELEVENLABS_KEY,
        'Content-Type': 'application/json',
        ...(bodyStr ? { 'Content-Length': Buffer.byteLength(bodyStr) } : {}),
      },
    };
    const req = https.request(opts, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        if (res.statusCode >= 400) return reject(new Error(`ElevenLabs ${res.statusCode}: ${data.substring(0, 400)}`));
        try { resolve(JSON.parse(data)); } catch { resolve(data); }
      });
    });
    req.on('error', reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

// ── 46elks REST API ──────────────────────────────────────────

function elksRequest(apiPath, formData) {
  return new Promise((resolve, reject) => {
    const auth = Buffer.from(`${ELKS_USER}:${ELKS_PASS}`).toString('base64');
    const body = new URLSearchParams(formData).toString();
    const opts = {
      hostname: 'api.46elks.com',
      path:     apiPath,
      method:   'POST',
      headers: {
        'Authorization':  `Basic ${auth}`,
        'Content-Type':   'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(body),
      },
    };
    const req = https.request(opts, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); } catch { resolve(data); }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// ── Agent management ─────────────────────────────────────────

function buildSystemPrompt(goal) {
  return `Du är en professionell och empatisk samtalsagent som ringer å uppdragsgivarens vägnar.

${goal ? `UPPDRAG FÖR DETTA SAMTAL:\n${goal}\n\n` : ''}INSTRUKTIONER:
- Presentera dig vänligt och kort i början
- Håll samtalet fokuserat och effektivt (max 4 minuter)
- Lyssna aktivt och anpassa tonen efter kunden
- Om kunden är ointresserad, avsluta artigt
- Avsluta alltid med en tydlig sammanfattning av vad som beslutades
- Tala svenska om inte kunden talar ett annat språk

Skapad av Ted Svärd / Navi AI.`;
}

async function getOrCreateDefaultAgent() {
  if (telConfig.agentId) {
    // Return stored agent ID directly — skip HTTP verify (server IP may be blocked)
    return telConfig.agentId;
  }
  return createAgent('Navi Default Agent', buildSystemPrompt(null), 'Hej, hur kan jag hjälpa dig idag?');
}

async function createAgent(name, systemPrompt, firstMessage = 'Hej, hur kan jag hjälpa dig?') {
  const agent = await elvRequest('/v1/convai/agents/create', 'POST', {
    name,
    conversation_config: {
      agent: {
        prompt: {
          prompt:      systemPrompt,
          llm:         'gpt-4o-mini',
          temperature: 0.7,
        },
        first_message: firstMessage,
        language:      'sv',
      },
      tts: {
        voice_id: '21m00Tcm4TlvDq8ikWAM', // Rachel — works well in Swedish
        model_id: 'eleven_turbo_v2_5',
      },
      asr: {
        quality:  'high',
        provider: 'elevenlabs',
      },
    },
    platform_settings: {
      post_call_analysis_data: [
        {
          type:        'string',
          id:          'summary',
          name:        'Samtalssammanfattning',
          description: 'Sammanfatta samtalet i 2-3 meningar.',
          prompt:      'Sammanfatta detta samtal kortfattat.',
        },
        {
          type:        'string',
          id:          'goal_result',
          name:        'Måluppfyllelse',
          description: 'Bedöm om agentens mål uppnåddes. Svara ACHIEVED, PARTIAL eller NOT_ACHIEVED med kort förklaring.',
          prompt:      'Bedöm om agentens mål uppnåddes i samtalet.',
        },
      ],
      webhook: { url: `${SERVER_URL}/call/webhook` },
    },
  });
  return agent.agent_id;
}

// ── ElevenLabs phone number (SIP trunk) ─────────────────────

async function setupPhoneNumber() {
  if (telConfig.phoneNumberId) {
    try {
      const existing = await elvRequest(`/v1/convai/phone-numbers/${telConfig.phoneNumberId}`);
      return { ok: true, existing: true, config: telConfig, phoneNumber: existing };
    } catch { telConfig.phoneNumberId = null; }
  }

  // Create agent first
  const agentId = await getOrCreateDefaultAgent();
  telConfig.agentId = agentId;

  // Register the 46elks SIP trunk with ElevenLabs
  const result = await elvRequest('/v1/convai/phone-numbers', 'POST', {
    phone_number: ELKS_NUMBER,
    label:        'Navi Main Line',
    agent_id:     agentId,
    provider:     'sip_trunk',
    sip_trunk_settings: {
      username:       '4600110357',
      password:       'F309CDD3E75FB6B0339F4C2976F21CA5',
      sip_server:     'voip.46elks.com',
      termination_uri: '4600110357@voip.46elks.com',
    },
  });

  telConfig.phoneNumberId = result.phone_number_id;
  telConfig.sipUri         = result.sip_uri || null;
  saveTelConfig();

  return { ok: true, config: telConfig, phoneNumber: result };
}

// ── Outbound calling ─────────────────────────────────────────

async function placeCall(job) {
  const { id, to, goal, systemPrompt, firstMessage } = job;

  // Create a per-call agent with custom prompt
  const prompt  = systemPrompt || buildSystemPrompt(goal);
  const fmsg    = firstMessage || (goal
    ? `Hej, jag ringer angående ${goal.substring(0, 60)}. Har du ett ögonblick?`
    : 'Hej, hur mår du?');
  const agentId = await createAgent(`Navi — ${(goal || 'Outbound').substring(0, 40)}`, prompt, fmsg);

  // Try ElevenLabs outbound call API first
  if (telConfig.phoneNumberId) {
    try {
      const res = await elvRequest('/v1/convai/outbound-calls', 'POST', {
        agent_id:               agentId,
        agent_phone_number_id:  telConfig.phoneNumberId,
        to_number:              to,
        conversation_initiation_client_data: {
          conversation_config_override: {
            agent: {
              prompt:        { prompt },
              first_message: fmsg,
            },
          },
        },
      });
      const callId = res.conversation_id || `call_${id}`;
      calls[callId] = newCallObj(callId, id, 'outbound', null, to, agentId, goal);
      saveCalls();
      return { ok: true, callId, method: 'elevenlabs' };
    } catch (e) {
      console.error('[TELEPHONY] ElevenLabs outbound failed, trying 46elks:', e.message);
    }
  }

  // Fallback: use 46elks REST API
  if (!ELKS_USER || !ELKS_PASS) throw new Error('46elks API-nycklar saknas (FORTYSIX_ELKS_USER/PASS)');

  const connectTarget = telConfig.sipUri
    ? `sip:${agentId}@${telConfig.sipUri}`
    : `sip:${agentId}@sip.rtc.elevenlabs.io`;

  const result = await elksRequest('/a1/calls', {
    from:        ELKS_NUMBER,
    to,
    voice_start: JSON.stringify({ connect: connectTarget }),
    whenhangup:  `${SERVER_URL}/call/hangup/${id}`,
  });

  if (!result.id) throw new Error(`46elks call failed: ${JSON.stringify(result)}`);

  const callId = result.id;
  calls[callId] = newCallObj(callId, id, 'outbound', null, to, agentId, goal);
  calls[callId].fortyElksId = result.id;
  saveCalls();
  return { ok: true, callId, method: '46elks' };
}

function newCallObj(id, scheduledId, direction, from, to, agentId, goal) {
  return {
    id,
    scheduledId,
    direction,
    from:               from  || null,
    to:                 to    || null,
    status:             'active',
    agentId,
    goal:               goal  || null,
    startedAt:          new Date().toISOString(),
    endedAt:            null,
    duration:           null,
    transcript:         [],
    liveTranscript:     [],
    summary:            null,
    goalResult:         null,
    analysis:           null,
  };
}

// ── Scheduler (run every 30 s) ───────────────────────────────

async function runScheduler(addLog) {
  const now = Date.now();
  const due = scheduled.filter(j => j.status === 'pending' && new Date(j.scheduledAt).getTime() <= now);
  for (const job of due) {
    job.status = 'placing';
    saveScheduled();
    try {
      const r = await placeCall(job);
      job.status = 'placed';
      job.callId = r.callId;
      addLog('TELEPHONY', `✅ Samtal ringer: ${job.to} — ${job.goal || ''}`);
    } catch (e) {
      job.status = 'failed';
      job.error  = e.message;
      addLog('TELEPHONY', `❌ Samtal misslyckades: ${job.to} — ${e.message}`);
    }
    saveScheduled();
  }
}

// ── Route registration ───────────────────────────────────────

function register(app, auth, addLog) {

  // ── Setup ─────────────────────────────────────────────────

  app.post('/telephony/setup', auth, async (req, res) => {
    addLog('TELEPHONY', 'Konfigurerar ElevenLabs SIP-trunk...');
    try {
      const r = await setupPhoneNumber();
      addLog('TELEPHONY', r.existing
        ? `SIP-trunk redan konfigurerad (${telConfig.phoneNumberId})`
        : `SIP-trunk klar! PhoneNumberId: ${telConfig.phoneNumberId}`);
      res.json(r);
    } catch (e) {
      addLog('TELEPHONY', `Setup-fel: ${e.message}`);
      res.status(500).json({ ok: false, error: e.message });
    }
  });

  app.get('/telephony/config', auth, (req, res) => {
    res.json({
      configured:    !!(telConfig.agentId || telConfig.phoneNumberId),
      agentId:       telConfig.agentId,
      phoneNumberId: telConfig.phoneNumberId,
      sipUri:        telConfig.sipUri,
      number:        ELKS_NUMBER,
      hasElksKeys:   !!(ELKS_USER && ELKS_PASS),
      hasElvKey:     !!ELEVENLABS_KEY,
      webhookUrl:    `${SERVER_URL}/call/incoming`,
      // Tell the user what to set in 46elks dashboard
      instructions: {
        inbound:  `Sätt voice_start webhook i 46elks till: ${SERVER_URL}/call/incoming`,
        outbound: `Servern ringer ut via ElevenLabs eller 46elks REST API automatiskt`,
      },
    });
  });

  // ── Incoming call from 46elks ─────────────────────────────

  app.post('/call/incoming', async (req, res) => {
    const { callid, from, to, direction } = req.body;
    const cid = callid || `call_${Date.now()}`;
    addLog('TELEPHONY', `📞 Inkommande: ${from || '?'} → ${to || ELKS_NUMBER}`);

    try {
      const agentId = await getOrCreateDefaultAgent();

      calls[cid] = newCallObj(cid, null, direction || 'incoming', from, to, agentId, null);
      saveCalls();

      const connectTarget = telConfig.sipUri
        ? `sip:${agentId}@${telConfig.sipUri}`
        : `sip:${agentId}@sip.rtc.elevenlabs.io`;

      res.json({
        connect:    connectTarget,
        whenhangup: `${SERVER_URL}/call/hangup/${cid}`,
      });
    } catch (e) {
      addLog('TELEPHONY', `Inkommande samtal-fel: ${e.message}`);
      res.json({ hangup: 'error' });
    }
  });

  // ── ElevenLabs post-call webhook ──────────────────────────

  app.post('/call/webhook', async (req, res) => {
    const data = req.body || {};
    const cid  = data.conversation_id;
    addLog('TELEPHONY', `ElevenLabs webhook: ${data.type || 'unknown'} cid=${cid}`);

    if (cid) {
      if (!calls[cid]) calls[cid] = newCallObj(cid, null, 'incoming', null, null, null, null);
      const call = calls[cid];

      if (data.type === 'conversation_ended' || data.status === 'done') {
        call.status   = 'completed';
        call.endedAt  = new Date().toISOString();
        call.duration = data.metadata?.call_duration_secs || null;
      }

      // Transcript lines
      const rawLines = data.transcript || data.messages || [];
      if (rawLines.length) {
        call.transcript = rawLines;
        call.liveTranscript = rawLines.slice(-30).map(l => ({
          role:    l.role === 'agent' ? 'AI' : 'Kund',
          text:    l.message || l.content || l.text || '',
          timeSec: l.time_in_call_secs || 0,
        }));
      }

      // Post-call analysis
      if (data.analysis) {
        call.analysis   = data.analysis;
        call.summary    = data.analysis.transcript_summary
          || data.analysis.custom_analysis_data?.summary
          || null;
        call.goalResult = data.analysis.custom_analysis_data?.goal_result || null;
      }

      saveCalls();
    }
    res.json({ ok: true });
  });

  // ── 46elks hangup webhook ─────────────────────────────────

  app.post('/call/hangup/:cid', (req, res) => {
    const call = calls[req.params.cid];
    if (call) {
      if (call.status !== 'completed') {
        call.status   = 'completed';
        call.endedAt  = new Date().toISOString();
        call.duration = req.body?.duration || null;
        saveCalls();
        addLog('TELEPHONY', `📴 Avslutad: ${req.params.cid} (${call.duration || '?'}s)`);
      }
    }
    res.json({ ok: true });
  });

  // ── Live transcript update from client (iOS polling) ──────
  // ElevenLabs may also push partial transcripts here during call

  app.post('/call/:cid/transcript', auth, (req, res) => {
    const call = calls[req.params.cid];
    if (!call) return res.status(404).json({ error: 'Samtal ej hittat' });
    const lines = req.body.lines || [];
    if (lines.length) {
      call.liveTranscript = lines;
      saveCalls();
    }
    res.json({ ok: true });
  });

  // ── Call list ─────────────────────────────────────────────

  app.get('/calls', auth, (req, res) => {
    const limit = Math.min(parseInt(req.query.limit) || 50, 200);
    const list = Object.values(calls)
      .sort((a, b) => new Date(b.startedAt) - new Date(a.startedAt))
      .slice(0, limit)
      .map(stripLargeFields);
    res.json({ calls: list, total: Object.keys(calls).length });
  });

  app.get('/calls/live', auth, (req, res) => {
    const active = Object.values(calls)
      .filter(c => c.status === 'active')
      .map(c => ({ ...c }));
    res.json({ calls: active });
  });

  app.get('/calls/stats', auth, (req, res) => {
    const today = new Date().toISOString().slice(0, 10);
    const all   = Object.values(calls);
    const tod   = all.filter(c => (c.startedAt || '').startsWith(today));
    const durs  = tod.filter(c => c.duration).map(c => Number(c.duration));
    res.json({
      today: {
        total:         tod.length,
        incoming:      tod.filter(c => c.direction === 'incoming').length,
        outbound:      tod.filter(c => c.direction === 'outbound').length,
        active:        tod.filter(c => c.status === 'active').length,
        completed:     tod.filter(c => c.status === 'completed').length,
        avgDurationSec: durs.length ? Math.round(durs.reduce((s, v) => s + v, 0) / durs.length) : 0,
        goalsAchieved: tod.filter(c => (c.goalResult || '').startsWith('ACHIEVED')).length,
      },
      allTime: {
        total:    all.length,
        incoming: all.filter(c => c.direction === 'incoming').length,
        outbound: all.filter(c => c.direction === 'outbound').length,
      },
    });
  });

  app.get('/calls/:cid', auth, (req, res) => {
    const call = calls[req.params.cid];
    if (!call) return res.status(404).json({ error: 'Samtal ej hittat' });
    res.json(call);
  });

  // ── Scheduled outbound calls ──────────────────────────────

  app.get('/calls/scheduled', auth, (req, res) => {
    const sorted = [...scheduled].sort((a, b) => new Date(a.scheduledAt) - new Date(b.scheduledAt));
    res.json({ scheduled: sorted });
  });

  app.post('/calls/schedule', auth, async (req, res) => {
    const { to, goal, systemPrompt, firstMessage, scheduledAt, notes } = req.body;
    if (!to || !scheduledAt) return res.status(400).json({ error: 'to och scheduledAt krävs' });

    const id = `sched_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
    const entry = {
      id,
      to,
      goal:         goal         || 'Genomföra samtal',
      systemPrompt: systemPrompt || buildSystemPrompt(goal),
      firstMessage: firstMessage || null,
      scheduledAt,
      notes:        notes || '',
      status:       'pending',
      createdAt:    new Date().toISOString(),
      callId:       null,
      error:        null,
    };
    scheduled.push(entry);
    saveScheduled();
    addLog('TELEPHONY', `📅 Schemalagt: ${to} @ ${scheduledAt} — ${goal || ''}`);
    res.json({ ok: true, scheduled: entry });
  });

  // Bulk schedule: up to 100 calls
  app.post('/calls/schedule/bulk', auth, async (req, res) => {
    const { calls: items } = req.body;
    if (!Array.isArray(items) || items.length > 100) {
      return res.status(400).json({ error: 'Skicka en array "calls" med max 100 objekt' });
    }
    const added = [];
    for (const item of items) {
      if (!item.to || !item.scheduledAt) continue;
      const id = `sched_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
      const entry = {
        id,
        to:           item.to,
        goal:         item.goal         || 'Genomföra samtal',
        systemPrompt: item.systemPrompt || buildSystemPrompt(item.goal),
        firstMessage: item.firstMessage || null,
        scheduledAt:  item.scheduledAt,
        notes:        item.notes || '',
        status:       'pending',
        createdAt:    new Date().toISOString(),
        callId:       null,
        error:        null,
      };
      scheduled.push(entry);
      added.push(entry);
    }
    saveScheduled();
    addLog('TELEPHONY', `📅 ${added.length} samtal schemalagda i bulk`);
    res.json({ ok: true, added: added.length, scheduled: added });
  });

  app.delete('/calls/schedule/:id', auth, (req, res) => {
    const idx = scheduled.findIndex(j => j.id === req.params.id);
    if (idx === -1) return res.status(404).json({ error: 'Hittades ej' });
    scheduled.splice(idx, 1);
    saveScheduled();
    res.json({ ok: true });
  });

  app.patch('/calls/schedule/:id', auth, (req, res) => {
    const job = scheduled.find(j => j.id === req.params.id);
    if (!job) return res.status(404).json({ error: 'Hittades ej' });
    const allowed = ['to', 'goal', 'systemPrompt', 'firstMessage', 'scheduledAt', 'notes'];
    for (const k of allowed) { if (req.body[k] !== undefined) job[k] = req.body[k]; }
    saveScheduled();
    res.json({ ok: true, scheduled: job });
  });

  // Immediate call (no scheduling)
  app.post('/calls/place', auth, async (req, res) => {
    const { to, goal, systemPrompt, firstMessage } = req.body;
    if (!to) return res.status(400).json({ error: 'to krävs' });
    const id = `manual_${Date.now()}`;
    try {
      const r = await placeCall({ id, to, goal, systemPrompt, firstMessage });
      addLog('TELEPHONY', `📞 Direktsamtal: ${to} — ${goal || ''}`);
      res.json(r);
    } catch (e) {
      addLog('TELEPHONY', `Direktsamtal fel: ${e.message}`);
      res.status(500).json({ ok: false, error: e.message });
    }
  });
}

// ── Helper ───────────────────────────────────────────────────

function stripLargeFields(c) {
  const { transcript, liveTranscript, ...rest } = c;
  return {
    ...rest,
    transcriptLines: (transcript || []).length,
    lastLine: (liveTranscript || []).slice(-1)[0] || null,
  };
}

module.exports = { register, loadAll, runScheduler };
