// ============================================================
// Navi Code Agent v2 — Server-side autonomous coding agent
// WebSocket streaming, persistent sessions, runs when iOS closes
// ============================================================
// Protocol (server → client):
//   CONNECTED, STATE_SNAPSHOT, RUN_STARTED, TEXT_DELTA, TEXT_COMMIT
//   TOOL_START, TOOL_RESULT, PHASE, TODO, GIT_COMMIT, ITERATION
//   RUN_FINISHED, RUN_ERROR, LINT_WARN, COMPACTING, PING
// Protocol (client → server):
//   SUBSCRIBE { sessionId, lastSeq }, START { task, model, openrouterKey, anthropicKey }
//   STOP, SEND { text }
// ============================================================

const fs    = require('fs');
const path  = require('path');
const https = require('https');
const http  = require('http');
const { exec, execFile, execSync } = require('child_process');
const { v4: uuidv4 } = require('uuid');

// ============================================================
// CONFIG (injected via init())
// ============================================================

let DATA_DIR = '/tmp/navi-code';
let DEFAULT_OPENROUTER_KEY = '';
let DEFAULT_ANTHROPIC_KEY  = '';

const SESSIONS_FILE = () => path.join(DATA_DIR, 'code-sessions.json');
const WORK_DIR      = () => path.join(DATA_DIR, 'workspaces');

// ============================================================
// MODELS — with per-model context window limits
// MiniMax M2.5:  1 000 000 token context (80.2% SWE-bench)
// Qwen3-Coder:     128 000 token context (free)
// DeepSeek-R1:     128 000 token context
// Claude Sonnet:   200 000 token context
// ============================================================

const MODELS = {
  minimax:  { id: 'minimax/minimax-m2.5',   contextLimit: 900000, maxTokens: 32768 },
  qwen:     { id: 'qwen/qwen3-coder:free',  contextLimit: 110000, maxTokens: 16384 },
  deepseek: { id: 'deepseek/deepseek-r1',   contextLimit: 110000, maxTokens: 16384 },
  claude:   { id: 'claude-sonnet-4-6',      contextLimit: 170000, maxTokens: 16384 },
};

// ============================================================
// ASYNC HELPERS
// ============================================================

function asyncExec(cmd, opts = {}) {
  return new Promise((resolve, reject) => {
    exec(cmd, { maxBuffer: 4 * 1024 * 1024, ...opts }, (err, stdout, stderr) => {
      if (err) {
        const e = new Error(err.message);
        e.stdout = stdout || '';
        e.stderr = stderr || '';
        e.code = err.code;
        reject(e);
      } else {
        resolve(stdout || '');
      }
    });
  });
}

function asyncExecFile(file, args, opts = {}) {
  return new Promise((resolve, reject) => {
    execFile(file, args, { maxBuffer: 4 * 1024 * 1024, ...opts }, (err, stdout, stderr) => {
      if (err) {
        const e = new Error(err.message);
        e.stdout = stdout || '';
        e.stderr = stderr || '';
        e.code = err.code;
        reject(e);
      } else {
        resolve(stdout || '');
      }
    });
  });
}

// ============================================================
// TOOLS
// ============================================================

const CODE_TOOLS = [
  {
    name: 'read_file',
    description: 'Read file contents with line numbers. Use start_line/end_line for large files.',
    parameters: {
      type: 'object',
      properties: {
        path:       { type: 'string',  description: 'Absolute or relative file path' },
        start_line: { type: 'integer', description: 'Start line (1-based, optional)' },
        end_line:   { type: 'integer', description: 'End line (1-based, optional)' },
      },
      required: ['path'],
    },
  },
  {
    name: 'write_file',
    description: 'Write content to a file. Creates parent directories if needed. Runs lint check after.',
    parameters: {
      type: 'object',
      properties: {
        path:    { type: 'string', description: 'File path' },
        content: { type: 'string', description: 'Complete file content' },
      },
      required: ['path', 'content'],
    },
  },
  {
    name: 'edit_file',
    description: 'Apply an exact search/replace edit. old_text MUST match verbatim — use read_file first to confirm exact content.',
    parameters: {
      type: 'object',
      properties: {
        path:     { type: 'string', description: 'File path' },
        old_text: { type: 'string', description: 'Exact text to find and replace (must exist verbatim in file)' },
        new_text: { type: 'string', description: 'Replacement text' },
      },
      required: ['path', 'old_text', 'new_text'],
    },
  },
  {
    name: 'run_command',
    description: 'Run a shell command asynchronously. Safe for long operations (npm install, cargo build, etc.). Default cwd is session workspace.',
    parameters: {
      type: 'object',
      properties: {
        command: { type: 'string',  description: 'Shell command to execute' },
        cwd:     { type: 'string',  description: 'Working directory (optional, default: session workspace)' },
        timeout: { type: 'integer', description: 'Timeout in seconds (default 120, max 600)' },
      },
      required: ['command'],
    },
  },
  {
    name: 'grep',
    description: 'Search file contents with a regex pattern. Returns matching lines with context.',
    parameters: {
      type: 'object',
      properties: {
        pattern:       { type: 'string',  description: 'Regex pattern to search for' },
        path:          { type: 'string',  description: 'File or directory to search in' },
        file_pattern:  { type: 'string',  description: 'Glob filter (e.g. "*.js", "*.py")' },
        context_lines: { type: 'integer', description: 'Lines of context around each match (default 2)' },
      },
      required: ['pattern', 'path'],
    },
  },
  {
    name: 'list_files',
    description: 'List files in a directory, optionally recursively (excludes node_modules, .git).',
    parameters: {
      type: 'object',
      properties: {
        path:      { type: 'string',  description: 'Directory path' },
        recursive: { type: 'boolean', description: 'Recurse into subdirectories (max depth 3)' },
      },
      required: ['path'],
    },
  },
  {
    name: 'todo_write',
    description: 'Update the agent TODO list. Call at task start and whenever the plan changes. Visible to user in real-time.',
    parameters: {
      type: 'object',
      properties: {
        todos: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              id:    { type: 'string'  },
              title: { type: 'string'  },
              done:  { type: 'boolean' },
            },
            required: ['id', 'title', 'done'],
          },
          description: 'Complete TODO list (replaces the current list)',
        },
      },
      required: ['todos'],
    },
  },
  {
    name: 'git_commit',
    description: 'Stage all changes and create a git commit. Returns commit hash. Use at meaningful milestones.',
    parameters: {
      type: 'object',
      properties: {
        message: { type: 'string', description: 'Commit message (concise, imperative mood)' },
        cwd:     { type: 'string', description: 'Git repository directory (default: session workspace)' },
      },
      required: ['message'],
    },
  },
  {
    name: 'web_search',
    description: 'Search the web for documentation, packages, error messages, or current information.',
    parameters: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Search query' },
      },
      required: ['query'],
    },
  },
  {
    name: 'fetch_url',
    description: 'Fetch content from a URL (HTML stripped to text, JSON returned raw). Use for docs, APIs, GitHub files, package registries.',
    parameters: {
      type: 'object',
      properties: {
        url:    { type: 'string', description: 'URL to fetch (http or https)' },
        method: { type: 'string', description: 'HTTP method (default: GET)' },
        body:   { type: 'string', description: 'Request body for POST/PUT (optional)' },
      },
      required: ['url'],
    },
  },
];

