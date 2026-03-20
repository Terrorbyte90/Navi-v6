// ============================================================
// Navi Brain v3.3 — Autonomous AI Server
// ============================================================
// Models: MiniMax M2.5 (OpenRouter), DeepSeek R1/Qwen3 (OpenRouter), Claude Sonnet 4.6 (Anthropic)
// Features: ReAct tool loop, persistent tasks, ntfy.sh push, disk persistence
// ============================================================

const express = require('express');
const { v4: uuidv4 } = require('uuid');
const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync, exec } = require('child_process');
const { WebSocketServer } = require('ws');
const telephony = require('./telephony');
const codeAgent = require('./code-agent');
const apns      = require('./apns');

const app = express();
app.use(express.json({ limit: '5mb' }));

// ============================================================
// CONFIG
// ============================================================

const PORT = process.env.PORT || 3001;
const API_KEY = process.env.API_KEY || 'navi-brain-2026';
const OPENROUTER_KEY = process.env.OPENROUTER_KEY || '';
const NTFY_TOPIC = process.env.NTFY_TOPIC || 'navi-brain-' + require('os').hostname();
const ASC_ISSUER_ID = process.env.ASC_ISSUER_ID || '';
const ASC_KEY_ID = process.env.ASC_KEY_ID || '';
const ASC_PRIVATE_KEY_PATH = process.env.ASC_PRIVATE_KEY_PATH || path.join(__dirname, 'AuthKey.p8');
const DATA_DIR = path.join(__dirname, 'data');
process.env.DATA_DIR   = DATA_DIR;
process.env.SERVER_URL = process.env.SERVER_URL || 'http://209.38.98.107:3001';
process.env.ELEVENLABS_API_KEY = process.env.ELEVENLABS_API_KEY || 'sk_acaf2ca0405eb4966a7ca9494dc36fe15c8f38b3484f740d';
process.env.FORTYSIX_ELKS_NUMBER = process.env.FORTYSIX_ELKS_NUMBER || '+4600110357';
const TASKS_FILE = path.join(DATA_DIR, 'tasks.json');
const SESSIONS_FILE = path.join(DATA_DIR, 'sessions.json');
const COSTS_FILE = path.join(DATA_DIR, 'costs.json');
const PUSH_TOKENS_FILE = path.join(DATA_DIR, 'push-tokens.json');
const startTime = Date.now();

// Model IDs
const MODELS = {
  minimax: 'minimax/minimax-m2.5',
  qwen: 'qwen/qwen3-coder:free',
  deepseek: 'deepseek/deepseek-r1',
  opus: 'claude-sonnet-4-6',   // runs via Anthropic API
};

// Push notification tokens (for background notifications)
const pushTokens = new Set();

// ============================================================
// AUTH MIDDLEWARE
// ============================================================

function auth(req, res, next) {
  const key = req.headers['x-api-key'];
  if (key !== API_KEY) {
    return res.status(401).json({ error: 'Ogiltig API-nyckel' });
  }
  next();
}

// ============================================================
// PERSISTENCE — save/load to disk
// ============================================================

function ensureDataDir() {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }
}

function saveTasks() {
  try {
    ensureDataDir();
    const data = JSON.stringify(Object.values(activeTasks), null, 2);
    fs.writeFileSync(TASKS_FILE, data, 'utf8');
  } catch (e) {
    console.error('[PERSIST] Failed to save tasks:', e.message);
  }
}

function loadTasks() {
  try {
    if (!fs.existsSync(TASKS_FILE)) return;
    const data = fs.readFileSync(TASKS_FILE, 'utf8');
    const tasks = JSON.parse(data);
    for (const task of tasks) {
      // Mark any previously "running" tasks as failed (server restarted)
      if (task.status === 'running') {
        task.status = 'failed';
        task.error = 'Servern startades om under körning';
        task.completedAt = new Date().toISOString();
      }
      activeTasks[task.taskId] = task;
    }
    addLog('PERSIST', `Laddade ${tasks.length} sparade uppgifter`);
  } catch (e) {
    console.error('[PERSIST] Failed to load tasks:', e.message);
  }
}

function saveSessions() {
  try {
    ensureDataDir();
    // Only save last 10 messages per session to keep file small
    const trimmed = {};
    for (const [id, s] of Object.entries(sessions)) {
      trimmed[id] = { history: s.history.slice(-20) };
    }
    const data = JSON.stringify({
      minimax: trimmed,
      qwen: Object.fromEntries(Object.entries(qwenSessions).map(([k, v]) => [k, { history: v.history.slice(-20) }])),
      opus: Object.fromEntries(Object.entries(opusSessions).map(([k, v]) => [k, {
        history: v.history.slice(-10),
        totalCost: v.totalCost || 0,
        totalTokens: v.totalTokens || 0,
      }])),
    }, null, 2);
    fs.writeFileSync(SESSIONS_FILE, data, 'utf8');
  } catch (e) {
    console.error('[PERSIST] Failed to save sessions:', e.message);
  }
}

function loadSessions() {
  try {
    if (!fs.existsSync(SESSIONS_FILE)) return;
    const data = JSON.parse(fs.readFileSync(SESSIONS_FILE, 'utf8'));
    if (data.minimax) Object.assign(sessions, data.minimax);
    if (data.qwen) Object.assign(qwenSessions, data.qwen);
    if (data.opus) Object.assign(opusSessions, data.opus);
    addLog('PERSIST', 'Sessioner laddade från disk');
  } catch (e) {
    console.error('[PERSIST] Failed to load sessions:', e.message);
  }
}

function saveCosts() {
  try {
    ensureDataDir();
    fs.writeFileSync(COSTS_FILE, JSON.stringify(costTracker, null, 2), 'utf8');
  } catch (e) {
    console.error('[PERSIST] Failed to save costs:', e.message);
  }
}

function loadCosts() {
  try {
    if (!fs.existsSync(COSTS_FILE)) return;
    const data = JSON.parse(fs.readFileSync(COSTS_FILE, 'utf8'));
    costTracker.total_cost = data.total_cost || 0;
    costTracker.total_requests = data.total_requests || 0;
  } catch (e) {
    console.error('[PERSIST] Failed to load costs:', e.message);
  }
}

