// ============================================================
// Navi Brain v3.4 — Autonomous AI Server
// ============================================================
// Models: MiniMax M2.5 (OpenRouter), DeepSeek R1/Qwen3 (OpenRouter), Claude Sonnet 4.6 (Anthropic)
// Features: ReAct tool loop, persistent tasks, ntfy.sh push, disk persistence, Navi Code v1.0
// ============================================================

const express = require('express');
const { v4: uuidv4 } = require('uuid');
const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync, exec } = require('child_process');
const telephony = require('./telephony');

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
const CODE_SESSIONS_FILE = path.join(DATA_DIR, 'code_sessions.json');
const startTime = Date.now();

// Model IDs
const MODELS = {
  minimax: 'minimax/minimax-m2.5',
  qwen: 'qwen/qwen3-coder',           // paid — proper tool-calling support
  deepseek: 'deepseek/deepseek-r1-0528', // updated DeepSeek R1
  deepseekFallback: 'meta-llama/llama-3.3-70b-instruct',
  opus: 'claude-sonnet-4-6',          // runs via Anthropic API
};

// Free OpenRouter model chain — ordered by quality, used for cost-free fallback
const FREE_MODEL_CHAIN = [
  'qwen/qwen3-coder:free',
  'deepseek/deepseek-chat-v3-0324:free',
  'nvidia/nemotron-3-super-120b-a12b:free',
  'google/gemini-2.5-flash:free',
  'meta-llama/llama-4-maverick:free',
  'qwen/qwen3-235b-a22b:free',
  'meta-llama/llama-3.3-70b-instruct:free',
  'mistralai/mistral-small-3.1-24b-instruct:free',
  'deepseek/deepseek-r1:free',
];

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

// Auto-save periodically (every 60 seconds)
setInterval(() => {
  saveTasks();
  saveSessions();
  saveCosts();
  saveCodeSessions();
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
let codeSessions = {};         // { [sessionId]: CodeSession }
let codeWorkers = {};          // { [sessionId]: { [workerId]: workerInfo } }

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
    description: 'Kör ett shell-kommando på Ubuntu-servern. Returnerar stdout+stderr. Använd för git-kommandon, filoperationer, npm, python, curl etc. Git-autentisering via token sköts automatiskt — du behöver inte skicka lösenord manuellt.',
    parameters: {
      type: 'object',
      properties: {
        command: { type: 'string', description: 'Shell-kommandot att köra (bash)' },
        cwd: { type: 'string', description: 'Arbetskatalog (standard: /root). Exempel: /root/repos/Navi-v6' },
      },
      required: ['command'],
    },
  },
  {
    name: 'read_file',
    description: 'Läs innehållet i en fil på servern. Returnerar filens text (max 15 000 tecken).',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Absolut sökväg till filen' },
      },
      required: ['path'],
    },
  },
  {
    name: 'write_file',
    description: 'Skriv eller ersätt en fil på servern. Skapar kataloger om de saknas.',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Absolut sökväg till filen' },
        content: { type: 'string', description: 'Fullständigt filinnehåll att skriva' },
      },
      required: ['path', 'content'],
    },
  },
  {
    name: 'list_files',
    description: 'Lista filer i en katalog på servern.',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Katalogväg (absolut)' },
        recursive: { type: 'boolean', description: 'Rekursiv listning (max djup 3)' },
      },
      required: ['path'],
    },
  },
  {
    name: 'search_files',
    description: 'Sök efter text/mönster i filer på servern med grep/ripgrep. Returnerar filnamn och matchande rader.',
    parameters: {
      type: 'object',
      properties: {
        pattern: { type: 'string', description: 'Söksträngen (regex stöds)' },
        path: { type: 'string', description: 'Katalog att söka i' },
        filePattern: { type: 'string', description: 'Filnamnsmönster, t.ex. "*.swift" eller "*.js"' },
        caseSensitive: { type: 'boolean', description: 'Skiftlägeskänslig sökning (standard: false)' },
      },
      required: ['pattern', 'path'],
    },
  },
  {
    name: 'github_api',
    description: 'Anropa GitHub REST API direkt med admin-token. Använd för att hämta repos, filer, commits, skapa PRs, issues, branches etc. GitHub-ägare: Terrorbyte90. Token autentiseras automatiskt.',
    parameters: {
      type: 'object',
      properties: {
        method: { type: 'string', description: 'HTTP-metod: GET, POST, PUT, PATCH, DELETE', enum: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'] },
        path: { type: 'string', description: 'API-sökväg, t.ex. /repos/Terrorbyte90/Navi-v6/contents/README.md eller /repos/Terrorbyte90/Navi-v6/git/refs' },
        body: { type: 'object', description: 'JSON-body för POST/PUT/PATCH (valfritt)' },
      },
      required: ['method', 'path'],
    },
  },
  {
    name: 'deploy_testflight',
    description: 'Trigga en Xcode Cloud-build och deploya till TestFlight via App Store Connect API.',
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

// Exponential backoff retry for API calls
async function withRetry(fn, maxRetries = 3, baseDelayMs = 2000) {
  let lastError;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastError = err;
      const msg = (err.message || '').toLowerCase();
      // Don't retry on permanent errors
      if (msg.includes('401') || msg.includes('invalid_api_key') ||
          msg.includes('bad url') || attempt >= maxRetries) {
        throw err;
      }
      const delay = baseDelayMs * Math.pow(2, attempt) * (0.8 + Math.random() * 0.4);
      addLog('RETRY', `Attempt ${attempt + 1} failed: ${err.message.substring(0, 80)} — waiting ${Math.round(delay)}ms`);
      await new Promise(r => setTimeout(r, delay));
    }
  }
  throw lastError;
}

// Classify task complexity: 'simple', 'medium', or 'complex'
function detectComplexity(prompt) {
  if (!prompt) return 'medium';
  const p = prompt.toLowerCase();
  const len = prompt.length;
  // Simple: short factual questions
  const simplePatterns = /^(vad |vad är |vad betyder |förklara |hur stavas |berätta |vem |när |var |how |what |who |when |explain |define |list )/;
  if (simplePatterns.test(p) && len < 180) return 'simple';
  // Complex: multi-step work
  const complexPatterns = /(refactor|migrer|bygg|implementera|skapa|analysera|fixa alla|gå igenom|undersök hela|klon|deploya|testa allt|uppdatera alla|refactor all|implement all|build|create.*project)/;
  if (complexPatterns.test(p) || len > 600) return 'complex';
  return 'medium';
}