function toolsToOpenAI() {
  return CODE_TOOLS.map(t => ({
    type: 'function',
    function: { name: t.name, description: t.description, parameters: t.parameters },
  }));
}

function toolsToAnthropic() {
  return CODE_TOOLS.map(t => ({
    name: t.name,
    description: t.description,
    input_schema: t.parameters,
  }));
}

// ============================================================
// LINT GUARDRAILS
// ============================================================

function lintCheck(filePath, cwd) {
  const ext = path.extname(filePath).toLowerCase();
  try {
    let cmd;
    if (ext === '.js' || ext === '.mjs' || ext === '.cjs') {
      cmd = `node --check "${filePath}"`;
    } else if (ext === '.py') {
      cmd = `python3 -m py_compile "${filePath}" 2>&1 && echo OK`;
    } else if (ext === '.sh') {
      cmd = `bash -n "${filePath}"`;
    } else if (ext === '.json') {
      cmd = `node -e "JSON.parse(require('fs').readFileSync('${filePath}','utf8'))" 2>&1 && echo OK`;
    } else {
      return null; // no lint for this type
    }
    execSync(cmd, { cwd: cwd || '/', timeout: 5000, stdio: 'pipe' });
    return null; // OK
  } catch (e) {
    return (e.stderr || e.stdout || e.message || '').toString().substring(0, 500);
  }
}

// ============================================================
// TOOL EXECUTOR
// ============================================================

const TOOL_RESULT_LIMIT = 5000;