function savePushTokens() {
  try {
    ensureDataDir();
    fs.writeFileSync(PUSH_TOKENS_FILE, JSON.stringify(Array.from(pushTokens)), 'utf8');
  } catch (e) { console.error('[PERSIST] Failed to save push tokens:', e.message); }
}

function loadPushTokens() {
  try {
    if (!fs.existsSync(PUSH_TOKENS_FILE)) return;
    const tokens = JSON.parse(fs.readFileSync(PUSH_TOKENS_FILE, 'utf8'));
    tokens.forEach(t => pushTokens.add(t));
    addLog('PERSIST', `Laddade ${tokens.length} push-tokens`);
  } catch (e) { console.error('[PERSIST] Failed to load push tokens:', e.message); }
}

// Auto-save periodically (every 60 seconds)
setInterval(() => {
  saveTasks();
  saveSessions();
  saveCosts();
  savePushTokens();
}, 60_000);

// ============================================================
// STATE
// ============================================================

const sessions = {};          // sessionId → { history: [] }
const opusSessions = {};      // sessionId → { history: [], totalCost, totalTokens }
const qwenSessions = {};      // sessionId → { history: [] }
const activeTasks = {};        // taskId → ServerTask
const logs = [];               // { timestamp, action, details, project, tokens }
let liveStatus = { active: false, model: null, tool: null, iter: null };
let costTracker = { total_cost: 0, total_requests: 0 };

// ============================================================
// LOGGING
// ============================================================

function addLog(action, details, project = 'system', tokens = null) {
  const entry = {
    timestamp: new Date().toISOString(),
    action,
    details: typeof details === 'string' ? details : JSON.stringify(details),
    project,
    tokens,
  };
  logs.push(entry);
  if (logs.length > 500) logs.splice(0, logs.length - 500);
  console.log(`[${action}] ${entry.details.substring(0, 120)}`);
}

// ============================================================
// TOOLS (ReAct loop)
// ============================================================

const TOOLS = [
  {
    name: 'run_command',
    description: 'Kör ett shell-kommando på servern. Returnerar stdout och stderr. Använd för att utforska filsystem, köra git-kommandon, etc.',
    parameters: {
      type: 'object',
      properties: {
        command: { type: 'string', description: 'Shell-kommandot att köra' },
      },
      required: ['command'],
    },
  },
  {
    name: 'read_file',
    description: 'Läs innehållet i en fil. Returnerar filens text.',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Sökväg till filen' },
      },
      required: ['path'],
    },
  },
  {
    name: 'write_file',
    description: 'Skriv innehåll till en fil. Skapar filen om den inte finns.',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Sökväg till filen' },
        content: { type: 'string', description: 'Innehållet att skriva' },
      },
      required: ['path', 'content'],
    },
  },
  {
    name: 'list_files',
    description: 'Lista filer i en katalog.',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Katalogväg' },
        recursive: { type: 'boolean', description: 'Rekursiv listning' },
      },
      required: ['path'],
    },
  },
  {
    name: 'deploy_testflight',
    description: 'Trigga en Xcode Cloud-build via App Store Connect API och ladda upp till TestFlight. Pushar först till GitHub och startar sedan en Xcode Cloud workflow.',
    parameters: {
      type: 'object',
      properties: {
        scheme: { type: 'string', description: 'Scheme att bygga (t.ex. "Navi-iOS")' },
        branch: { type: 'string', description: 'Git-branch att bygga (standard: aktuell branch)' },
        commitMessage: { type: 'string', description: 'Commit-meddelande om ändringar ska pushas först' },
      },
      required: ['scheme'],
    },
  },
];

// Convert tools to OpenAI function format (for OpenRouter)
function toolsToOpenAI() {
  return TOOLS.map(t => ({
    type: 'function',
    function: {
      name: t.name,
      description: t.description,
      parameters: t.parameters,
    },
  }));
}

// Convert tools to Anthropic format
function toolsToAnthropic() {
  return TOOLS.map(t => ({
    name: t.name,
    description: t.description,
    input_schema: t.parameters,
  }));
}

// ============================================================
// XCODE CLOUD — App Store Connect API (JWT + REST)
// ============================================================

function generateASCToken() {
  if (!ASC_ISSUER_ID || !ASC_KEY_ID) {
    throw new Error('App Store Connect API-nycklar saknas (ASC_ISSUER_ID, ASC_KEY_ID)');
  }

  let privateKey;
  try {
    privateKey = fs.readFileSync(ASC_PRIVATE_KEY_PATH, 'utf8');
  } catch {
    throw new Error(`Kan inte läsa privat nyckel: ${ASC_PRIVATE_KEY_PATH}`);
  }

  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: ASC_KEY_ID, typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({
    iss: ASC_ISSUER_ID,
    iat: now,
    exp: now + 1200,
    aud: 'appstoreconnect-v1',
  })).toString('base64url');

  const signingInput = `${header}.${payload}`;
  const sign = crypto.createSign('SHA256');
  sign.update(signingInput);
  const signature = sign.sign(privateKey, 'base64url');

  return `${header}.${payload}.${signature}`;
}