// Execute a tool call — githubToken is injected so git ops can authenticate
async function executeTool(name, args, githubToken = null) {
  try {
    switch (name) {
      case 'run_command': {
        const cmd = args.command || '';
        const cwd = args.cwd || '/root';
        addLog('TOOL', `run_command: ${cmd.substring(0, 100)}`);
        try {
          // Inject GitHub token into environment so git push/pull/clone works
          const env = { ...process.env };
          if (githubToken) {
            env.GIT_ASKPASS = '/bin/echo';
            env.GITHUB_TOKEN = githubToken;
            // Configure git to use token-based auth inline for this call
            // Pre-configure credential helper to use the token
            try {
              execSync(
                `git config --global credential.helper '!f() { echo "username=x-token"; echo "password=${githubToken}"; }; f'`,
                { encoding: 'utf8', timeout: 5000 }
              );
            } catch {}
          }
          const output = execSync(cmd, {
            timeout: 60000,      // 60s — git clone/push can take time
            maxBuffer: 2 * 1024 * 1024,
            encoding: 'utf8',
            cwd,
            env,
          });
          return output.substring(0, 10000) || '(tom utdata — kommandot lyckades)';
        } catch (e) {
          const errOut = ((e.stderr || '') + ' ' + (e.stdout || '') + ' ' + e.message).trim();
          return `Fel (exit ${e.status ?? '?'}): ${errOut.substring(0, 5000)}`;
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
        return `✅ Filen skriven: ${filePath} (${content.length} tecken)`;
      }
      case 'list_files': {
        const dirPath = args.path || '/root';
        const recursive = args.recursive || false;
        addLog('TOOL', `list_files: ${dirPath}`);
        if (!fs.existsSync(dirPath)) return `Katalogen finns inte: ${dirPath}`;
        if (recursive) {
          try {
            const output = execSync(`find "${dirPath}" -maxdepth 4 -not -path '*/node_modules/*' -not -path '*/.git/objects/*' | head -200`, {
              encoding: 'utf8', timeout: 8000,
            });
            return output || '(tom katalog)';
          } catch {
            return fs.readdirSync(dirPath).join('\n');
          }
        }
        return fs.readdirSync(dirPath).join('\n') || '(tom katalog)';
      }
      case 'search_files': {
        const pattern = args.pattern || '';
        const searchPath = args.path || '/root';
        const filePattern = args.filePattern ? `--include="${args.filePattern}"` : '';
        const caseFlag = args.caseSensitive ? '' : '-i';
        addLog('TOOL', `search_files: "${pattern}" in ${searchPath}`);
        try {
          const cmd = `grep -r ${caseFlag} --line-number ${filePattern} "${pattern.replace(/"/g, '\\"')}" "${searchPath}" 2>/dev/null | head -100`;
          const output = execSync(cmd, { encoding: 'utf8', timeout: 15000, maxBuffer: 1024 * 1024 });
          return output || `Inga matchningar för "${pattern}" i ${searchPath}`;
        } catch (e) {
          if (e.status === 1) return `Inga matchningar för "${pattern}" i ${searchPath}`;
          return `Sökfel: ${e.message.substring(0, 500)}`;
        }
      }
      case 'github_api': {
        const method = (args.method || 'GET').toUpperCase();
        const apiPath = args.path || '';
        const body = args.body || null;
        const token = githubToken || process.env.GITHUB_TOKEN || '';
        addLog('TOOL', `github_api: ${method} ${apiPath}`);

        if (!token) return '❌ Ingen GitHub-token tillgänglig. Skicka x-github-token i headern.';

        const result = await new Promise((resolve, reject) => {
          const bodyData = body ? JSON.stringify(body) : null;
          const req = https.request({
            hostname: 'api.github.com',
            path: apiPath,
            method,
            headers: {
              'Authorization': `Bearer ${token}`,
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'Navi-Brain/3.5',
              'X-GitHub-Api-Version': '2022-11-28',
              ...(bodyData ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(bodyData) } : {}),
            },
            timeout: 30000,
          }, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
              try {
                const json = JSON.parse(data);
                if (res.statusCode >= 400) {
                  resolve(`❌ GitHub API ${res.statusCode}: ${JSON.stringify(json.message || json).substring(0, 500)}`);
                } else {
                  resolve(JSON.stringify(json, null, 2).substring(0, 12000));
                }
              } catch {
                resolve(data.substring(0, 5000));
              }
            });
          });
          req.on('error', reject);
          req.on('timeout', () => { req.destroy(); reject(new Error('GitHub API timeout')); });
          if (bodyData) req.write(bodyData);
          req.end();
        });
        return result;
      }
      case 'deploy_testflight': {
        const scheme = args.scheme || 'Navi-iOS';
        const branch = args.branch || null;
        const commitMsg = args.commitMessage || null;
        addLog('TOOL', `deploy_testflight: scheme=${scheme} branch=${branch}`);

        // Optional: commit and push first
        if (commitMsg) {
          try {
            const repoPath = '/root/repos/Navi-v6';
            const env = { ...process.env };
            if (githubToken) env.GITHUB_TOKEN = githubToken;
            execSync(
              `git add -A && git commit -m "${commitMsg.replace(/"/g, '\\"')}" && git push`,
              { encoding: 'utf8', timeout: 60000, cwd: repoPath, env }
            );
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

// MiniMax does not support system role — fold system prompt into first user message
function prepareMessagesForModel(messages, model) {
  if (!model.includes('minimax')) return messages;
  const result = [...messages];
  const sysIdx = result.findIndex(m => m.role === 'system');
  if (sysIdx === -1) return result;
  const sysContent = result[sysIdx].content;
  result.splice(sysIdx, 1);
  const firstUserIdx = result.findIndex(m => m.role === 'user');
  if (firstUserIdx >= 0) {
    const existing = result[firstUserIdx];
    result[firstUserIdx] = {
      ...existing,
      content: `<system>\n${sysContent}\n</system>\n\n${existing.content}`,
    };
  } else {
    result.unshift({ role: 'user', content: `<system>\n${sysContent}\n</system>` });
  }
  return result;
}

async function callOpenRouter(messages, model, tools = null) {
  const preparedMessages = prepareMessagesForModel(messages, model);
  const body = {
    model,
    messages: preparedMessages,
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

function buildSystemPrompt(githubToken = null) {
  const tokenSection = githubToken
    ? `\nGITHUB-TOKEN (admin-åtkomst till Terrorbyte90):
- Token finns och är injicerat i git credential helper automatiskt.
- För github_api-verktyget autentiseras det automatiskt — du behöver inte skicka det manuellt.
- För git push/pull/clone via run_command fungerar autentisering automatiskt.
- GitHub-ägare: Terrorbyte90 | API-bas: https://api.github.com\n`
    : `\nOBS: Ingen GitHub-token skickades med denna förfrågan. Be användaren konfigurera token i appen.\n`;

  return `Du är Navi Brain — en kraftfull autonom AI-kodningsagent skapad av Ted Svärd.
Du kör på en dedikerad Ubuntu-server (209.38.98.107) med full root-åtkomst.
Du agerar som Claude Code — du utforskar, planerar, implementerar och verifierar självständigt.

SERVERMILJÖ:
- OS: Ubuntu Linux, root-användare, IP: 209.38.98.107
- Repos klonade under: /root/repos/ (t.ex. /root/repos/Navi-v6, /root/repos/BabyCare-v1)
- Klona ny repo: git clone https://github.com/Terrorbyte90/<repo>.git /root/repos/<repo>
- Verktyg installerade: Node.js, git, python3, curl, npm, pip, jq, find, grep
- Serverns eget projekt: /root/navi-brain/ (server.js, package.json, data/)
${tokenSection}
VERKTYG DU HAR:
- run_command(command, cwd?): Kör bash-kommando. cwd standard: /root. Alltid specificera cwd för repo-arbete.
- read_file(path): Läs fil (max 15 000 tecken per anrop). Läs ALLTID filen innan du ändrar den.
- write_file(path, content): Skriv/ersätt fil. Skapar kataloger automatiskt.
- list_files(path, recursive?): Lista katalog (maxdjup 4, exkl. node_modules/.git).
- search_files(pattern, path, filePattern?, caseSensitive?): Grep/sök i filer.
- github_api(method, path, body?): GitHub REST API direkt. GitHub-ägare: Terrorbyte90.
- deploy_testflight(scheme, branch?, commitMessage?): Bygg och deploya via Xcode Cloud.

ARBETSMETOD — CLAUDE CODE-STIL (OBLIGATORISK):
Steg 1 UTFORSKA: Innan du börjar, utforska relevanta filer. Läs alltid koden INNAN du ändrar den.
         - list_files för att förstå strukturen
         - search_files för att hitta relevanta funktioner/klasser
         - read_file för filer du ska ändra
Steg 2 PLANERA: Identifiera exakt vad som behöver göras. Dela upp i konkreta steg.
Steg 3 IMPLEMENTERA: Utför ett steg i taget. Verifiera varje steg med verktyg.
Steg 4 VERIFIERA: Kontrollera att ändringarna fungerar (kör tester, bygg om möjligt).
Steg 5 RAPPORTERA: Sammanfatta exakt vad du gjorde, vilka filer du ändrade, och resultatet.

GIT-REGLER (ALLTID):
- Konfigurera git user FÖRE commits: git config user.email "navi@brain.ai" && git config user.name "Navi Brain"
- Kontrollera nuvarande branch: git status && git log --oneline -5
- Pusha: git push origin <branch> (token autentisering sköts automatiskt)
- Merge/rebase ALDRIG utan explicit instruktion
- Om repo saknas lokalt: git clone https://github.com/Terrorbyte90/<repo>.git /root/repos/<repo>

FELHANTERING (KRITISK):
- Om ett verktyg misslyckas: läs felet NOGA, analysera orsaken, prova alternativ strategi.
- Timeout? Dela upp kommandot i mindre delar, eller öka timeout med 'timeout 120 <kommando>'.
- Nätverksfel? Försök igen med retry-logik: for i in 1 2 3; do <kommando> && break || sleep 3; done
- Syntax-fel i kod? Läs om hela filen, analysera felet, rätta och verifiera.
- Saknar åtkomst? Du har root + GitHub + internet. Lös alltid problemet, ge upp aldrig.

TEXTFORMATERING I SVAR:
- Börja alltid med det direkta svaret. Ge svaret FÖRST, förklaring sedan.
- Enkla frågor: 1–3 meningar ren text. Inga rubriker eller punktlistor.
- Tekniska svar: Markdown. ## för stora sektioner, ### för undersektioner. ALDRIG # (H1).
- Listor: bara för 3+ parallella objekt. Numrerade för steg. Punktlistor för egenskaper.
- **Fetstil** för kritiska termer eller varningar. \`inline-kod\` för filnamn, variabler, kommandon.
- Tabeller: bara för jämförelser av 3+ objekt med samma attribut.
- Inga emoji i tekniska svar. Inga upprepningar av frågan. Inga sammanfattningar av svaret.

VIKTIGA REGLER:
- Fortsätt loopen tills uppgiften är HELT löst (upp till 20 iterationer).
- Säg ALDRIG att du saknar åtkomst — du har root + GitHub + internet.
- Läs filen INNAN du skriver till den. Verifiera ALLTID med verktyg, gissa aldrig.
- Leverera alltid konkret, verifierbart resultat.
- Svara på svenska om inte annat begärs.`;
}

async function reactLoop(prompt, model, sessionHistory, maxIter = 20, githubToken = null) {
  const systemPrompt = buildSystemPrompt(githubToken);
  const messages = [
    { role: 'system', content: systemPrompt },
    ...sessionHistory,
    { role: 'user', content: prompt },
  ];

  const toolCallNames = [];
  let finalResponse = '';
  let totalTokens = 0;

  for (let i = 0; i < maxIter; i++) {
    liveStatus = { active: true, model, tool: null, iter: i };

    const result = await withRetry(() => callOpenRouter(messages, model, toolsToOpenAI()), 3, 1500);

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

        const toolResult = await executeTool(name, args, githubToken);
        messages.push({
          role: 'tool',
          tool_call_id: tc.id,
          content: toolResult,
        });
      }
      continue; // Another iteration
    }

    // No tool calls — model is done
    finalResponse = msg.content || '';
    if (finalResponse) break;  // Only break if we actually got a response
  }

  liveStatus = { active: false, model: null, tool: null, iter: null };

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

async function reactLoopAnthropic(prompt, anthropicKey, sessionHistory, maxIter = 20, githubToken = null) {
  const systemPrompt = buildSystemPrompt(githubToken);
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

    const result = await withRetry(() => callAnthropic(messages, anthropicKey, systemPrompt), 3, 2000);

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

        const toolResult = await executeTool(name, args, githubToken);
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
  const githubToken = req.headers['x-github-token'] || req.body.githubToken || null;

  if (!sessions[sessionId]) sessions[sessionId] = { history: [] };
  const session = sessions[sessionId];

  addLog('MINIMAX', `Prompt: ${prompt.substring(0, 80)}`, 'minimax');

  try {
    const result = await reactLoop(prompt, MODELS.minimax, session.history, 20, githubToken);

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
  const { prompt, sessionId: reqSessionId } = req.body;
  const githubToken = req.headers['x-github-token'] || req.body.githubToken || null;
  const sessionId = req.headers['x-session-id'] || reqSessionId || 'default';
  const modelOverride = req.headers['x-model-override'] || null;

  if (!OPENROUTER_KEY) return res.status(500).json({ response: 'Ingen OpenRouter API-nyckel konfigurerad på servern.', tokens: 0 });
  if (!qwenSessions[sessionId]) qwenSessions[sessionId] = { history: [] };
  const session = qwenSessions[sessionId];

  const complexity = detectComplexity(prompt);
  const maxIter = complexity === 'simple' ? 3 : complexity === 'complex' ? 20 : 12;

  // Try each model in the chain until one succeeds
  const modelChain = modelOverride ? [modelOverride, ...FREE_MODEL_CHAIN] : FREE_MODEL_CHAIN;
  let lastError = null;

  for (const model of modelChain) {
    try {
      addLog('QWEN', `Försöker ${model} (complexity: ${complexity})`, 'qwen');
      const result = await reactLoop(prompt, model, session.history, maxIter, githubToken);
      session.history.push({ role: 'user', content: prompt });
      session.history.push({ role: 'assistant', content: result.response });
      if (session.history.length > 30) session.history = session.history.slice(-30);
      saveSessions();
      return res.json({ ...result, usedModel: model });
    } catch (e) {
      lastError = e;
      addLog('QWEN', `${model} misslyckades: ${e.message.substring(0, 100)}`, 'qwen');
      // Continue to next model on any error
    }
  }

  // All models failed
  res.status(500).json({ response: `Alla gratismodeller misslyckades. Sista fel: ${lastError?.message}`, tokens: 0 });
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
  const githubToken = req.headers['x-github-token'] || req.body.githubToken || null;

  if (!anthropicKey) {
    return res.status(400).json({ response: 'Ingen Anthropic API-nyckel', tokens: 0 });
  }

  if (!opusSessions[sessionId]) opusSessions[sessionId] = { history: [], totalCost: 0, totalTokens: 0 };
  const session = opusSessions[sessionId];

  addLog('OPUS', `Prompt: ${prompt.substring(0, 80)}`, 'opus');

  try {
    const result = await reactLoopAnthropic(prompt, anthropicKey, session.history, 20, githubToken);

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
  const githubToken = req.headers['x-github-token'] || req.body.githubToken || null;

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
    githubToken,  // store for background use
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
  const githubToken = task.githubToken || null;
  try {
    let result;

    if (task.model === 'opus' && anthropicKey) {
      // Claude via Anthropic
      const session = opusSessions[task.sessionId] || { history: [], totalCost: 0, totalTokens: 0 };
      result = await reactLoopAnthropic(task.prompt, anthropicKey, session.history, 20, githubToken);
      session.totalCost += result.cost || 0;
      session.totalTokens += result.tokens || 0;
      opusSessions[task.sessionId] = session;
    } else if (task.model === 'free') {
      // Free model chain — cycles through FREE_MODEL_CHAIN with retry
      if (!qwenSessions[task.sessionId]) qwenSessions[task.sessionId] = { history: [] };
      const session = qwenSessions[task.sessionId];
      let lastError;
      for (const freeModel of FREE_MODEL_CHAIN) {
        try {
          task.progress = `Försöker ${freeModel.split('/').pop().replace(':free', '')}…`;
          result = await reactLoop(task.prompt, freeModel, session.history, 15, githubToken);
          session.history.push({ role: 'user', content: task.prompt });
          session.history.push({ role: 'assistant', content: result.response });
          break; // success — stop trying
        } catch (e) {
          lastError = e;
          addLog('WARN', `Free model ${freeModel} misslyckades: ${e.message.substring(0, 80)}`);
          continue;
        }
      }
      if (!result) throw lastError || new Error('Alla gratismodeller misslyckades');
    } else {
      // OpenRouter paid models (minimax, qwen)
      const model = task.model === 'qwen' ? MODELS.qwen : MODELS.minimax;
      const sessionStore = task.model === 'qwen' ? qwenSessions : sessions;
      if (!sessionStore[task.sessionId]) sessionStore[task.sessionId] = { history: [] };
      const session = sessionStore[task.sessionId];
      result = await reactLoop(task.prompt, model, session.history, 20, githubToken);
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
// CODE AGENT — Persistence
// ============================================================

function saveCodeSessions() {
  try {
    ensureDataDir();
    fs.writeFileSync(CODE_SESSIONS_FILE, JSON.stringify(codeSessions, null, 2), 'utf8');
  } catch (e) {
    console.error('[PERSIST] Failed to save code sessions:', e.message);
  }
}

function loadCodeSessions() {
  try {
    if (!fs.existsSync(CODE_SESSIONS_FILE)) return;
    const data = JSON.parse(fs.readFileSync(CODE_SESSIONS_FILE, 'utf8'));
    codeSessions = data || {};
    let fixed = 0;
    for (const session of Object.values(codeSessions)) {
      if (session.status === 'working') {
        session.status = 'error';
        session.messages = session.messages || [];
        session.messages.push({
          role: 'assistant',
          content: 'Servern startades om under körning.',
          timestamp: new Date().toISOString(),
        });
        fixed++;
      }
    }
    addLog('PERSIST', `Laddade ${Object.keys(codeSessions).length} kodsessioner (${fixed} markerade som error)`);
  } catch (e) {
    console.error('[PERSIST] Failed to load code sessions:', e.message);
  }
}

function updateCodeSession(id, changes) {
  if (!codeSessions[id]) return;
  Object.assign(codeSessions[id], changes, { updatedAt: new Date().toISOString() });
  saveCodeSessions();
}

// ============================================================
// CODE AGENT — Tool Definitions
// ============================================================

function codeAgentToolDefinitions() {
  return [
    {
      type: 'function',
      function: {
        name: 'read_file',
        description: 'Läs fil. MAX 15 000 tecken.',
        parameters: {
          type: 'object',
          properties: {
            path: { type: 'string', description: 'Absolut sökväg till filen' },
          },
          required: ['path'],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'write_file',
        description: 'Skriv/ersätt fil. Skapar kataloger automatiskt. Verifiera alltid med read_file efteråt.',
        parameters: {
          type: 'object',
          properties: {
            path: { type: 'string', description: 'Absolut sökväg till filen' },
            content: { type: 'string', description: 'Fullständigt filinnehåll' },
          },
          required: ['path', 'content'],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'list_directory',
        description: 'Lista katalog (exkl. node_modules/.git/dist).',
        parameters: {
          type: 'object',
          properties: {
            path: { type: 'string', description: 'Katalogväg (absolut)' },
            recursive: { type: 'boolean', description: 'Rekursiv listning (max djup 3, standard: false)' },
          },
          required: ['path'],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'search_files',
        description: 'Sök i filer med grep/regex.',
        parameters: {
          type: 'object',
          properties: {
            pattern: { type: 'string', description: 'Söksträngen (regex stöds)' },
            path: { type: 'string', description: 'Katalog att söka i' },
            file_pattern: { type: 'string', description: 'Filnamnsmönster, t.ex. "*.js"' },
            case_sensitive: { type: 'boolean', description: 'Skiftlägeskänslig sökning (standard: false)' },
          },
          required: ['pattern', 'path'],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'run_command',
        description: 'Kör bash-kommando med full root-access.',
        parameters: {
          type: 'object',
          properties: {
            command: { type: 'string', description: 'Shell-kommandot att köra (bash)' },
            cwd: { type: 'string', description: 'Arbetskatalog (standard: /root)' },
            timeout_seconds: { type: 'number', description: 'Timeout i sekunder (standard: 60)' },
          },
          required: ['command'],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'create_directory',
        description: 'Skapa katalog rekursivt.',
        parameters: {
          type: 'object',
          properties: {
            path: { type: 'string', description: 'Katalogväg att skapa' },
          },
          required: ['path'],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'delete_file',
        description: 'Ta bort fil.',
        parameters: {
          type: 'object',
          properties: {
            path: { type: 'string', description: 'Absolut sökväg till filen att ta bort' },
          },
          required: ['path'],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'web_search',
        description: 'Sök på internet.',
        parameters: {
          type: 'object',
          properties: {
            query: { type: 'string', description: 'Sökfråga' },
          },
          required: ['query'],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'github_list_repos',
        description: 'Lista GitHub-repos för Terrorbyte90.',
        parameters: {
          type: 'object',
          properties: {},
          required: [],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'github_read_file',
        description: 'Läs fil direkt från GitHub utan att klona.',
        parameters: {
          type: 'object',
          properties: {
            repo: { type: 'string', description: 'Repo-namn (t.ex. "Navi-v6")' },
            path: { type: 'string', description: 'Filsökväg i repot' },
            ref: { type: 'string', description: 'Branch eller commit (standard: main)' },
          },
          required: ['repo', 'path'],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'github_write_file',
        description: 'Skapa/uppdatera fil på GitHub med commit.',
        parameters: {
          type: 'object',
          properties: {
            repo: { type: 'string', description: 'Repo-namn' },
            file_path: { type: 'string', description: 'Filsökväg i repot' },
            content: { type: 'string', description: 'Filinnehåll (klartext)' },
            commit_message: { type: 'string', description: 'Commit-meddelande' },
          },
          required: ['repo', 'file_path', 'content', 'commit_message'],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'github_create_branch',
        description: 'Skapa ny branch.',
        parameters: {
          type: 'object',
          properties: {
            repo: { type: 'string', description: 'Repo-namn' },
            branch: { type: 'string', description: 'Ny branch-namn' },
            from_branch: { type: 'string', description: 'Bas-branch (standard: main)' },
          },
          required: ['repo', 'branch'],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'github_list_files',
        description: 'Lista filer i GitHub-repo.',
        parameters: {
          type: 'object',
          properties: {
            repo: { type: 'string', description: 'Repo-namn' },
            path: { type: 'string', description: 'Sökväg i repot (standard: rot)' },
            ref: { type: 'string', description: 'Branch eller commit (standard: main)' },
          },
          required: ['repo'],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'github_create_pr',
        description: 'Skapa pull request.',
        parameters: {
          type: 'object',
          properties: {
            repo: { type: 'string', description: 'Repo-namn' },
            title: { type: 'string', description: 'PR-titel' },
            body: { type: 'string', description: 'PR-beskrivning' },
            head: { type: 'string', description: 'Källbranch (head)' },
            base: { type: 'string', description: 'Målbranch (standard: main)' },
          },
          required: ['repo', 'title', 'body', 'head'],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'todo_write',
        description: 'Uppdatera todo-listan som syns i appen.',
        parameters: {
          type: 'object',
          properties: {
            todos: {
              type: 'array',
              description: 'Lista av todos',
              items: {
                type: 'object',
                properties: {
                  text: { type: 'string' },
                  done: { type: 'boolean' },
                },
                required: ['text', 'done'],
              },
            },
          },
          required: ['todos'],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'spawn_worker',
        description: 'Starta parallell worker-agent. Max 8 st. Ger tillbaka workerId.',
        parameters: {
          type: 'object',
          properties: {
            task: { type: 'string', description: 'Uppgiften som workern ska utföra' },
            context: { type: 'string', description: 'Relevant kontext för workern' },
            worker_index: { type: 'number', description: 'Worker-index 0-7 (valfritt)' },
          },
          required: ['task', 'context'],
        },
      },
    },
    {
      type: 'function',
      function: {
        name: 'worker_status',
        description: 'Hämta status/resultat för en worker.',
        parameters: {
          type: 'object',
          properties: {
            worker_id: { type: 'string', description: 'Worker-ID returnerat av spawn_worker' },
          },
          required: ['worker_id'],
        },
      },
    },
  ];
}

// ============================================================
// CODE AGENT — GitHub Helper
// ============================================================

async function githubFetch(method, apiPath, body, githubToken) {
  return new Promise((resolve, reject) => {
    const bodyData = body ? JSON.stringify(body) : null;
    const req = https.request({
      hostname: 'api.github.com',
      path: apiPath,
      method: method.toUpperCase(),
      headers: {
        'Authorization': `Bearer ${githubToken}`,
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Navi-Brain/3.4',
        'X-GitHub-Api-Version': '2022-11-28',
        ...(bodyData ? {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(bodyData),
        } : {}),
      },
      timeout: 30000,
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          resolve({ status: res.statusCode, data: json });
        } catch {
          resolve({ status: res.statusCode, data });
        }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('GitHub API timeout')); });
    if (bodyData) req.write(bodyData);
    req.end();
  });
}

// ============================================================
// CODE AGENT — Tool Executor
// ============================================================

async function executeCodeTool(name, args, session, githubToken) {
  try {
    switch (name) {

      case 'read_file': {
        const filePath = args.path || '';
        addLog('CODE_TOOL', `read_file: ${filePath}`);
        if (!fs.existsSync(filePath)) return `Filen finns inte: ${filePath}`;
        const content = fs.readFileSync(filePath, 'utf8');
        return content.substring(0, 15000);
      }

      case 'write_file': {
        const filePath = args.path || '';
        const content = args.content || '';
        addLog('CODE_TOOL', `write_file: ${filePath} (${content.length} tecken)`);
        const dir = path.dirname(filePath);
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(filePath, content, 'utf8');
        return `Filen skriven: ${filePath} (${content.length} tecken)`;
      }

      case 'list_directory': {
        const dirPath = args.path || '/root';
        const recursive = args.recursive || false;
        addLog('CODE_TOOL', `list_directory: ${dirPath} recursive=${recursive}`);
        if (!fs.existsSync(dirPath)) return `Katalogen finns inte: ${dirPath}`;
        try {
          const maxDepth = recursive ? 3 : 1;
          const output = execSync(
            `find "${dirPath}" -maxdepth ${maxDepth} -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" 2>/dev/null | head -200`,
            { encoding: 'utf8', timeout: 10000 }
          );
          return output || '(tom katalog)';
        } catch {
          return fs.readdirSync(dirPath).join('\n') || '(tom katalog)';
        }
      }

      case 'search_files': {
        const pattern = args.pattern || '';
        const searchPath = args.path || '/root';
        const safePattern = pattern.replace(/"/g, '\\"');
        const safeSearchPath = searchPath.replace(/"/g, '\\"').replace(/`/g, '\\`');
        const filePattern = args.file_pattern ? `--include="${args.file_pattern.replace(/"/g, '')}"` : '';
        const caseFlag = args.case_sensitive ? '' : '-i';
        addLog('CODE_TOOL', `search_files: "${pattern}" in ${searchPath}`);
        try {
          const cmd = `grep -r ${caseFlag} --line-number ${filePattern} "${safePattern}" "${safeSearchPath}" 2>/dev/null | head -100`;
          const output = execSync(cmd, { encoding: 'utf8', timeout: 15000, maxBuffer: 1024 * 1024 });
          return output || `Inga matchningar för "${pattern}" i ${searchPath}`;
        } catch (e) {
          if (e.status === 1) return `Inga matchningar för "${pattern}" i ${searchPath}`;
          return `Sökfel: ${e.message.substring(0, 500)}`;
        }
      }

      case 'run_command': {
        const cmd = args.command || '';
        const cwd = args.cwd || '/root';
        const timeoutSec = Math.min(args.timeout_seconds || 60, 300); // Max 5 minutes
        addLog('CODE_TOOL', `run_command: ${cmd.substring(0, 100)}`);
        try {
          const env = { ...process.env };
          if (githubToken) {
            env.GIT_ASKPASS = 'echo';
            env.GITHUB_TOKEN = githubToken;
            // Use env var based credential helper, not inline token in shell
            env.GIT_TERMINAL_PROMPT = '0';
          }
          const output = execSync(cmd, {
            timeout: timeoutSec * 1000,
            maxBuffer: 2 * 1024 * 1024,
            encoding: 'utf8',
            cwd,
            env,
          });
          return output.substring(0, 10000) || '(tom utdata — kommandot lyckades)';
        } catch (e) {
          const errOut = ((e.stderr || '') + ' ' + (e.stdout || '') + ' ' + e.message).trim();
          return `Fel (exit ${e.status ?? '?'}): ${errOut.substring(0, 5000)}`;
        }
      }

      case 'create_directory': {
        const dirPath = args.path || '';
        addLog('CODE_TOOL', `create_directory: ${dirPath}`);
        fs.mkdirSync(dirPath, { recursive: true });
        return `Katalog skapad: ${dirPath}`;
      }

      case 'delete_file': {
        const filePath = args.path || '';
        addLog('CODE_TOOL', `delete_file: ${filePath}`);
        if (!fs.existsSync(filePath)) return `Filen finns inte: ${filePath}`;
        fs.unlinkSync(filePath);
        return `Filen borttagen: ${filePath}`;
      }

      case 'web_search': {
        const query = args.query || '';
        addLog('CODE_TOOL', `web_search: ${query}`);
        return `Web search inte tillgänglig direkt — använd run_command med curl för att söka. Exempel: curl -s "https://ddg.gg/search?q=${encodeURIComponent(query)}&format=json" | head -2000`;
      }

      case 'github_list_repos': {
        if (!githubToken) return 'Ingen GitHub-token tillgänglig.';
        addLog('CODE_TOOL', 'github_list_repos');
        // Paginate up to 5 pages (max 500 repos)
        let allRepos = [];
        for (let page = 1; page <= 5; page++) {
          const resp = await githubFetch('GET', `/user/repos?per_page=100&page=${page}&sort=updated`, null, githubToken);
          if (resp.status >= 400) return `GitHub API-fel ${resp.status}: ${JSON.stringify(resp.data).substring(0, 500)}`;
          const batch = Array.isArray(resp.data) ? resp.data : [];
          allRepos.push(...batch);
          if (batch.length < 100) break; // No more pages
        }
        return allRepos.map(r => `${r.full_name} (${r.private ? 'privat' : 'publik'}) — ${r.description || 'ingen beskrivning'}`).join('\n') || '(inga repos hittades)';
      }

      case 'github_read_file': {
        if (!githubToken) return 'Ingen GitHub-token tillgänglig.';
        const repo = args.repo || '';
        const filePath = args.path || '';
        const ref = args.ref || 'main';
        addLog('CODE_TOOL', `github_read_file: ${repo}/${filePath}@${ref}`);
        const apiPath = `/repos/Terrorbyte90/${repo}/contents/${filePath}?ref=${ref}`;
        const resp = await githubFetch('GET', apiPath, null, githubToken);
        if (resp.status >= 400) return `GitHub API-fel ${resp.status}: ${JSON.stringify(resp.data).substring(0, 500)}`;
        if (resp.data.content) {
          const decoded = Buffer.from(resp.data.content, 'base64').toString('utf8');
          return decoded.substring(0, 15000);
        }
        return JSON.stringify(resp.data).substring(0, 5000);
      }

      case 'github_write_file': {
        if (!githubToken) return 'Ingen GitHub-token tillgänglig.';
        const repo = args.repo || '';
        const filePath = args.file_path || '';
        const content = args.content || '';
        const commitMessage = args.commit_message || 'Update via Navi Code';
        addLog('CODE_TOOL', `github_write_file: ${repo}/${filePath}`);
        // Get current SHA if file exists
        let sha;
        try {
          const getResp = await githubFetch('GET', `/repos/Terrorbyte90/${repo}/contents/${filePath}`, null, githubToken);
          if (getResp.status === 200 && getResp.data.sha) sha = getResp.data.sha;
        } catch {}
        const putBody = {
          message: commitMessage,
          content: Buffer.from(content).toString('base64'),
        };
        if (sha) putBody.sha = sha;
        const resp = await githubFetch('PUT', `/repos/Terrorbyte90/${repo}/contents/${filePath}`, putBody, githubToken);
        if (resp.status >= 400) return `GitHub API-fel ${resp.status}: ${JSON.stringify(resp.data).substring(0, 500)}`;
        return `Filen uppdaterad på GitHub: ${repo}/${filePath} — commit: ${resp.data.commit?.sha?.substring(0, 8) || 'ok'}`;
      }

      case 'github_create_branch': {
        if (!githubToken) return 'Ingen GitHub-token tillgänglig.';
        const repo = args.repo || '';
        const branch = args.branch || '';
        const fromBranch = args.from_branch || 'main';
        addLog('CODE_TOOL', `github_create_branch: ${repo} ${fromBranch} -> ${branch}`);
        // Get sha of from_branch
        const refResp = await githubFetch('GET', `/repos/Terrorbyte90/${repo}/git/ref/heads/${fromBranch}`, null, githubToken);
        if (refResp.status >= 400) return `Kunde inte hämta ref för ${fromBranch}: ${JSON.stringify(refResp.data).substring(0, 300)}`;
        const sha = refResp.data.object?.sha;
        if (!sha) return `Ingen SHA hittad för branch ${fromBranch}`;
        const createResp = await githubFetch('POST', `/repos/Terrorbyte90/${repo}/git/refs`, {
          ref: `refs/heads/${branch}`,
          sha,
        }, githubToken);
        if (createResp.status >= 400) return `GitHub API-fel ${createResp.status}: ${JSON.stringify(createResp.data).substring(0, 500)}`;
        return `Branch skapad: ${branch} (från ${fromBranch}, sha: ${sha.substring(0, 8)})`;
      }

      case 'github_list_files': {
        if (!githubToken) return 'Ingen GitHub-token tillgänglig.';
        const repo = args.repo || '';
        const filePath = args.path || '';
        const ref = args.ref || 'main';
        addLog('CODE_TOOL', `github_list_files: ${repo}/${filePath}@${ref}`);
        const apiPath = `/repos/Terrorbyte90/${repo}/contents/${filePath}?ref=${ref}`;
        const resp = await githubFetch('GET', apiPath, null, githubToken);
        if (resp.status >= 400) return `GitHub API-fel ${resp.status}: ${JSON.stringify(resp.data).substring(0, 500)}`;
        const items = Array.isArray(resp.data) ? resp.data : [resp.data];
        return items.map(i => `${i.type === 'dir' ? '[DIR]' : '[FIL]'} ${i.path} (${i.size || 0} bytes)`).join('\n');
      }

      case 'github_create_pr': {
        if (!githubToken) return 'Ingen GitHub-token tillgänglig.';
        const repo = args.repo || '';
        const title = args.title || '';
        const body = args.body || '';
        const head = args.head || '';
        const base = args.base || 'main';
        addLog('CODE_TOOL', `github_create_pr: ${repo} ${head} -> ${base}`);
        const resp = await githubFetch('POST', `/repos/Terrorbyte90/${repo}/pulls`, {
          title, body, head, base,
        }, githubToken);
        if (resp.status >= 400) return `GitHub API-fel ${resp.status}: ${JSON.stringify(resp.data).substring(0, 500)}`;
        return `PR skapad: #${resp.data.number} — ${resp.data.html_url}`;
      }

      case 'todo_write': {
        const todos = args.todos || [];
        addLog('CODE_TOOL', `todo_write: ${todos.length} todos`);
        if (session) {
          session.todos = todos;
          updateCodeSession(session.id, { todos });
        }
        return `Todos uppdaterade: ${todos.length} st`;
      }

      case 'spawn_worker': {
        const task = args.task || '';
        const context = args.context || '';
        const workerIndex = args.worker_index !== undefined ? args.worker_index : 0;
        if (!session) return 'Ingen aktiv session för worker.';
        const sessionId = session.id;
        // Count active workers
        const activeWorkerCount = Object.values(codeWorkers[sessionId] || {})
          .filter(w => w.status === 'running').length;
        if (activeWorkerCount >= 8) return 'Max 8 aktiva workers. Vänta tills en är klar.';
        const workerId = uuidv4();
        addLog('CODE_TOOL', `spawn_worker: #${workerIndex} — ${task.substring(0, 60)}`);
        spawnCodeWorker(sessionId, workerId, workerIndex, task, context, githubToken);
        return JSON.stringify({ workerId, workerIndex, status: 'started' });
      }

      case 'worker_status': {
        const workerId = args.worker_id || '';
        if (!session) return 'Ingen aktiv session.';
        const sessionId = session.id;
        const worker = (codeWorkers[sessionId] || {})[workerId];
        if (!worker) return `Ingen worker med id ${workerId} hittad.`;
        return JSON.stringify({
          workerId,
          index: worker.index,
          status: worker.status,
          task: worker.task,
          output: worker.output ? worker.output.substring(0, 3000) : null,
          filesModified: worker.filesModified || [],
          startedAt: worker.startedAt,
          completedAt: worker.completedAt,
        });
      }

      default:
        return `Okänt verktyg: ${name}`;
    }
  } catch (e) {
    return `Verktygsfel (${name}): ${e.message}`;
  }
}

// ============================================================
// CODE AGENT — System Prompt
// ============================================================

function buildCodeAgentSystemPrompt(session, githubToken) {
  const githubSection = githubToken
    ? `\nDu har full admin-åtkomst till github.com/Terrorbyte90.
- Klona repo: run_command("git clone https://github.com/Terrorbyte90/REPO.git /root/repos/REPO")
- Läs filer: github_read_file(repo, path) — läser direkt från GitHub utan att klona
- Skriv: github_write_file(repo, path, content, "feat: beskrivning") — auto-committar
- Skapa PR: github_create_pr(repo, title, body, head_branch)
- Lista repos: github_list_repos()
- ALLTID konfigurera git: git config user.email "navi@brain.ai" && git config user.name "Navi Brain"`
    : `\nOBS: Ingen GitHub-token skickades med denna förfrågan. Be användaren konfigurera token i appen.`;

  return `Du är Navi Code — ett fullt autonomt multi-agent kodningssystem som körs på Navi Brain-servern.
Du drivs av MiniMax M2.5 (1M kontextfönster) och är modellerad efter Claude Code.

## DINA FÖRMÅGOR
- Du körs dygnet runt på servern — användaren kan stänga appen och du FORTSÄTTER JOBBA
- Full filsystemsåtkomst på /root/repos/ — läsa, skriva, ta bort, söka
- Full GitHub-åtkomst (Terrorbyte90-kontot) — klona, pusha, skapa PRs
- Shell-åtkomst med root — npm, pip, git, node, python3, curl, alla standardverktyg
- Upp till 8 parallella workers — starta dem för oberoende deluppgifter
- 1M kontextfönster — kan bearbeta hela kodbaser på en gång

## ARBETSMETOD (OBLIGATORISK — HOPPA ALDRIG ÖVER)
1. UTFORSKA: Läs ALLA relevanta filer innan du skriver något. list_directory → read_file.
2. PLANERA: Skriv todos med todo_write. Var specifik: "Skriv auth-middleware i middleware/auth.js"
3. EXEKVERA: Arbeta metodiskt genom todos. En uppgift åt gången (eller starta workers för parallellism).
4. VERIFIERA: Efter varje write_file — läs filen direkt med read_file för att bekräfta. Kör tester om tillgängligt.
5. COMMITTA: git commit + push efter varje stor funktion. Lämna aldrig ocommittad kod.

## PARALLELLA WORKERS (Använd för stora projekt)
För 5+ oberoende filer/funktioner, starta workers:
- spawn_worker("Implementera auth-routes i /root/repos/app/routes/auth.js", kontext)
- Workers kör simultant — snabbar upp stora projekt 4-8x
- Hämta resultat med worker_status(id), slå ihop resultaten själv
- Max 8 aktiva workers simultant

## GITHUB-ÅTKOMST (ANVÄND ALLTID)${githubSection}

## ASYNKRONITET
Du körs asynkront — användaren kan stänga appen när som helst och du FORTSÄTTER JOBBA.
- Spara framsteg ofta med todo_write och git commits
- Förvänta dig INTE snabb feedback — avsluta uppgifter fullständigt utan att vänta
- Ntfy-notis skickas automatiskt när du är klar

## GRÄNSER
- read_file / github_read_file: MAX 15 000 tecken per fil
- run_command: MAX 10 000 tecken output, MAX 300 sekunder timeout
- list_directory: MAX djup 3, MAX 200 filer
- search_files: MAX 100 matchningar
- workers: MAX 8 aktiva parallella workers
- iterationer: MAX 8 (enkla) / 20 (normala) / 30 (komplexa) per session

## ROBUSTHET — FEL = LÖSNING, INTE STOPP
- Om ett verktyg misslyckas: läs felet, prova alternativ strategi, GE ALDRIG UPP
- Om git push misslyckas: kolla remote, gör git pull --rebase, pusha igen
- Om npm build misslyckas: läs felet, åtgärda grundorsaken
- Logga varje stort steg — användaren kan kolla tillbaka timmar senare

## TEXTFORMATERING
- Börja alltid med det direkta svaret
- Enkla frågor: 1-3 meningar. Inga rubriker eller listor
- ## för stora sektioner (3+), ### för undersektioner, ALDRIG # (H1)
- **fetstil** för kritiska termer. \`inline-kod\` för filnamn, variabler, kommandon
- Inga emoji i tekniska svar. Ingen upprepning av frågan. Ingen summering av svaret

SERVERMILJÖ: Ubuntu Linux, root, /root/repos/ för projekt, verktyg: Node.js, git, python3, npm, curl, jq, find, grep`;
}

// ============================================================
// CODE AGENT — Worker Spawn
// ============================================================

function spawnCodeWorker(parentSessionId, workerId, workerIndex, task, context, githubToken) {
  if (!codeWorkers[parentSessionId]) codeWorkers[parentSessionId] = {};
  const workerInfo = {
    id: workerId,
    index: workerIndex,
    task,
    status: 'running',
    output: null,
    filesModified: [],
    startedAt: new Date().toISOString(),
    completedAt: null,
  };
  codeWorkers[parentSessionId][workerId] = workerInfo;

  // Run worker asynchronously
  (async () => {
    try {
      let workerModel = (codeSessions[parentSessionId] || {}).model || 'minimax/minimax-m2.5';
      // For free chain workers, pick the first free model
      const isWorkerFree = workerModel === 'free';
      if (isWorkerFree) workerModel = FREE_MODEL_CHAIN[0];
      const workerSystemPrompt = `Du är worker #${workerIndex} i Navi Code. Uppgift: ${task}. Kontext: ${context}. Arbeta självständigt, rapportera filerna du skapade/ändrade. Max 10 iterationer.`;
      // prepareMessagesForModel handles MiniMax system→user conversion
      const messages = prepareMessagesForModel([
        { role: 'system', content: workerSystemPrompt },
        { role: 'user', content: task },
      ], workerModel);
      const maxIter = 10;
      let finalResponse = '';

      for (let i = 0; i < maxIter; i++) {
        // Check if parent session was stopped
        if (codeSessions[parentSessionId]?.shouldStop) {
          workerInfo.output = 'Stoppat av användaren.';
          break;
        }
        // For free workers, try model chain with fallback
        let result;
        if (isWorkerFree) {
          let lastErr;
          for (const fm of FREE_MODEL_CHAIN) {
            try {
              result = await callOpenRouter(messages, fm, codeAgentToolDefinitions());
              break;
            } catch (e) { lastErr = e; continue; }
          }
          if (!result) throw lastErr || new Error('Alla gratismodeller misslyckades (worker)');
        } else {
          result = await withRetry(() => callOpenRouter(messages, workerModel, codeAgentToolDefinitions()), 3, 1500);
        }
        const choice = result.choices?.[0];
        if (!choice) break;
        const msg = choice.message;
        messages.push(msg);

        if (msg.tool_calls && msg.tool_calls.length > 0) {
          const fakeSession = { id: parentSessionId, todos: [] };
          // Run worker tool calls in parallel for speed
          const toolResults = await Promise.all(msg.tool_calls.map(async (tc) => {
            const tcName = tc.function?.name || 'unknown';
            let tcArgs = {};
            try { tcArgs = JSON.parse(tc.function?.arguments || '{}'); } catch {}
            const toolResult = await executeCodeTool(tcName, tcArgs, fakeSession, githubToken);
            return { id: tc.id, content: toolResult, tcName, tcArgs };
          }));
          for (const { id, content, tcName, tcArgs } of toolResults) {
            messages.push({ role: 'tool', tool_call_id: id, content });
            // Track file modifications
            if ((tcName === 'write_file' || tcName === 'github_write_file') && tcArgs.path) {
              workerInfo.filesModified.push(tcArgs.path);
            }
          }
          continue;
        }

        finalResponse = msg.content || '';
        if (finalResponse) break;
      }

      workerInfo.status = 'done';
      workerInfo.output = finalResponse;
      workerInfo.completedAt = new Date().toISOString();
      addLog('CODE_WORKER', `Worker #${workerIndex} klar: ${finalResponse.substring(0, 80)}`);
    } catch (e) {
      workerInfo.status = 'error';
      workerInfo.output = `Fel: ${e.message}`;
      workerInfo.completedAt = new Date().toISOString();
      addLog('CODE_WORKER', `Worker #${workerIndex} fel: ${e.message}`);
    } finally {
      // Clean up worker after 10 minutes to avoid memory leaks
      setTimeout(() => {
        if (codeWorkers[parentSessionId]) {
          delete codeWorkers[parentSessionId][workerId];
        }
      }, 10 * 60 * 1000);
    }
  })();

  return workerId;
}

// ============================================================
// CODE AGENT — Main ReAct Loop
// ============================================================

async function codeReactLoop(sessionId, userMessage) {
  const session = codeSessions[sessionId];
  if (!session) throw new Error(`Sessionen ${sessionId} finns inte`);

  // Normalize model ID — map short names to full OpenRouter model IDs
  const MODEL_ALIASES = {
    'minimax':  'minimax/minimax-m2.5',
    'kimi':     'moonshotai/kimi-k2.5',
    'qwen':     'qwen/qwen3-coder',
    'deepseek': 'deepseek/deepseek-r1-0528',
  };
  if (MODEL_ALIASES[session.model]) {
    session.model = MODEL_ALIASES[session.model];
    updateCodeSession(sessionId, { model: session.model });
  }

  const isFreeChain = session.model === 'free';
  const complexity = detectComplexity(userMessage);
  const maxIter = complexity === 'simple' ? 8 : complexity === 'complex' ? 30 : 20;

  // Initialize messages list
  const now = new Date().toISOString();
  session.messages = session.messages || [];
  session.history = session.history || [];
  session.messages.push({ role: 'user', content: userMessage, timestamp: now });

  // Set session name from first message if not set
  if (!session.name || session.name === 'Ny session') {
    session.name = userMessage.substring(0, 60);
  }

  updateCodeSession(sessionId, {
    status: 'working',
    liveStatus: { phase: 'thinking', tool: null, iter: 0, workersActive: 0, startedAt: new Date().toISOString() },
  });

  const systemPrompt = buildCodeAgentSystemPrompt(session, session.githubToken);
  const messages = [
    { role: 'system', content: systemPrompt },
    ...session.history,
    { role: 'user', content: userMessage },
  ];

  const toolCallsUsed = [];
  let finalResponse = '';
  let totalTokens = 0;
  // Track which free model is currently working (for chain fallback)
  let currentFreeModelIdx = 0;

  // Helper: call OpenRouter with free-chain fallback when model === 'free'
  async function callWithModel(msgs, tools) {
    if (!isFreeChain) {
      return await withRetry(() => callOpenRouter(msgs, session.model, tools), 3, 1500);
    }
    // Free model chain — try each model until one succeeds
    let lastError;
    for (let fi = currentFreeModelIdx; fi < FREE_MODEL_CHAIN.length; fi++) {
      const freeModel = FREE_MODEL_CHAIN[fi];
      try {
        updateCodeSession(sessionId, {
          liveStatus: { ...session.liveStatus, phase: `trying ${freeModel.split('/').pop().replace(':free', '')}` },
        });
        const result = await callOpenRouter(msgs, freeModel, tools);
        currentFreeModelIdx = fi; // stick with working model
        return result;
      } catch (e) {
        lastError = e;
        addLog('WARN', `Free model ${freeModel} misslyckades (code): ${e.message.substring(0, 80)}`);
        continue;
      }
    }
    throw lastError || new Error('Alla gratismodeller misslyckades');
  }

  try {
    for (let i = 0; i < maxIter; i++) {
      // Check stop flag
      if (codeSessions[sessionId] && codeSessions[sessionId].shouldStop) {
        finalResponse = 'Stoppad av användaren.';
        updateCodeSession(sessionId, {
          status: 'error',
          liveStatus: { phase: 'done', tool: null, iter: i },
        });
        session.messages.push({
          role: 'assistant',
          content: finalResponse,
          timestamp: new Date().toISOString(),
        });
        saveCodeSessions();
        return;
      }

      updateCodeSession(sessionId, {
        liveStatus: { phase: 'thinking', tool: null, iter: i, startedAt: session.liveStatus?.startedAt || new Date().toISOString() },
      });

      const result = await callWithModel(messages, codeAgentToolDefinitions());
      const choice = result.choices?.[0];
      if (!choice) break;

      const usage = result.usage || {};
      totalTokens += (usage.completion_tokens || 0) + (usage.prompt_tokens || 0);

      const msg = choice.message;
      messages.push(msg);

      if (msg.tool_calls && msg.tool_calls.length > 0) {
        // Show first tool label in live status
        const firstTc = msg.tool_calls[0];
        const firstTcName = firstTc.function?.name || 'unknown';
        updateCodeSession(sessionId, {
          liveStatus: {
            phase: 'executing',
            tool: msg.tool_calls.length > 1
              ? `${firstTcName} +${msg.tool_calls.length - 1} parallellt`
              : firstTcName,
            iter: i,
            startedAt: session.liveStatus?.startedAt || new Date().toISOString(),
          },
        });

        // Execute independent tool calls in parallel (significant speed-up for multi-tool turns)
        const toolResults = await Promise.all(msg.tool_calls.map(async (tc) => {
          const tcName = tc.function?.name || 'unknown';
          let tcArgs = {};
          try { tcArgs = JSON.parse(tc.function?.arguments || '{}'); } catch {}
          toolCallsUsed.push(tcName);
          const toolResult = await executeCodeTool(tcName, tcArgs, codeSessions[sessionId], session.githubToken);
          return { id: tc.id, content: toolResult };
        }));

        // Append results in same order as tool_calls (required by API spec)
        for (const { id, content } of toolResults) {
          messages.push({ role: 'tool', tool_call_id: id, content });
        }
        continue;
      }

      finalResponse = msg.content || '';
      if (finalResponse) break;
    }
  } catch (e) {
    addLog('CODE_ERROR', `Session ${sessionId}: ${e.message}`);
    finalResponse = `Fel: ${e.message}`;
    updateCodeSession(sessionId, {
      status: 'error',
      liveStatus: { phase: 'done', tool: null, iter: 0 },
    });
    session.messages.push({
      role: 'assistant',
      content: finalResponse,
      timestamp: new Date().toISOString(),
      toolCalls: toolCallsUsed,
      tokens: totalTokens,
    });
    // Update history
    session.history.push({ role: 'user', content: userMessage });
    session.history.push({ role: 'assistant', content: finalResponse });
    if (session.history.length > 40) session.history = session.history.slice(-40);
    saveCodeSessions();
    return;
  }

  // Finalize — model-aware cost calculation (price per 1M tokens, avg input+output)
  const MODEL_COSTS = {
    'minimax/minimax-m2.5':          0.30,
    'moonshotai/kimi-k2.5':          0.45,
    'openrouter-free-chain':         0.0,
    'qwen/qwen3-coder:free':         0.0,
    'deepseek/deepseek-chat-v3-0324:free': 0.0,
    'nvidia/nemotron-3-super-120b-a12b:free': 0.0,
    'google/gemini-2.5-flash:free':  0.0,
    'meta-llama/llama-4-maverick:free': 0.0,
    'qwen/qwen3-235b-a22b:free':     0.0,
    'meta-llama/llama-3.3-70b-instruct:free': 0.0,
    'mistralai/mistral-small-3.1-24b-instruct:free': 0.0,
    'deepseek/deepseek-r1:free':     0.0,
  };
  const costPerMTok = MODEL_COSTS[session.model] ?? 0.30;
  const estimatedCost = (totalTokens * costPerMTok) / 1_000_000;
  session.messages.push({
    role: 'assistant',
    content: finalResponse,
    timestamp: new Date().toISOString(),
    toolCalls: toolCallsUsed,
    tokens: totalTokens,
  });

  // Update conversation history (keep last 40)
  session.history.push({ role: 'user', content: userMessage });
  session.history.push({ role: 'assistant', content: finalResponse });
  if (session.history.length > 40) session.history = session.history.slice(-40);
  // Cap stored messages to avoid unbounded memory growth
  if (session.messages.length > 200) session.messages = session.messages.slice(-200);

  updateCodeSession(sessionId, {
    status: 'done',
    totalTokens: (session.totalTokens || 0) + totalTokens,
    totalCost: (session.totalCost || 0) + estimatedCost,
    liveStatus: { phase: 'done', tool: null, iter: 0 },
    shouldStop: false,
  });

  addLog('CODE', `Session ${sessionId} klar: ${finalResponse.substring(0, 80)} (${totalTokens} tok)`);

  // Send ntfy notification
  sendNtfyNotification(
    'Navi Code klar',
    `${finalResponse.substring(0, 80)}`,
    ['white_check_mark'],
    3
  );
}

// ============================================================
// CODE AGENT — Routes
// ============================================================

// GET /code/sessions — list all sessions
app.get('/code/sessions', auth, (req, res) => {
  const sessions_list = Object.values(codeSessions)
    .sort((a, b) => new Date(b.updatedAt || 0) - new Date(a.updatedAt || 0))
    .map(s => ({
      id: s.id,
      name: s.name,
      status: s.status,
      model: s.model,
      messageCount: (s.messages || []).length,
      totalTokens: s.totalTokens || 0,
      totalCost: s.totalCost || 0,
      createdAt: s.createdAt,
      updatedAt: s.updatedAt,
      liveStatus: s.liveStatus || {},
    }));
  res.json({ sessions: sessions_list });
});

// POST /code/sessions — create new session
app.post('/code/sessions', auth, (req, res) => {
  const { name, model, githubToken: bodyToken, githubRepo } = req.body;
  const githubToken = req.headers['x-github-token'] || bodyToken || null;
  const sessionId = uuidv4();
  const now = new Date().toISOString();
  const session = {
    id: sessionId,
    name: name || 'Ny session',
    status: 'idle',
    model: model || 'minimax/minimax-m2.5',
    messages: [],
    history: [],
    liveStatus: {},
    workers: [],
    todos: [],
    githubToken: githubToken || null,
    githubRepo: githubRepo || null,
    totalTokens: 0,
    totalCost: 0,
    createdAt: now,
    updatedAt: now,
    stoppedAt: null,
    shouldStop: false,
  };
  codeSessions[sessionId] = session;
  saveCodeSessions();
  addLog('CODE', `Ny session skapad: ${sessionId} (${name || 'Ny session'})`);
  res.json({ sessionId, name: session.name, status: 'idle', createdAt: now });
});

// GET /code/sessions/:id — get full session
app.get('/code/sessions/:id', auth, (req, res) => {
  const session = codeSessions[req.params.id];
  if (!session) return res.status(404).json({ error: 'Sessionen finns inte' });
  const sessionCopy = { ...session };
  // Return last 50 messages
  sessionCopy.messages = (session.messages || []).slice(-50);
  // Attach workers
  sessionCopy.workers = Object.values(codeWorkers[session.id] || {});
  res.json({ session: sessionCopy });
});

// DELETE /code/sessions/:id — delete session
app.delete('/code/sessions/:id', auth, (req, res) => {
  if (!codeSessions[req.params.id]) return res.status(404).json({ error: 'Sessionen finns inte' });
  delete codeSessions[req.params.id];
  delete codeWorkers[req.params.id];
  saveCodeSessions();
  res.json({ ok: true });
});

// POST /code/sessions/:id/message — send message
app.post('/code/sessions/:id/message', auth, (req, res) => {
  const session = codeSessions[req.params.id];
  if (!session) return res.status(404).json({ error: 'Sessionen finns inte' });
  if (session.status === 'working') {
    return res.status(400).json({ error: 'Agent kör redan' });
  }

  const { message, githubToken: bodyToken } = req.body;
  if (!message) return res.status(400).json({ error: 'Inget meddelande' });

  const githubToken = req.headers['x-github-token'] || bodyToken || session.githubToken || null;
  if (githubToken) session.githubToken = githubToken;
  session.shouldStop = false;

  updateCodeSession(req.params.id, { status: 'working', shouldStop: false });

  // Run in background
  codeReactLoop(req.params.id, message).catch(e => {
    addLog('CODE_ERROR', `codeReactLoop failure: ${e.message}`);
    updateCodeSession(req.params.id, { status: 'error' });
  });

  res.json({ ok: true, sessionId: req.params.id, status: 'working' });
});

// POST /code/sessions/:id/stop — stop agent
app.post('/code/sessions/:id/stop', auth, (req, res) => {
  if (!codeSessions[req.params.id]) return res.status(404).json({ error: 'Sessionen finns inte' });
  updateCodeSession(req.params.id, { shouldStop: true, stoppedAt: new Date().toISOString() });
  res.json({ ok: true });
});

// POST /code/sessions/:id/clear — clear history
app.post('/code/sessions/:id/clear', auth, (req, res) => {
  if (!codeSessions[req.params.id]) return res.status(404).json({ error: 'Sessionen finns inte' });
  updateCodeSession(req.params.id, { history: [], messages: [], todos: [] });
  res.json({ ok: true });
});

// GET /code/live — live status all sessions
app.get('/code/live', auth, (req, res) => {
  const live = {};
  for (const [id, s] of Object.entries(codeSessions)) {
    live[id] = {
      status: s.status,
      liveStatus: s.liveStatus || {},
      name: s.name,
      workers: Object.values(codeWorkers[id] || {}),
    };
  }
  res.json({ sessions: live });
});

// ============================================================
// START SERVER
// ============================================================

// Load persisted data before starting
loadCosts();
loadTasks();
loadSessions();
loadCodeSessions();
telephony.loadAll();

// Register telephony routes
telephony.register(app, auth, addLog);

// Telephony scheduler — check every 30 seconds
setInterval(() => telephony.runScheduler(addLog), 30000);

app.listen(PORT, '0.0.0.0', () => {
  addLog('BOOT', `Navi Brain v3.4 startad på port ${PORT}`);
  addLog('BOOT', `Modeller: MiniMax M2.5, Qwen3-Coder, DeepSeek R1, Claude Sonnet 4.6`);
  addLog('BOOT', `ntfy.sh topic: ${NTFY_TOPIC}`);
  addLog('BOOT', `Persistens: ${DATA_DIR}`);
  addLog('BOOT', `Navi Code v1.0 aktiverat — ${Object.keys(codeSessions).length} sparade kodsessioner`);
  console.log(`\nNavi Brain v3.4 running on port ${PORT}`);
  console.log(`   ntfy topic: ${NTFY_TOPIC}`);
  console.log(`   Models: MiniMax M2.5, Qwen3-Coder, DeepSeek R1, Claude Sonnet 4.6`);
  console.log(`   Navi Code v1.0 active`);
  console.log(`   Data dir: ${DATA_DIR}\n`);
});

// Graceful shutdown — save state
process.on('SIGTERM', () => {
  console.log('[SHUTDOWN] Saving state...');
  saveTasks();
  saveSessions();
  saveCosts();
  saveCodeSessions();
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('[SHUTDOWN] Saving state...');
  saveTasks();
  saveSessions();
  saveCosts();
  saveCodeSessions();
  process.exit(0);
});