async function executeTool(name, args, session) {
  const workDir = session.workDir;
  const cwd = args.cwd || workDir;

  try {
    switch (name) {

      case 'read_file': {
        const fp = args.path;
        if (!fs.existsSync(fp)) return { result: `File not found: ${fp}`, isError: true };
        const lines = fs.readFileSync(fp, 'utf8').split('\n');
        const start = Math.max(0, (args.start_line || 1) - 1);
        const end   = args.end_line ? Math.min(lines.length, args.end_line) : lines.length;
        const slice = lines.slice(start, end);
        const numbered = slice.map((l, i) => `${start + i + 1}\t${l}`).join('\n');
        const result = numbered.substring(0, 20000);
        return {
          result: slice.length < lines.length
            ? `[Lines ${start+1}-${end} of ${lines.length}]\n${result}`
            : result,
          isError: false,
        };
      }

      case 'write_file': {
        const fp = args.path;
        const dir = path.dirname(fp);
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(fp, args.content || '', 'utf8');
        const lintErr = lintCheck(fp, workDir);
        if (lintErr) {
          session.emit({ type: 'LINT_WARN', path: fp, error: lintErr });
          return { result: `File written: ${fp}\n⚠️ Lint warning: ${lintErr}`, isError: false };
        }
        return { result: `File written: ${fp} (${(args.content || '').length} chars)`, isError: false };
      }

      case 'edit_file': {
        const fp = args.path;
        if (!fs.existsSync(fp)) return { result: `File not found: ${fp}`, isError: true };
        const original = fs.readFileSync(fp, 'utf8');
        const oldText = args.old_text || '';

        if (!original.includes(oldText)) {
          // Return first 30 lines to help the agent re-read and retry correctly
          const firstLines = original.split('\n').slice(0, 30).map((l, i) => `${i + 1}\t${l}`).join('\n');
          return {
            result: `Edit failed: old_text not found verbatim in ${fp}.\nUse read_file to get the exact current content, then retry.\n\nFirst 30 lines of file:\n${firstLines}`,
            isError: true,
          };
        }

        const updated = original.replace(oldText, args.new_text || '');
        fs.writeFileSync(fp, updated, 'utf8');
        const lintErr = lintCheck(fp, workDir);
        if (lintErr) session.emit({ type: 'LINT_WARN', path: fp, error: lintErr });
        return { result: `File edited: ${fp}`, isError: false };
      }

      case 'run_command': {
        // Async — does NOT block the Node.js event loop
        const timeoutMs = Math.min((args.timeout || 120), 600) * 1000;
        try {
          const output = await asyncExec(args.command, { cwd, timeout: timeoutMs });
          return { result: output.substring(0, 10000), isError: false };
        } catch (e) {
          const err = ((e.stderr || '') + (e.stdout || '') + e.message).substring(0, TOOL_RESULT_LIMIT);
          return { result: `Exit ${e.code ?? 1}: ${err}`, isError: true };
        }
      }

      case 'grep': {
        const ctxLines = args.context_lines ? `-C${args.context_lines}` : '-C2';
        const fileGlob = args.file_pattern ? `--include="${args.file_pattern}"` : '';
        const searchPath = args.path || workDir;
        const isDir = fs.existsSync(searchPath) && fs.statSync(searchPath).isDirectory();
        const rFlag = isDir ? '-r' : '';
        const cmd = `grep -n ${rFlag} ${ctxLines} ${fileGlob} "${args.pattern}" "${searchPath}" 2>/dev/null | head -100`;
        try {
          const output = execSync(cmd, { cwd, timeout: 10000, encoding: 'utf8' });
          return { result: output || '(no matches)', isError: false };
        } catch {
          return { result: '(no matches)', isError: false };
        }
      }

      case 'list_files': {
        const lsPath = args.path || workDir;
        if (!fs.existsSync(lsPath)) return { result: `Directory not found: ${lsPath}`, isError: true };
        if (args.recursive) {
          try {
            const out = execSync(
              `find "${lsPath}" -maxdepth 3 -not -path "*/node_modules/*" -not -path "*/.git/*" | sort | head -200`,
              { timeout: 8000, encoding: 'utf8' }
            );
            return { result: out, isError: false };
          } catch {
            return { result: fs.readdirSync(lsPath).join('\n'), isError: false };
          }
        }
        const entries = fs.readdirSync(lsPath, { withFileTypes: true });
        const lines = entries.map(e => `${e.isDirectory() ? 'd' : 'f'} ${e.name}`).join('\n');
        return { result: lines, isError: false };
      }

      case 'todo_write': {
        const todos = args.todos || [];
        session.todos = todos;
        session.emit({ type: 'TODO', todos });
        session.save();
        const summary = todos.map(t => `${t.done ? '✓' : '○'} ${t.title}`).join('\n');
        return { result: `TODO updated (${todos.length} items):\n${summary}`, isError: false };
      }

      case 'git_commit': {
        const gitCwd = args.cwd || workDir;
        try {
          await asyncExecFile('git', ['add', '-A'], { cwd: gitCwd, timeout: 10000 });
          const commitOut = await asyncExecFile(
            'git', ['commit', '-m', args.message || 'checkpoint'],
            { cwd: gitCwd, timeout: 15000 }
          );
          const hashMatch = commitOut.match(/\[.+\s+([a-f0-9]{7,})\]/);
          const hash = hashMatch ? hashMatch[1] : 'unknown';
          const diffStat = await asyncExecFile('git', ['diff', 'HEAD~1', '--stat'], { cwd: gitCwd, timeout: 5000 }).catch(() => '');
          const filesChanged = (diffStat.match(/\d+ file/) || [''])[0];
          const checkpoint = {
            hash,
            message: args.message || 'checkpoint',
            filesChanged,
            timestamp: new Date().toISOString(),
          };
          session.gitCheckpoints.push(checkpoint);
          session.emit({ type: 'GIT_COMMIT', ...checkpoint });
          session.save();
          return { result: `Committed: ${hash} — ${args.message}`, isError: false };
        } catch (e) {
          const msg = ((e.stderr || '') + e.message).substring(0, 500);
          if (msg.includes('nothing to commit')) {
            return { result: 'Nothing to commit', isError: false };
          }
          return { result: `Git error: ${msg}`, isError: true };
        }
      }

      case 'web_search': {
        const query = encodeURIComponent(args.query || '');
        const result = await new Promise((resolve) => {
          const req = https.request({
            hostname: 'api.duckduckgo.com',
            path: `/?q=${query}&format=json&no_html=1&skip_disambig=1`,
            method: 'GET',
            timeout: 10000,
            headers: { 'User-Agent': 'Navi-Code-Agent/2.0' },
          }, (res) => {
            let body = '';
            res.on('data', c => body += c);
            res.on('end', () => {
              try {
                const d = JSON.parse(body);
                const parts = [];
                if (d.AbstractText) {
                  parts.push(d.AbstractText);
                  if (d.AbstractURL) parts.push(`Source: ${d.AbstractURL}`);
                }
                const results = (d.RelatedTopics || [])
                  .filter(t => t.Text && t.FirstURL)
                  .slice(0, 8)
                  .map(t => `• ${t.Text}\n  ${t.FirstURL}`);
                if (results.length > 0) {
                  parts.push('\nRelated:\n' + results.join('\n'));
                }
                resolve(parts.join('\n\n') || 'No results found. Try a more specific query.');
              } catch { resolve('Search failed — could not parse response.'); }
            });
          });
          req.on('error', () => resolve('Search unavailable'));
          req.on('timeout', () => { req.destroy(); resolve('Search timed out'); });
          req.end();
        });
        return { result, isError: false };
      }

      case 'fetch_url': {
        const urlStr = args.url;
        if (!urlStr) return { result: 'url is required', isError: true };

        const result = await (async () => {
          let currentUrl = urlStr;
          let redirects = 0;

          while (redirects < 3) {
            const urlObj = (() => { try { return new URL(currentUrl); } catch { return null; } })();
            if (!urlObj) return { text: `Invalid URL: ${currentUrl}`, error: true };

            const lib = urlObj.protocol === 'https:' ? https : http;
            const response = await new Promise((resolve) => {
              const reqOpts = {
                hostname: urlObj.hostname,
                port: urlObj.port || (urlObj.protocol === 'https:' ? 443 : 80),
                path: urlObj.pathname + (urlObj.search || ''),
                method: args.method || 'GET',
                headers: {
                  'User-Agent': 'Mozilla/5.0 (Navi-Code-Agent/2.0)',
                  'Accept': 'text/html,application/json,text/plain,*/*',
                },
                timeout: 15000,
              };

              const req = lib.request(reqOpts, (res) => {
                if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location) {
                  res.resume();
                  resolve({ redirect: res.headers.location });
                  return;
                }
                let body = '';
                res.on('data', c => { if (body.length < 500000) body += c; });
                res.on('end', () => {
                  const ct = res.headers['content-type'] || '';
                  if (ct.includes('application/json')) {
                    resolve({ text: body.substring(0, 20000) });
                  } else {
                    const text = body
                      .replace(/<script[\s\S]*?<\/script>/gi, '')
                      .replace(/<style[\s\S]*?<\/style>/gi, '')
                      .replace(/<[^>]+>/g, ' ')
                      .replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
                      .replace(/\s{3,}/g, '\n\n')
                      .trim();
                    resolve({ text: text.substring(0, 20000) });
                  }
                });
              });

              if (args.body && args.method && args.method !== 'GET') req.write(args.body);
              req.on('error', (e) => resolve({ text: `Network error: ${e.message}`, error: true }));
              req.on('timeout', () => { req.destroy(); resolve({ text: 'Request timed out', error: true }); });
              req.end();
            });

            if (response.redirect) {
              currentUrl = response.redirect.startsWith('http') ? response.redirect : new URL(response.redirect, currentUrl).href;
              redirects++;
              continue;
            }
            return response;
          }
          return { text: 'Too many redirects', error: true };
        })();

        if (result.error) return { result: result.text, isError: true };
        return { result: result.text || '(empty response)', isError: false };
      }

      default:
        return { result: `Unknown tool: ${name}`, isError: true };
    }
  } catch (e) {
    return { result: `Tool error: ${e.message}`, isError: true };
  }
}