async function ascApiRequest(path, method = 'GET', body = null) {
  const token = generateASCToken();
  const url = new URL(`https://api.appstoreconnect.apple.com/v1${path}`);

  return new Promise((resolve, reject) => {
    const options = {
      hostname: url.hostname,
      path: url.pathname + url.search,
      method,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode >= 400) {
          reject(new Error(`ASC API ${res.statusCode}: ${data.substring(0, 500)}`));
        } else {
          try { resolve(JSON.parse(data)); }
          catch { resolve(data); }
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function triggerXcodeCloudBuild(scheme, branch) {
  // 1. List CI products → find workflows
  const products = await ascApiRequest('/ciProducts');
  if (!products.data || products.data.length === 0) {
    return '❌ Inga Xcode Cloud-produkter hittades. Konfigurera Xcode Cloud i App Store Connect.';
  }

  let allWorkflows = [];
  for (const product of products.data) {
    const wf = await ascApiRequest(`/ciProducts/${product.id}/workflows`);
    if (wf.data) allWorkflows.push(...wf.data);
  }

  if (allWorkflows.length === 0) {
    return '❌ Inga Xcode Cloud-workflows hittade. Skapa en workflow i Xcode eller App Store Connect.';
  }

  // Match by scheme name or use first
  const workflow = allWorkflows.find(w =>
    w.attributes.name.toLowerCase().includes(scheme.toLowerCase())
  ) || allWorkflows[0];

  // 2. Trigger build run
  const buildBody = {
    data: {
      type: 'ciBuildRuns',
      attributes: branch ? { sourceBranchOrTag: { kind: 'BRANCH', name: branch } } : {},
      relationships: {
        workflow: { data: { type: 'ciWorkflows', id: workflow.id } },
      },
    },
  };

  const buildRun = await ascApiRequest('/ciBuildRuns', 'POST', buildBody);
  const buildId = buildRun.data.id;

  addLog('XCODE_CLOUD', `Build startad: workflow=${workflow.attributes.name} id=${buildId}`);

  // 3. Poll for status (max 5 min)
  const start = Date.now();
  const maxWait = 300000;
  let status = 'PENDING';

  while (Date.now() - start < maxWait) {
    await new Promise(r => setTimeout(r, 15000));
    try {
      const check = await ascApiRequest(`/ciBuildRuns/${buildId}`);
      status = check.data.attributes.executionProgress || 'PENDING';
      const completion = check.data.attributes.completionStatus;

      if (status === 'COMPLETE' || completion) {
        if (completion === 'SUCCEEDED') {
          sendNtfyNotification(
            '✅ Xcode Cloud Build Klar',
            `${scheme} har byggts och laddats upp till TestFlight.`,
            ['white_check_mark', 'rocket'], 4
          );
          return `✅ Xcode Cloud build klar!\nWorkflow: ${workflow.attributes.name}\nBuild ID: ${buildId}\nAppen bearbetas av Apple och dyker upp i TestFlight inom kort.`;
        } else {
          sendNtfyNotification(
            '❌ Xcode Cloud Build Misslyckades',
            `${scheme} build failed: ${completion}`,
            ['x', 'warning'], 5
          );
          return `❌ Xcode Cloud build misslyckades.\nWorkflow: ${workflow.attributes.name}\nBuild ID: ${buildId}\nStatus: ${completion}\nKontrollera loggar i App Store Connect.`;
        }
      }
    } catch (e) {
      addLog('XCODE_CLOUD', `Status-poll fel: ${e.message}`);
    }
  }

  return `🟡 Xcode Cloud build pågår.\nWorkflow: ${workflow.attributes.name}\nBuild ID: ${buildId}\nStatus: ${status}\nBygget körs i bakgrunden — ntfy-notis skickas när det är klart.`;
}

// Execute a tool call
async function executeTool(name, args) {
  try {
    switch (name) {
      case 'run_command': {
        const cmd = args.command || '';
        addLog('TOOL', `run_command: ${cmd.substring(0, 100)}`);
        try {
          const output = execSync(cmd, {
            timeout: 30000,
            maxBuffer: 1024 * 1024,
            encoding: 'utf8',
            cwd: '/root',
          });
          return output.substring(0, 8000);
        } catch (e) {
          return `Error (exit ${e.status}): ${(e.stderr || e.message).substring(0, 4000)}`;
        }
      }
      case 'read_file': {
        const filePath = args.path || '';
        addLog('TOOL', `read_file: ${filePath}`);
        if (!fs.existsSync(filePath)) return `Filen finns inte: ${filePath}`;
        const content = fs.readFileSync(filePath, 'utf8');
        return content.substring(0, 15000);
      }
      case 'write_file': {
        const filePath = args.path || '';
        const content = args.content || '';
        addLog('TOOL', `write_file: ${filePath} (${content.length} tecken)`);
        const dir = path.dirname(filePath);
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(filePath, content, 'utf8');
        return `Filen skriven: ${filePath}`;
      }
      case 'list_files': {
        const dirPath = args.path || '/root';
        const recursive = args.recursive || false;
        addLog('TOOL', `list_files: ${dirPath}`);
        if (!fs.existsSync(dirPath)) return `Katalogen finns inte: ${dirPath}`;
        if (recursive) {
          try {
            const output = execSync(`find "${dirPath}" -maxdepth 3 -type f | head -100`, {
              encoding: 'utf8', timeout: 5000,
            });
            return output;
          } catch {
            return 'Kunde inte lista filer rekursivt';
          }
        }
        return fs.readdirSync(dirPath).join('\n');
      }
      case 'deploy_testflight': {
        const scheme = args.scheme || 'Navi-iOS';
        const branch = args.branch || null;
        const commitMsg = args.commitMessage || null;
        addLog('TOOL', `deploy_testflight: scheme=${scheme} branch=${branch}`);

        // Optional: commit and push first
        if (commitMsg) {
          try {
            execSync(`cd /root/repos/Navi-v5 && git add -A && git commit -m "${commitMsg.replace(/"/g, '\\"')}" && git push`, {
              encoding: 'utf8', timeout: 30000,
            });
            addLog('TOOL', 'Git push klar innan deploy');
          } catch (e) {
            addLog('TOOL', `Git push-varning: ${e.message.substring(0, 200)}`);
          }
        }

        try {
          return await triggerXcodeCloudBuild(scheme, branch);
        } catch (e) {
          return `❌ Xcode Cloud-fel: ${e.message}`;
        }
      }
      default:
        return `Okänt verktyg: ${name}`;
    }
  } catch (e) {
    return `Verktygsfel: ${e.message}`;
  }
}

// ============================================================
// OPENROUTER API CALL (with tool support)
// ============================================================

async function callOpenRouter(messages, model, tools = null) {
  const body = {
    model,
    messages,
    max_tokens: 8192,
  };
  if (tools && tools.length > 0) {
    body.tools = tools;
  }

  const data = JSON.stringify(body);

  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'openrouter.ai',
      path: '/api/v1/chat/completions',
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${OPENROUTER_KEY}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://navi.app',
        'X-Title': 'Navi Brain',
        'Content-Length': Buffer.byteLength(data),
      },
      timeout: 180000,
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(body);
          if (json.error) {
            reject(new Error(json.error.message || JSON.stringify(json.error)));
            return;
          }
          resolve(json);
        } catch (e) {
          reject(new Error(`Parse error: ${body.substring(0, 200)}`));
        }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('Timeout')); });
    req.write(data);
    req.end();
  });
}

// ============================================================
// ANTHROPIC API CALL (Claude, with tool support)
// ============================================================

async function callAnthropic(messages, anthropicKey, systemPrompt = null) {
  const body = {
    model: MODELS.opus,
    max_tokens: 8192,
    messages,
    tools: toolsToAnthropic(),
  };
  if (systemPrompt) body.system = systemPrompt;

  const data = JSON.stringify(body);

  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'api.anthropic.com',
      path: '/v1/messages',
      method: 'POST',
      headers: {
        'x-api-key': anthropicKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data),
      },
      timeout: 300000,
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(body);
          if (json.error) {
            reject(new Error(json.error.message || JSON.stringify(json.error)));
            return;
          }
          resolve(json);
        } catch (e) {
          reject(new Error(`Parse error: ${body.substring(0, 200)}`));
        }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('Timeout')); });
    req.write(data);
    req.end();
  });
}

// ============================================================
// REACT LOOP (OpenRouter models)
// ============================================================

const SYSTEM_PROMPT = `Du är Navi Brain — en autonom AI-agent skapad av Ted Svärd.
Du kör på en dedikerad Ubuntu-server (209.38.98.107).
Du har tillgång till verktyg: run_command, read_file, write_file, list_files.

## Svarsformatering (VIKTIGT)
Strukturera ALLTID svar såhär:
- Emoji + rubrik för varje sektion: ## 🎯 Rubrik
- Avdelare --- mellan sektioner
- Punktlistor med - för åtgärder och steg
  - Undernivå med   - för sub-punkter
- ❌ / ✅ / 👉 som visuella markörer i punktlistor
- **Fetstil** för nyckelord och viktiga termer
- Korta, direkta stycken — aldrig långa textväggar

## Regler
- Tänk steg-för-steg (ReAct: Tanke → Åtgärd → Observation → upprepa).
- Använd verktygen aktivt för att utforska, läsa och modifiera filer.
- Svara alltid på svenska om inte annat begärs.
- När du är klar, ge ett tydligt svar med resultatet.
- Du kan köra git-kommandon, installera paket, redigera filer etc.`;

async function reactLoop(prompt, model, sessionHistory, maxIter = 15) {
  const messages = [
    { role: 'system', content: SYSTEM_PROMPT },
    ...sessionHistory,
    { role: 'user', content: prompt },
  ];

  const toolCallNames = [];
  let finalResponse = '';
  let totalTokens = 0;

  for (let i = 0; i < maxIter; i++) {
    liveStatus = { active: true, model, tool: null, iter: i };

    const result = await callOpenRouter(messages, model, toolsToOpenAI());

    const choice = result.choices?.[0];
    if (!choice) break;

    const usage = result.usage || {};
    totalTokens += (usage.completion_tokens || 0) + (usage.prompt_tokens || 0);

    const msg = choice.message;
    messages.push(msg);

    // Check for tool calls
    if (msg.tool_calls && msg.tool_calls.length > 0) {
      for (const tc of msg.tool_calls) {
        const name = tc.function?.name || 'unknown';
        let args = {};
        try { args = JSON.parse(tc.function?.arguments || '{}'); } catch {}

        liveStatus.tool = `${name}(${JSON.stringify(args).substring(0, 60)})`;
        toolCallNames.push(name);

        const result = await executeTool(name, args);
        messages.push({
          role: 'tool',
          tool_call_id: tc.id,
          content: result,
        });
      }
      continue; // Another iteration
    }

    // No tool calls — we have the final response
    finalResponse = msg.content || '';
    break;
  }

  liveStatus = { active: false, model: null, tool: null, iter: null };

  // Track cost
  const inputCost = (totalTokens * 0.3) / 1_000_000;  // rough estimate
  costTracker.total_cost += inputCost;
  costTracker.total_requests += 1;

  return {
    response: finalResponse,
    tokens: totalTokens,
    model,
    toolCalls: toolCallNames,
  };
}

// ============================================================
// REACT LOOP (Anthropic/Claude)
// ============================================================

async function reactLoopAnthropic(prompt, anthropicKey, sessionHistory, maxIter = 15) {
  const messages = [
    ...sessionHistory,
    { role: 'user', content: prompt },
  ];

  const toolCallNames = [];
  let finalResponse = '';
  let totalTokens = 0;
  let totalCost = 0;

  for (let i = 0; i < maxIter; i++) {
    liveStatus = { active: true, model: MODELS.opus, tool: null, iter: i };

    const result = await callAnthropic(messages, anthropicKey, SYSTEM_PROMPT);

    const usage = result.usage || {};
    const inputTok = usage.input_tokens || 0;
    const outputTok = usage.output_tokens || 0;
    totalTokens += inputTok + outputTok;
    totalCost += (inputTok * 3 / 1_000_000) + (outputTok * 15 / 1_000_000);

    // Build assistant message content
    const content = result.content || [];
    messages.push({ role: 'assistant', content });

    // Check for tool_use blocks
    const toolUseBlocks = content.filter(b => b.type === 'tool_use');

    if (toolUseBlocks.length > 0) {
      const toolResults = [];
      for (const block of toolUseBlocks) {
        const name = block.name;
        const args = block.input || {};

        liveStatus.tool = `${name}(${JSON.stringify(args).substring(0, 60)})`;
        toolCallNames.push(name);

        const toolResult = await executeTool(name, args);
        toolResults.push({
          type: 'tool_result',
          tool_use_id: block.id,
          content: toolResult,
        });
      }

      messages.push({ role: 'user', content: toolResults });

      if (result.stop_reason === 'tool_use') {
        continue; // Another iteration
      }
    }

    // Extract text response
    const textBlocks = content.filter(b => b.type === 'text');
    finalResponse = textBlocks.map(b => b.text).join('\n');

    if (result.stop_reason !== 'tool_use') {
      break;
    }
  }

  liveStatus = { active: false, model: null, tool: null, iter: null };

  return {
    response: finalResponse,
    tokens: totalTokens,
    model: MODELS.opus,
    cost: totalCost,
    toolCalls: toolCallNames,
  };
}