// ============================================================
// SESSION
// ============================================================

class CodeSession {
  constructor(id, task, model) {
    this.id          = id;
    this.task        = task;         // current task (updated on SEND)
    this.initialTask = task;         // original task (preserved for system prompt context)
    this.model       = model;
    this.status      = 'idle';       // idle | running | done | error | stopped
    this.messages    = [];           // LLM conversation history
    this.events      = [];           // all emitted events (for replay)
    this.todos       = [];
    this.gitCheckpoints = [];
    this.workDir     = path.join(WORK_DIR(), id);
    this.createdAt   = new Date().toISOString();
    this.updatedAt   = new Date().toISOString();
    this.openrouterKey = '';
    this.anthropicKey  = '';
    this._ws      = null;
    this._stopped = false;
    this._seq     = 0;

    if (!fs.existsSync(this.workDir)) {
      fs.mkdirSync(this.workDir, { recursive: true });
    }
  }

  emit(event) {
    event.seq = this._seq++;
    event.ts  = Date.now();
    this.events.push(event);
    if (this.events.length > 1000) this.events.splice(0, this.events.length - 1000);
    if (this._ws && this._ws.readyState === 1) {
      try { this._ws.send(JSON.stringify(event)); } catch {}
    }
    this.updatedAt = new Date().toISOString();
  }

  replayFrom(ws, fromSeq) {
    const missed = this.events.filter(e => e.seq >= fromSeq);
    for (const ev of missed) {
      try { ws.send(JSON.stringify(ev)); } catch {}
    }
  }

  save() {
    this.updatedAt = new Date().toISOString();
    try {
      const all = loadAllSessions();
      all[this.id] = this.toJSON();
      fs.writeFileSync(SESSIONS_FILE(), JSON.stringify(all, null, 2), 'utf8');
    } catch {}
  }

  toJSON() {
    return {
      id:          this.id,
      task:        this.task,
      initialTask: this.initialTask,
      model:       this.model,
      status:      this.status,
      messages:    this.messages.slice(-40),
      events:      this.events.slice(-200),
      todos:       this.todos,
      gitCheckpoints: this.gitCheckpoints,
      workDir:     this.workDir,
      createdAt:   this.createdAt,
      updatedAt:   this.updatedAt,
    };
  }

  static fromJSON(data) {
    const s = new CodeSession(data.id, data.task, data.model);
    s.initialTask    = data.initialTask || data.task;
    s.status         = data.status      || 'idle';
    s.messages       = data.messages    || [];
    s.events         = data.events      || [];
    s.todos          = data.todos       || [];
    s.gitCheckpoints = data.gitCheckpoints || [];
    s.workDir        = data.workDir     || s.workDir;
    s.createdAt      = data.createdAt   || s.createdAt;
    s.updatedAt      = data.updatedAt   || s.updatedAt;
    // Restore _seq to one past the highest seq in persisted events
    s._seq = s.events.reduce((m, e) => Math.max(m, (e.seq ?? 0) + 1), 0);
    return s;
  }
}