// ============================================================
// NTFY.SH — Send push notification
// ============================================================

function sendNtfyNotification(title, message, tags = [], priority = 3) {
  const data = JSON.stringify({
    topic: NTFY_TOPIC,
    title,
    message,
    tags,
    priority,
  });

  const req = https.request({
    hostname: 'ntfy.sh',
    path: '/',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(data),
    },
    timeout: 10000,
  }, (res) => {
    let body = '';
    res.on('data', chunk => body += chunk);
    res.on('end', () => {
      addLog('NTFY', `Skickad: "${title}" (HTTP ${res.statusCode})`);
    });
  });
  req.on('error', (e) => {
    addLog('NTFY', `Fel vid push: ${e.message}`);
  });
  req.write(data);
  req.end();
}

// ============================================================
// ROUTES — Health & Status
// ============================================================

function formatUptime(ms) {
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ${s % 60}s`;
  const h = Math.floor(m / 60);
  return `${h}h ${m % 60}m`;
}

app.get('/', (req, res) => {
  const uptime = formatUptime(Date.now() - startTime);
  const activeTaskCount = Object.values(activeTasks).filter(t => t.status === 'running').length;
  res.json({
    status: 'online',
    version: '3.4.0',
    uptime,
    model: MODELS.minimax,
    activeTasks: activeTaskCount,
    totalTasks: Object.keys(activeTasks).length,
    totalCost: `$${costTracker.total_cost.toFixed(4)}`,
    dailyCost: `$${(costTracker.total_cost / Math.max(1, (Date.now() - startTime) / 86400000)).toFixed(4)}`,
  });
});

// Dedicated health endpoint for monitoring
app.get('/health', (req, res) => {
  const memUsage = process.memoryUsage();
  res.json({
    status: 'ok',
    version: '3.4.0',
    uptime: formatUptime(Date.now() - startTime),
    memory: {
      rss: `${Math.round(memUsage.rss / 1024 / 1024)}MB`,
      heap: `${Math.round(memUsage.heapUsed / 1024 / 1024)}MB`,
    },
    activeTasks: Object.values(activeTasks).filter(t => t.status === 'running').length,
    models: Object.keys(MODELS),
    ntfyTopic: NTFY_TOPIC,
  });
});

// ============================================================
// ROUTES — Costs
// ============================================================

app.get('/costs', auth, (req, res) => {
  res.json(costTracker);
});

// ============================================================
// ROUTES — Logs
// ============================================================

app.get('/logs', auth, (req, res) => {
  const limit = parseInt(req.query.limit) || 30;
  const recent = logs.slice(-limit);
  res.json({ logs: recent, total: logs.length });
});

// ============================================================
// ROUTES — Live Status
// ============================================================

app.get('/brain/live-status', auth, (req, res) => {
  res.json(liveStatus);
});

// ============================================================
// ROUTES — ntfy topic
// ============================================================

app.get('/ntfy-topic', auth, (req, res) => {
  res.json({ topic: NTFY_TOPIC });
});

// ============================================================
// ROUTES — Exec (terminal command)
// ============================================================

app.post('/exec', auth, (req, res) => {
  const cmd = req.body.cmd || '';
  addLog('EXEC', cmd);
  try {
    const output = execSync(cmd, {
      timeout: 30000,
      maxBuffer: 2 * 1024 * 1024,
      encoding: 'utf8',
      cwd: '/root',
    });
    res.json({ output, stdout: output });
  } catch (e) {
    res.json({
      output: e.stdout || '',
      stdout: e.stdout || '',
      stderr: e.stderr || e.message,
      error: e.message,
    });
  }
});

// ============================================================
// ROUTES — Minimax (MiniMax M2.5 via OpenRouter)
// ============================================================

app.post('/ask', auth, async (req, res) => {
  const prompt = req.body.prompt || '';
  const sessionId = req.body.sessionId || req.headers['x-session-id'] || 'default';
  const notify = req.body.notify !== false;

  if (!sessions[sessionId]) sessions[sessionId] = { history: [] };
  const session = sessions[sessionId];

  addLog('MINIMAX', `Prompt: ${prompt.substring(0, 80)}`, 'minimax');

  try {
    const result = await reactLoop(prompt, MODELS.minimax, session.history);

    // Update session history
    session.history.push({ role: 'user', content: prompt });
    session.history.push({ role: 'assistant', content: result.response });
    if (session.history.length > 40) session.history.splice(0, session.history.length - 40);

    addLog('MINIMAX', `Svar: ${result.response.substring(0, 80)} (${result.tokens} tok)`, 'minimax', result.tokens);

    // Send notification for completed chat request
    if (notify && result.toolCalls.length > 0) {
      sendNtfyNotification(
        'MiniMax klar',
        `${result.toolCalls.length} verktyg, ${result.tokens} tok: ${prompt.substring(0, 60)}`,
        ['chat_complete', 'sparkles'],
        3
      );
    }

    res.json({
      response: result.response,
      tokens: result.tokens,
      model: result.model,
      sessionId,
      toolCalls: result.toolCalls,
    });
  } catch (e) {
    addLog('ERROR', `Minimax: ${e.message}`, 'minimax');
    res.status(500).json({ response: `Fel: ${e.message}`, tokens: 0, model: MODELS.minimax });
  }
});

app.post('/minimax/history/clear', auth, (req, res) => {
  const sessionId = req.body.sessionId || req.headers['x-session-id'] || 'default';
  sessions[sessionId] = { history: [] };
  res.json({ ok: true });
});

// ============================================================
// ROUTES — Qwen (Qwen3-Coder / DeepSeek R1 via OpenRouter)
// ============================================================

app.post('/qwen/ask', auth, async (req, res) => {
  const prompt = req.body.prompt || '';
  const sessionId = req.body.sessionId || req.headers['x-session-id'] || 'default';
  const notify = req.body.notify !== false;

  if (!qwenSessions[sessionId]) qwenSessions[sessionId] = { history: [] };
  const session = qwenSessions[sessionId];

  addLog('QWEN', `Prompt: ${prompt.substring(0, 80)}`, 'qwen');

  try {
    // Try Qwen3-Coder first, fall back to DeepSeek R1
    let result;
    try {
      result = await reactLoop(prompt, MODELS.qwen, session.history, 10);
    } catch (e) {
      addLog('QWEN', `Qwen3-Coder misslyckades, testar DeepSeek R1: ${e.message}`);
      result = await reactLoop(prompt, MODELS.deepseek, session.history, 10);
    }

    session.history.push({ role: 'user', content: prompt });
    session.history.push({ role: 'assistant', content: result.response });
    if (session.history.length > 30) session.history.splice(0, session.history.length - 30);

    addLog('QWEN', `Svar: ${result.response.substring(0, 80)} (${result.tokens} tok)`, 'qwen', result.tokens);

    // Send notification for completed chat request
    if (notify && result.toolCalls.length > 0) {
      sendNtfyNotification(
        'Qwen/DeepSeek klar',
        `${result.toolCalls.length} verktyg, ${result.tokens} tok: ${prompt.substring(0, 60)}`,
        ['chat_complete', 'zap'],
        3
      );
    }

    res.json({
      response: result.response,
      tokens: result.tokens,
      model: result.model,
      sessionId,
      toolCalls: result.toolCalls,
    });
  } catch (e) {
    addLog('ERROR', `Qwen: ${e.message}`, 'qwen');
    res.status(500).json({ response: `Fel: ${e.message}`, tokens: 0, model: MODELS.qwen });
  }
});

app.post('/qwen/history/clear', auth, (req, res) => {
  const sessionId = req.body.sessionId || req.headers['x-session-id'] || 'default';
  qwenSessions[sessionId] = { history: [] };
  res.json({ ok: true });
});

// ============================================================
// ROUTES — Opus-Brain (Claude via Anthropic)
// ============================================================

app.post('/opus/ask', auth, async (req, res) => {
  const prompt = req.body.prompt || '';
  const sessionId = req.body.sessionId || req.headers['x-session-id'] || 'default';
  const anthropicKey = req.headers['x-anthropic-key'] || process.env.ANTHROPIC_API_KEY || '';
  const notify = req.body.notify !== false;

  if (!anthropicKey) {
    return res.status(400).json({ response: 'Ingen Anthropic API-nyckel', tokens: 0 });
  }

  if (!opusSessions[sessionId]) opusSessions[sessionId] = { history: [], totalCost: 0, totalTokens: 0 };
  const session = opusSessions[sessionId];

  addLog('OPUS', `Prompt: ${prompt.substring(0, 80)}`, 'opus');

  try {
    const result = await reactLoopAnthropic(prompt, anthropicKey, session.history);

    session.history.push({ role: 'user', content: prompt });
    session.history.push({ role: 'assistant', content: result.response });
    if (session.history.length > 20) session.history.splice(0, session.history.length - 20);

    session.totalCost += result.cost || 0;
    session.totalTokens += result.tokens || 0;

    addLog('OPUS', `Svar: ${result.response.substring(0, 80)} ($${(result.cost || 0).toFixed(6)})`, 'opus', result.tokens);

    // Send notification for completed chat request
    if (notify && result.toolCalls.length > 0) {
      sendNtfyNotification(
        'Claude Sonnet klar',
        `${result.toolCalls.length} verktyg, $${(result.cost || 0).toFixed(4)}: ${prompt.substring(0, 60)}`,
        ['chat_complete', 'brain'],
        3
      );
    }

    res.json({
      response: result.response,
      tokens: result.tokens,
      model: result.model,
      cost: result.cost,
      sessionId,
      toolCalls: result.toolCalls,
    });
  } catch (e) {
    addLog('ERROR', `Opus: ${e.message}`, 'opus');
    res.status(500).json({ response: `Fel: ${e.message}`, tokens: 0, model: MODELS.opus });
  }
});

app.get('/opus/status', auth, (req, res) => {
  let totalCost = 0;
  let totalTokens = 0;
  for (const s of Object.values(opusSessions)) {
    totalCost += s.totalCost || 0;
    totalTokens += s.totalTokens || 0;
  }
  res.json({ totalCost, totalTokens });
});

app.post('/opus/history/clear', auth, (req, res) => {
  const sessionId = req.body.sessionId || req.headers['x-session-id'] || 'default';
  opusSessions[sessionId] = { history: [], totalCost: 0, totalTokens: 0 };
  res.json({ ok: true });
});

// ============================================================
// ROUTES — Persistent Tasks (run even when app is closed)
// ============================================================

app.post('/task/start', auth, async (req, res) => {
  const { prompt, taskId: clientTaskId, model: modelName, sessionId, anthropicKey, notify } = req.body;

  if (!prompt) {
    return res.status(400).json({ error: 'Ingen prompt angiven' });
  }

  const taskId = clientTaskId || uuidv4();
  const modelKey = modelName || 'minimax';

  const task = {
    taskId,
    prompt,
    model: modelKey,
    status: 'running',
    result: null,
    error: null,
    progress: null,
    toolCalls: 0,
    startedAt: new Date().toISOString(),
    completedAt: null,
    sessionId: sessionId || 'default',
    notify: notify !== false,
  };

  activeTasks[taskId] = task;
  saveTasks();
  addLog('TASK', `Startad: ${modelKey} — ${prompt.substring(0, 80)}`, modelKey);

  // Respond immediately — task runs in background
  res.json({ taskId, status: 'running' });

  // Run task asynchronously
  runTaskInBackground(task, anthropicKey || process.env.ANTHROPIC_API_KEY).catch(e => {
    addLog('ERROR', `Task ${taskId}: ${e.message}`);
    task.status = 'failed';
    task.error = e.message;
    task.completedAt = new Date().toISOString();
    saveTasks();

    if (task.notify) {
      sendNtfyNotification(
        'Uppgift misslyckades',
        `${task.model}: ${e.message.substring(0, 100)}`,
        ['error', 'x'],
        4
      );
    }
  });
});

async function runTaskInBackground(task, anthropicKey) {
  try {
    let result;

    if (task.model === 'opus' && anthropicKey) {
      // Claude via Anthropic
      const session = opusSessions[task.sessionId] || { history: [], totalCost: 0, totalTokens: 0 };
      result = await reactLoopAnthropic(task.prompt, anthropicKey, session.history);
      session.totalCost += result.cost || 0;
      session.totalTokens += result.tokens || 0;
      opusSessions[task.sessionId] = session;
    } else {
      // OpenRouter models
      const model = task.model === 'qwen' ? MODELS.qwen : MODELS.minimax;
      const sessionStore = task.model === 'qwen' ? qwenSessions : sessions;
      if (!sessionStore[task.sessionId]) sessionStore[task.sessionId] = { history: [] };
      const session = sessionStore[task.sessionId];
      result = await reactLoop(task.prompt, model, session.history);
      session.history.push({ role: 'user', content: task.prompt });
      session.history.push({ role: 'assistant', content: result.response });
    }

    task.status = 'completed';
    task.result = result.response;
    task.toolCalls = result.toolCalls?.length || 0;
    task.completedAt = new Date().toISOString();
    saveTasks();

    addLog('TASK', `Klar: ${task.model} — ${result.response.substring(0, 80)} (${result.tokens} tok)`, task.model, result.tokens);

    // Send push notification
    if (task.notify) {
      const elapsed = ((new Date(task.completedAt) - new Date(task.startedAt)) / 1000).toFixed(0);
      sendNtfyNotification(
        'Uppgift klar',
        `${task.model} slutförde på ${elapsed}s: ${task.prompt.substring(0, 80)}`,
        ['task_complete', 'white_check_mark'],
        4
      );
    }
  } catch (e) {
    task.status = 'failed';
    task.error = e.message;
    task.completedAt = new Date().toISOString();
    saveTasks();
    throw e;
  }
}

app.get('/task/status/:taskId', auth, (req, res) => {
  const task = activeTasks[req.params.taskId];
  if (!task) {
    return res.status(404).json({ error: 'Uppgiften finns inte' });
  }
  res.json({
    taskId: task.taskId,
    status: task.status,
    result: task.result,
    error: task.error,
    progress: task.progress,
    toolCalls: task.toolCalls,
    model: task.model,
    startedAt: task.startedAt,
    completedAt: task.completedAt,
  });
});

app.post('/task/cancel/:taskId', auth, (req, res) => {
  const task = activeTasks[req.params.taskId];
  if (!task) {
    return res.status(404).json({ error: 'Uppgiften finns inte' });
  }
  task.status = 'cancelled';
  task.completedAt = new Date().toISOString();
  saveTasks();
  addLog('TASK', `Avbruten: ${task.taskId}`, task.model);
  res.json({ ok: true, status: 'cancelled' });
});

// ============================================================
// ROUTES — Xcode Cloud Build
// ============================================================

app.post('/build/xcode-cloud', auth, async (req, res) => {
  const { scheme, branch } = req.body;
  if (!scheme) {
    return res.status(400).json({ error: 'scheme krävs' });
  }

  try {
    addLog('BUILD', `Xcode Cloud triggas: scheme=${scheme} branch=${branch || 'default'}`);
    const result = await triggerXcodeCloudBuild(scheme, branch || null);
    res.json({ ok: true, result });
  } catch (e) {
    addLog('BUILD', `Xcode Cloud-fel: ${e.message}`);
    res.status(500).json({ error: e.message });
  }
});

// List all tasks
app.get('/tasks', auth, (req, res) => {
  const tasks = Object.values(activeTasks).sort((a, b) =>
    new Date(b.startedAt) - new Date(a.startedAt)
  );
  res.json({ tasks });
});

// ============================================================
// START SERVER
// ============================================================

// Load persisted data before starting
loadCosts();
loadTasks();
loadSessions();
loadPushTokens();
telephony.loadAll();

// Register telephony routes
telephony.register(app, auth, addLog);

// Telephony scheduler — check every 30 seconds
setInterval(() => telephony.runScheduler(addLog), 30000);

// ============================================================
// CODE AGENT routes
// ============================================================

app.use('/code', auth, codeAgent.createRouter(express));

// ============================================================
// PUSH TOKEN REGISTRATION
// ============================================================

// Register iOS push token for background notifications
app.post('/register-push', auth, (req, res) => {
  const { deviceToken, platform } = req.body;
  if (!deviceToken) return res.status(400).json({ error: 'deviceToken required' });
  pushTokens.add(deviceToken);
  savePushTokens();
  console.log(`[PUSH] Registered token for ${platform}: ${deviceToken.substring(0, 16)}...`);
  res.json({ ok: true, registered: pushTokens.size });
});

// Get registered push tokens (for debugging)
app.get('/push-tokens', auth, (req, res) => {
  res.json({ count: pushTokens.size, tokens: Array.from(pushTokens).map(t => t.substring(0, 16) + '...') });
});

// ============================================================
// HTTP SERVER + WEBSOCKET
// ============================================================

const httpServer = http.createServer(app);

const wss = new WebSocketServer({ noServer: true });

apns.init();

codeAgent.init(wss, {
  dataDir: DATA_DIR,
  openrouterKey: OPENROUTER_KEY,
  anthropicKey: process.env.ANTHROPIC_API_KEY || '',
  onSessionComplete: async (session, { status, task, summary, error }) => {
    const tokens = Array.from(pushTokens);
    if (tokens.length === 0) return;
    const title = status === 'done' ? '✅ Navi — Klar' : '⚠️ Navi — Fel';
    const body  = status === 'done'
      ? (summary || `"${(task || '').slice(0, 60)}"`)
      : `Fel: "${(task || '').slice(0, 50)}"`;
    await apns.sendPush({
      tokens,
      title,
      body,
      data: { sessionId: session.id, action: 'open_session' },
    });
    console.log(`[SERVER] APNs push sent for session ${session.id}: ${status}`);
  },
});

// Route WebSocket upgrades for /code/ws to the code agent WS server
httpServer.on('upgrade', (request, socket, head) => {
  // Simple auth: check ?key= or X-Api-Key header
  const url = new URL(request.url, 'http://localhost');
  const wsKey = url.searchParams.get('key') || request.headers['x-api-key'] || '';
  if (wsKey !== API_KEY) {
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
    socket.destroy();
    return;
  }

  if (request.url.startsWith('/code/ws')) {
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit('connection', ws, request);
    });
  } else {
    socket.destroy();
  }
});

// ============================================================
// HOURLY SESSION SUMMARIZER
// Reads recent completed sessions, asks AI to extract learnings,
// writes MD files to knowledge/learnings/
// ============================================================

const LEARNINGS_DIR = path.join(__dirname, 'knowledge', 'learnings');

async function summarizeRecentSessions() {
  try {
    if (!fs.existsSync(LEARNINGS_DIR)) {
      fs.mkdirSync(LEARNINGS_DIR, { recursive: true });
    }

    const recentSessions = codeAgent.getRecentCompletedSessions(5);
    if (!recentSessions || recentSessions.length === 0) {
      addLog('SUMMARIZER', 'Inga avslutade sessioner att sammanfatta ännu');
      return;
    }

    addLog('SUMMARIZER', `Sammanfattar ${recentSessions.length} sessioner...`);

    const sessionText = recentSessions.map((s, i) => `
### Session ${i + 1}
**Uppgift:** ${s.task}
**Status:** ${s.status}
**Modell:** ${s.model}
**Meddelanden:** ${s.messageCount}
**TODOs:** ${s.todoDoneCount}/${s.todoCount} klara
**Senaste output:**
${s.lastAssistantText}
`.trim()).join('\n\n---\n\n');

    const prompt = `Du är en lärande AI-agent. Analysera dessa nyligen avslutade Navi-sessioner och extrahera värdefulla lärdomar.

## Sessioner att analysera

${sessionText}

## Uppgift

Skriv en strukturerad Markdown-sammanfattning på svenska med exakt detta format:

# Session-lärdomar ${new Date().toISOString().slice(0, 16).replace('T', ' ')}

## Sessioner

${recentSessions.map((s, i) => `### ${i + 1}. ${s.task.slice(0, 80)}
- **Vad frågades:** [beskriv uppgiften kort]
- **Vad gjordes:** [vilka steg togs, vilka verktyg användes]
- **Resultat:** [vad producerades, status: ${s.status}]
- **Lärdom:** [konkret, handlingsbar lärdom för framtida sessioner]`).join('\n\n')}

## Mönster och insikter
[Identifiera återkommande mönster, vanliga problem, framgångsfaktorer]

## Föreslagna förbättringar
[Konkreta förslag på hur agenten kan bli bättre — ändra strategi, använda andra verktyg, etc.]

Var konkret och handlingsbar. Fokusera på lärdomar som gör agenten bättre nästa gång.`;

    // Use minimax for summarization (fast and cheap)
    const key = OPENROUTER_KEY;
    if (!key) {
      addLog('SUMMARIZER', 'Ingen OPENROUTER_KEY — hoppar över sammanfattning');
      return;
    }

    // Simple OpenRouter call (non-streaming)
    const summaryText = await new Promise((resolve, reject) => {
      const body = JSON.stringify({
        model: MODELS.minimax,
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 2000,
        temperature: 0.4,
      });

      const req = https.request({
        hostname: 'openrouter.ai',
        path: '/api/v1/chat/completions',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${key}`,
          'HTTP-Referer': 'https://navi-brain.io',
          'X-Title': 'Navi Session Summarizer',
        },
        timeout: 60000,
      }, (res) => {
        let data = '';
        res.on('data', c => data += c);
        res.on('end', () => {
          try {
            const parsed = JSON.parse(data);
            resolve(parsed.choices?.[0]?.message?.content || '(ingen output från modellen)');
          } catch (e) {
            reject(new Error('JSON parse failed: ' + data.slice(0, 200)));
          }
        });
      });
      req.on('error', reject);
      req.on('timeout', () => { req.destroy(); reject(new Error('Timeout')); });
      req.write(body);
      req.end();
    });

    // Save to learnings dir
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 16);
    const filename = path.join(LEARNINGS_DIR, `${timestamp}.md`);
    fs.writeFileSync(filename, summaryText, 'utf8');
    addLog('SUMMARIZER', `Lärdomsfil sparad: ${path.basename(filename)} (${summaryText.length} tecken)`);

  } catch (e) {
    addLog('SUMMARIZER', `Fel vid sammanfattning: ${e.message}`);
    console.error('[SUMMARIZER] Error:', e);
  }
}