// In-memory session store
const codeSessions = {};

function loadAllSessions() {
  try {
    if (!fs.existsSync(SESSIONS_FILE())) return {};
    return JSON.parse(fs.readFileSync(SESSIONS_FILE(), 'utf8'));
  } catch { return {}; }
}

function loadSessions() {
  try {
    const all = loadAllSessions();
    for (const [id, data] of Object.entries(all)) {
      const s = CodeSession.fromJSON(data);
      if (s.status === 'running') {
        s.status = 'error';
        s.emit({ type: 'RUN_ERROR', error: 'Server restarted during execution' });
      }
      codeSessions[id] = s;
    }
    console.log(`[CODE-AGENT] Loaded ${Object.keys(codeSessions).length} sessions`);
  } catch (e) {
    console.error('[CODE-AGENT] Failed to load sessions:', e.message);
  }
}

// ============================================================
// OPENROUTER STREAMING
// ============================================================

function streamOpenRouter(messages, modelInfo, tools, openrouterKey, onDelta, signal) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model: modelInfo.id,
      messages,
      tools: tools.length > 0 ? toolsToOpenAI() : undefined,
      tool_choice: tools.length > 0 ? 'auto' : undefined,
      stream: true,
      max_tokens: modelInfo.maxTokens,
      temperature: 0.7,
    });

    const req = https.request({
      hostname: 'openrouter.ai',
      path: '/api/v1/chat/completions',
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openrouterKey}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://navi.app',
        'X-Title': 'Navi Code Agent',
        'Content-Length': Buffer.byteLength(body),
      },
      timeout: 300000,
    }, (res) => {
      let buffer = '';
      let fullText = '';
      let toolCallMap = {};
      let stopReason = null;

      res.on('data', chunk => {
        if (signal?.aborted) { req.destroy(); return; }
        buffer += chunk.toString();
        const lines = buffer.split('\n');
        buffer = lines.pop();

        for (const line of lines) {
          if (!line.startsWith('data: ')) continue;
          const raw = line.slice(6).trim();
          if (raw === '[DONE]') continue;
          try {
            const json = JSON.parse(raw);
            const choice = json.choices?.[0];
            if (!choice) continue;
            const delta = choice.delta || {};

            if (delta.content) {
              fullText += delta.content;
              onDelta(delta.content);
            }

            if (delta.tool_calls) {
              for (const tc of delta.tool_calls) {
                const idx = tc.index ?? 0;
                if (!toolCallMap[idx]) {
                  toolCallMap[idx] = { id: tc.id || '', name: tc.function?.name || '', argsStr: '' };
                }
                if (tc.id) toolCallMap[idx].id = tc.id;
                if (tc.function?.name) toolCallMap[idx].name = tc.function.name;
                if (tc.function?.arguments) toolCallMap[idx].argsStr += tc.function.arguments;
              }
            }

            if (choice.finish_reason) stopReason = choice.finish_reason;
          } catch {}
        }
      });

      res.on('end', () => {
        const toolCalls = Object.values(toolCallMap).map(tc => {
          let args = {};
          try { args = JSON.parse(tc.argsStr); } catch {}
          return { id: tc.id, name: tc.name, args };
        });
        resolve({ fullText, toolCalls, stopReason });
      });

      res.on('error', reject);
    });

    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('OpenRouter timeout')); });
    req.write(body);
    req.end();
  });
}

// ============================================================
// ANTHROPIC STREAMING
// ============================================================

function streamAnthropic(messages, anthropicKey, systemPrompt, modelInfo, onDelta, signal) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model: modelInfo.id,
      max_tokens: modelInfo.maxTokens,
      system: systemPrompt,
      messages,
      tools: toolsToAnthropic(),
      stream: true,
    });

    const req = https.request({
      hostname: 'api.anthropic.com',
      path: '/v1/messages',
      method: 'POST',
      headers: {
        'x-api-key': anthropicKey,
        'anthropic-version': '2023-06-01',
        'anthropic-beta': 'prompt-caching-2024-07-31',
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
      timeout: 300000,
    }, (res) => {
      let buffer = '';
      let fullText = '';
      let toolUses = {};
      let stopReason = null;
      let currentBlockIdx = null;
      let currentBlockType = null;

      res.on('data', chunk => {
        if (signal?.aborted) { req.destroy(); return; }
        buffer += chunk.toString();
        const lines = buffer.split('\n');
        buffer = lines.pop();

        for (const line of lines) {
          if (!line.startsWith('data: ')) continue;
          try {
            const ev = JSON.parse(line.slice(6));
            if (ev.type === 'content_block_start') {
              currentBlockIdx = ev.index;
              currentBlockType = ev.content_block?.type;
              if (currentBlockType === 'tool_use') {
                toolUses[ev.index] = { id: ev.content_block.id, name: ev.content_block.name, inputStr: '' };
              }
            } else if (ev.type === 'content_block_delta') {
              const d = ev.delta;
              if (d.type === 'text_delta') {
                fullText += d.text;
                onDelta(d.text);
              } else if (d.type === 'input_json_delta' && toolUses[currentBlockIdx]) {
                toolUses[currentBlockIdx].inputStr += d.partial_json;
              }
            } else if (ev.type === 'message_delta') {
              stopReason = ev.delta?.stop_reason || stopReason;
            }
          } catch {}
        }
      });

      res.on('end', () => {
        const toolCalls = Object.values(toolUses).map(tu => {
          let args = {};
          try { args = JSON.parse(tu.inputStr); } catch {}
          return { id: tu.id, name: tu.name, args };
        });
        resolve({ fullText, toolCalls, stopReason });
      });

      res.on('error', reject);
    });

    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('Anthropic timeout')); });
    req.write(body);
    req.end();
  });
}

// ============================================================
// SYSTEM PROMPT
// ============================================================

function buildSystemPrompt(session) {
  const modelInfo = MODELS[session.model] || MODELS.minimax;
  return `You are Navi — an autonomous AI coding agent running on a dedicated Ubuntu Linux server (Navi Brain).

## Working directory
${session.workDir}

## Original task
${session.initialTask}

## Autonomous working method (ReAct loop)

Think step by step before every action. Follow this cycle:

1. **THINK** — What does the task require? What do I know vs what do I need to discover?
2. **PLAN** — Break into concrete steps. Call \`todo_write\` immediately to track the plan.
3. **ACT** — Use tools actively. Read files before editing. Run commands to build/test.
4. **OBSERVE** — Carefully analyze tool results. Check for errors. Did it work?
5. **ADAPT** — If something failed, understand why and try a different approach.
6. **REPEAT** — Continue until the task is fully done, tested, and working.

## Rules
- Always \`read_file\` before editing — never assume file contents
- Call \`todo_write\` at the start of every non-trivial task
- Write production-quality code — no stubs, no placeholders, no incomplete implementations
- If \`edit_file\` fails with "not found": use \`read_file\` to get exact current text, then retry
- Call \`git_commit\` after completing meaningful milestones
- Run tests/verify with \`run_command\` — do not claim success without verification
- If stuck, search the web or fetch docs — you have full internet access
- Never give up — always find a path forward

## Communication
Think aloud at key decision points. Be concise in updates.
Use markdown: **bold** for key info, \`code\` for paths/commands, fenced blocks for code.
When done, summarize what was built and how to run/use it.

## Environment — full server access, no restrictions
- Platform: Ubuntu Linux
- Internet: Yes — \`fetch_url\` for docs/APIs/GitHub, \`web_search\` for finding information
- Git: Available globally
- Package managers: npm, pip3, cargo, apt (use run_command)
- Full filesystem read/write/execute access
- Context window: ${(modelInfo.contextLimit).toLocaleString()} tokens (model: ${session.model}, max output: ${modelInfo.maxTokens.toLocaleString()} tokens)`;
}

// ============================================================
// CONTEXT COMPACTION
// ============================================================

function estimateTokens(messages) {
  return messages.reduce((sum, m) => {
    const content = typeof m.content === 'string' ? m.content : JSON.stringify(m.content);
    return sum + Math.ceil(content.length / 3.5);
  }, 0);
}

function serializeContent(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content.map(block => {
      if (block.type === 'text')        return block.text || '';
      if (block.type === 'tool_use')    return `[tool: ${block.name}(${JSON.stringify(block.input || {}).substring(0, 200)})]`;
      if (block.type === 'tool_result') return `[result: ${JSON.stringify(block.content).substring(0, 200)}]`;
      return JSON.stringify(block).substring(0, 200);
    }).join('\n');
  }
  return JSON.stringify(content).substring(0, 500);
}

async function compactContext(session) {
  const messages = session.messages;
  if (messages.length < 10) return;

  session.emit({ type: 'COMPACTING', reason: 'Context window approaching limit' });

  const head = messages.slice(0, 2);
  const tail = messages.slice(-8);
  const middle = messages.slice(2, -8);

  if (middle.length === 0) return;

  // Serialize ALL message types — including tool_use and tool_result blocks
  const summaryText = middle
    .map(m => `[${m.role}]: ${serializeContent(m.content).substring(0, 400)}`)
    .join('\n');

  session.messages = [
    ...head,
    {
      role: 'user',
      content: `[Context compacted — ${middle.length} prior messages summarized]\n${summaryText.substring(0, 4000)}`,
    },
    {
      role: 'assistant',
      content: 'Understood. I have reviewed the prior work summary and will continue from where we left off.',
    },
    ...tail,
  ];
}

// ============================================================
// MAIN AGENT LOOP
// ============================================================