// Run hourly
setInterval(summarizeRecentSessions, 60 * 60 * 1000);
// Run 3 minutes after startup (gives sessions time to load)
setTimeout(summarizeRecentSessions, 3 * 60 * 1000);

httpServer.listen(PORT, '0.0.0.0', () => {
  addLog('BOOT', `Navi Brain v3.4 startad på port ${PORT}`);
  addLog('BOOT', `Modeller: MiniMax M2.5, Qwen3-Coder, DeepSeek R1, Claude Sonnet 4.6`);
  addLog('BOOT', `ntfy.sh topic: ${NTFY_TOPIC}`);
  addLog('BOOT', `Persistens: ${DATA_DIR}`);
  addLog('BOOT', `Code Agent WebSocket: ws://0.0.0.0:${PORT}/code/ws`);
  console.log(`\n🧠 Navi Brain v3.4 running on port ${PORT}`);
  console.log(`   ntfy topic: ${NTFY_TOPIC}`);
  console.log(`   Models: MiniMax M2.5, Qwen3-Coder, DeepSeek R1, Claude Sonnet 4.6`);
  console.log(`   Code Agent WS: ws://0.0.0.0:${PORT}/code/ws`);
  console.log(`   Data dir: ${DATA_DIR}\n`);
});

// Graceful shutdown — save state
function gracefulShutdown() {
  console.log('[SHUTDOWN] Saving state...');
  saveTasks();
  saveSessions();
  saveCosts();
  savePushTokens();
  apns.shutdown();
  process.exit(0);
}

process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT',  gracefulShutdown);