async function runCodeAgent(session) {
  session.status = 'running';
  session._stopped = false;
  session.save();

  const abortCtrl = { aborted: false };
  session._abort = abortCtrl;

  session.emit({ type: 'RUN_STARTED', task: session.task, model: session.model, timestamp: new Date().toISOString() });
  session.emit({ type: 'PHASE', phase: 'thinking', label: 'Thinking…' });

  // Initial user message
  if (session.messages.length === 0) {
    session.messages.push({ role: 'user', content: session.task });
  }

  const isAnthropic = session.model === 'claude';
  const key = isAnthropic
    ? (session.anthropicKey || DEFAULT_ANTHROPIC_KEY)
    : (session.openrouterKey || DEFAULT_OPENROUTER_KEY);

  if (!key) {
    session.status = 'error';
    session.emit({ type: 'RUN_ERROR', error: 'No API key configured for this model' });
    session.save();
    return;
  }

  const modelInfo = MODELS[session.model] || MODELS.minimax;
  const systemPrompt = buildSystemPrompt(session);
  // Compact at 85% of context limit — leaves room for the model's output
  const compactAt = Math.floor(modelInfo.contextLimit * 0.85);
  const MAX_ITER = 40;
  let doomCounter = 0;
  let lastToolNames = '';

  try {
    for (let iter = 0; iter < MAX_ITER; iter++) {
      if (abortCtrl.aborted || session._stopped) break;

      session.emit({ type: 'ITERATION', n: iter + 1, maxN: MAX_ITER });
      session.emit({
        type: 'PHASE',
        phase: 'thinking',
        label: iter === 0 ? 'Thinking…' : `Thinking… (step ${iter + 1})`,
      });

      // Model-aware context compaction
      if (estimateTokens(session.messages) > compactAt) {
        await compactContext(session);
      }

      let streamResult;

      if (isAnthropic) {
        streamResult = await streamAnthropic(
          session.messages,
          key,
          systemPrompt,
          modelInfo,
          (delta) => session.emit({ type: 'TEXT_DELTA', delta }),
          abortCtrl
        );
        const assistantContent = [];
        if (streamResult.fullText) assistantContent.push({ type: 'text', text: streamResult.fullText });
        for (const tc of streamResult.toolCalls) {
          assistantContent.push({ type: 'tool_use', id: tc.id, name: tc.name, input: tc.args });
        }
        session.messages.push({ role: 'assistant', content: assistantContent });
      } else {
        const msgs = [
          { role: 'system', content: systemPrompt },
          ...session.messages,
        ];
        streamResult = await streamOpenRouter(
          msgs, modelInfo, CODE_TOOLS, key,
          (delta) => session.emit({ type: 'TEXT_DELTA', delta }),
          abortCtrl
        );
        const assistantMsg = { role: 'assistant', content: streamResult.fullText || '' };
        if (streamResult.toolCalls.length > 0) {
          assistantMsg.tool_calls = streamResult.toolCalls.map(tc => ({
            id: tc.id,
            type: 'function',
            function: { name: tc.name, arguments: JSON.stringify(tc.args) },
          }));
        }
        session.messages.push(assistantMsg);
      }

      // Commit text block to UI
      if (streamResult.fullText?.trim()) {
        session.emit({ type: 'TEXT_COMMIT', text: streamResult.fullText });
      }

      // No tool calls → task complete
      const { toolCalls, stopReason } = streamResult;
      if (toolCalls.length === 0 || stopReason === 'stop' || stopReason === 'end_turn') {
        session.emit({ type: 'PHASE', phase: 'done', label: 'Done' });
        break;
      }

      // Doom loop detection — same tools 3× in a row
      const toolNames = toolCalls.map(t => t.name).sort().join(',');
      if (toolNames === lastToolNames) {
        doomCounter++;
        if (doomCounter >= 3) {
          session.messages.push({
            role: 'user',
            content: 'You are repeating the same actions without progress. Stop and take a completely different approach, or explain clearly what is blocking you and what you have accomplished so far.',
          });
          doomCounter = 0;
        }
      } else {
        doomCounter = 0;
        lastToolNames = toolNames;
      }

      // Execute tools
      session.emit({
        type: 'PHASE',
        phase: 'tools',
        label: `Running ${toolCalls.length} tool${toolCalls.length > 1 ? 's' : ''}…`,
      });

      const toolResults = [];

      for (const tc of toolCalls) {
        if (abortCtrl.aborted || session._stopped) break;

        const startMs = Date.now();
        session.emit({ type: 'TOOL_START', toolId: tc.id, name: tc.name, params: tc.args });

        const { result, isError } = await executeTool(tc.name, tc.args, session);
        const durationMs = Date.now() - startMs;

        session.emit({
          type: 'TOOL_RESULT',
          toolId: tc.id,
          name: tc.name,
          result: result.substring(0, TOOL_RESULT_LIMIT),
          isError,
          durationMs,
        });

        if (isAnthropic) {
          toolResults.push({ type: 'tool_result', tool_use_id: tc.id, content: result });
        } else {
          toolResults.push({ role: 'tool', tool_call_id: tc.id, content: result });
        }
      }

      // Add tool results to conversation history
      if (isAnthropic) {
        session.messages.push({ role: 'user', content: toolResults });
      } else {
        for (const tr of toolResults) {
          session.messages.push(tr);
        }
      }

      session.save();
    }

    if (!abortCtrl.aborted && !session._stopped) {
      session.status = 'done';
      session.emit({
        type: 'RUN_FINISHED',
        summary: session.todos.length > 0
          ? `${session.todos.filter(t => t.done).length}/${session.todos.length} tasks completed`
          : 'Completed',
      });
    } else {
      session.status = 'stopped';
      session.emit({ type: 'RUN_ERROR', error: 'Stopped by user' });
    }

  } catch (err) {
    session.status = 'error';
    session.emit({ type: 'RUN_ERROR', error: err.message });
    console.error('[CODE-AGENT] Agent error:', err.message);
  }

  session._abort = null;
  session.save();
}

// ============================================================
// WEBSOCKET HANDLER
// ============================================================

function handleWebSocket(ws, req) {
  let session = null;
  let pingInterval = null;

  function sendRaw(obj) {
    try { ws.send(JSON.stringify(obj)); } catch {}
  }

  // Keepalive heartbeat
  pingInterval = setInterval(() => {
    if (ws.readyState === 1) sendRaw({ type: 'PING', ts: Date.now() });
  }, 20000);

  ws.on('message', async (rawMsg) => {
    let msg;
    try { msg = JSON.parse(rawMsg.toString()); } catch { return; }

    switch (msg.type) {

      case 'SUBSCRIBE': {
        const s = codeSessions[msg.sessionId];
        if (!s) {
          sendRaw({ type: 'ERROR', error: 'Session not found' });
          return;
        }
        session = s;
        session._ws = ws;
        sendRaw({ type: 'CONNECTED', sessionId: s.id, hasHistory: s.messages.length > 0 });
        sendRaw({
          type: 'STATE_SNAPSHOT',
          status: s.status,
          todos: s.todos,
          gitCheckpoints: s.gitCheckpoints,
          task: s.task,
          model: s.model,
          createdAt: s.createdAt,
        });
        // parseInt handles both Number and String lastSeq from iOS (fixes the String bug)
        const lastSeq = parseInt(msg.lastSeq, 10) || 0;
        s.replayFrom(ws, lastSeq);
        break;
      }

      case 'START': {
        const id = uuidv4();
        const s = new CodeSession(id, msg.task || '', msg.model || 'minimax');
        s.openrouterKey = msg.openrouterKey || DEFAULT_OPENROUTER_KEY;
        s.anthropicKey  = msg.anthropicKey  || DEFAULT_ANTHROPIC_KEY;
        s._ws = ws;
        session = s;
        codeSessions[id] = s;
        sendRaw({ type: 'CONNECTED', sessionId: id, hasHistory: false });
        s.save();
        runCodeAgent(s).catch(e => {
          console.error('[CODE-AGENT] Unhandled:', e.message);
        });
        break;
      }

      case 'SEND': {
        if (!session) { sendRaw({ type: 'ERROR', error: 'No active session' }); return; }
        if (session.status === 'running') { sendRaw({ type: 'ERROR', error: 'Agent is already running' }); return; }
        session.messages.push({ role: 'user', content: msg.text || '' });
        // Update current task but preserve initialTask in system prompt
        session.task = msg.text || session.task;
        session._ws = ws;
        runCodeAgent(session).catch(() => {});
        break;
      }

      case 'STOP': {
        if (session) {
          session._stopped = true;
          if (session._abort) session._abort.aborted = true;
        }
        break;
      }

      case 'PONG': break;

      default:
        sendRaw({ type: 'ERROR', error: `Unknown message type: ${msg.type}` });
    }
  });

  ws.on('close', () => {
    clearInterval(pingInterval);
    if (session && session._ws === ws) session._ws = null;
  });

  ws.on('error', () => {
    clearInterval(pingInterval);
    if (session && session._ws === ws) session._ws = null;
  });
}

// ============================================================
// EXPRESS ROUTER
// ============================================================

function createRouter(express) {
  const router = express.Router();

  // POST /code/start — REST fallback (no WebSocket)
  router.post('/start', (req, res) => {
    const { task, model, openrouterKey, anthropicKey } = req.body;
    if (!task) return res.status(400).json({ error: 'task required' });

    const id = uuidv4();
    const s = new CodeSession(id, task, model || 'minimax');
    s.openrouterKey = openrouterKey || req.headers['x-openrouter-key'] || DEFAULT_OPENROUTER_KEY;
    s.anthropicKey  = anthropicKey  || req.headers['x-anthropic-key']  || DEFAULT_ANTHROPIC_KEY;
    codeSessions[id] = s;
    s.save();
    runCodeAgent(s).catch(() => {});
    res.json({ sessionId: id, workDir: s.workDir, status: 'started' });
  });

  // GET /code/sessions — list all sessions
  router.get('/sessions', (req, res) => {
    const list = Object.values(codeSessions).map(s => ({
      id: s.id,
      task: s.task.substring(0, 100),
      model: s.model,
      status: s.status,
      createdAt: s.createdAt,
      updatedAt: s.updatedAt,
      todos: s.todos,
      gitCheckpoints: s.gitCheckpoints.length,
    }));
    res.json({ sessions: list.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)) });
  });

  // GET /code/session/:id — full session state
  router.get('/session/:id', (req, res) => {
    const s = codeSessions[req.params.id];
    if (!s) return res.status(404).json({ error: 'Session not found' });
    res.json(s.toJSON());
  });

  // POST /code/stop/:id
  router.post('/stop/:id', (req, res) => {
    const s = codeSessions[req.params.id];
    if (!s) return res.status(404).json({ error: 'Session not found' });
    s._stopped = true;
    if (s._abort) s._abort.aborted = true;
    res.json({ ok: true });
  });

  // DELETE /code/session/:id
  router.delete('/session/:id', (req, res) => {
    const s = codeSessions[req.params.id];
    if (s) {
      s._stopped = true;
      delete codeSessions[s.id];
    }
    res.json({ ok: true });
  });

  // GET /code/models — model info with context limits
  router.get('/models', (req, res) => {
    res.json({ models: MODELS });
  });

  return router;
}

// ============================================================
// INIT
// ============================================================

function init(wss, config = {}) {
  DATA_DIR               = config.dataDir      || DATA_DIR;
  DEFAULT_OPENROUTER_KEY = config.openrouterKey || '';
  DEFAULT_ANTHROPIC_KEY  = config.anthropicKey  || '';

  if (!fs.existsSync(DATA_DIR))   fs.mkdirSync(DATA_DIR,   { recursive: true });
  if (!fs.existsSync(WORK_DIR())) fs.mkdirSync(WORK_DIR(), { recursive: true });

  loadSessions();
  wss.on('connection', handleWebSocket);

  // Periodic save every 30 seconds
  setInterval(() => {
    for (const s of Object.values(codeSessions)) s.save();
  }, 30000);

  console.log('[CODE-AGENT] v2 initialized — sessions:', Object.keys(codeSessions).length);
  console.log('[CODE-AGENT] Models:', Object.entries(MODELS)
    .map(([k, v]) => `${k} (${v.contextLimit.toLocaleString()} ctx)`)
    .join(', '));
}

module.exports = { init, createRouter, codeSessions, MODELS };
