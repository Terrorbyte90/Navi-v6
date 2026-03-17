// ============================================================
// Navi Code Agent — Server-side autonomous coding agent
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

const fs   = require('fs');
const path = require('path');
const https = require('https');
const http  = require('http');
const { execSync } = require('child_process');
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
// MODELS
// ============================================================

const MODELS = {
  minimax: 'minimax/minimax-m2.5',
  qwen:    'qwen/qwen3-coder:free',
  deepseek:'deepseek/deepseek-r1',
  claude:  'claude-sonnet-4-6',
};

// ============================================================
// TOOLS
// ============================================================

const CODE_TOOLS = [
  {
    name: 'read_file',
    description: 'Read file contents. Optionally specify start_line/end_line for large files.',
    parameters: {
      type: 'object',
      properties: {
        path:       { type: 'string',  description: 'File path' },
        start_line: { type: 'integer', description: 'Start line (1-based, optional)' },
        end_line:   { type: 'integer', description: 'End line (1-based, optional)' },
      },
      required: ['path'],
    },
  },
  {
    name: 'write_file',
    description: 'Write content to a file. Creates parent dirs if needed. Runs lint check after write.',
    parameters: {
      type: 'object',
      properties: {
        path:    { type: 'string', description: 'File path' },
        content: { type: 'string', description: 'File content' },
      },
      required: ['path', 'content'],
    },
  },
  {
    name: 'edit_file',
    description: 'Apply a search/replace edit. old_text must exactly match content in file.',
    parameters: {
      type: 'object',
      properties: {
        path:     { type: 'string', description: 'File path' },
        old_text: { type: 'string', description: 'Exact text to replace' },
        new_text: { type: 'string', description: 'Replacement text' },
      },
      required: ['path', 'old_text', 'new_text'],
    },
  },
  {
    name: 'run_command',
    description: 'Run a shell command. Returns stdout+stderr. Default cwd is session workspace.',
    parameters: {
      type: 'object',
      properties: {
        command: { type: 'string',  description: 'Shell command' },
        cwd:     { type: 'string',  description: 'Working directory (optional)' },
        timeout: { type: 'integer', description: 'Timeout seconds (default 30)' },
      },
      required: ['command'],
    },
  },
  {
    name: 'grep',
    description: 'Search file contents with a regex pattern.',
    parameters: {
      type: 'object',
      properties: {
        pattern:      { type: 'string',  description: 'Regex pattern' },
        path:         { type: 'string',  description: 'File or directory to search' },
        file_pattern: { type: 'string',  description: 'Glob filter (e.g. "*.js")' },
        context_lines:{ type: 'integer', description: 'Context lines around each match' },
      },
      required: ['pattern', 'path'],
    },
  },
  {
    name: 'list_files',
    description: 'List files in a directory.',
    parameters: {
      type: 'object',
      properties: {
        path:      { type: 'string',  description: 'Directory path' },
        recursive: { type: 'boolean', description: 'List recursively (max depth 3)' },
      },
      required: ['path'],
    },
  },
  {
    name: 'todo_write',
    description: 'Update the agent TODO list. Call this to track your plan and progress.',
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
          description: 'Complete current TODO list',
        },
      },
      required: ['todos'],
    },
  },
  {
    name: 'git_commit',
    description: 'Stage all changes and create a git commit. Returns commit hash.',
    parameters: {
      type: 'object',
      properties: {
        message: { type: 'string', description: 'Commit message' },
        cwd:     { type: 'string', description: 'Repo directory (default: session workspace)' },
      },
      required: ['message'],
    },
  },
  {
    name: 'web_search',
    description: 'Search the web. Returns DuckDuckGo instant answer + top results.',
    parameters: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Search query' },
      },
      required: ['query'],
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
        return { result: slice.length < lines.length
          ? `[Lines ${start+1}-${end} of ${lines.length}]\n${result}`
          : result, isError: false };
      }

      case 'write_file': {
        const fp = args.path;
        const dir = path.dirname(fp);
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(fp, args.content || '', 'utf8');

        // Lint guardrail
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
          // Fuzzy: try trimmed whitespace match
          const normalOrig = original.replace(/[ \t]+/g, ' ');
          const normalOld  = oldText.replace(/[ \t]+/g, ' ');
          if (normalOrig.includes(normalOld)) {
            const updated = normalOrig.replace(normalOld, args.new_text || '');
            fs.writeFileSync(fp, updated, 'utf8');
            const lintErr = lintCheck(fp, workDir);
            if (lintErr) session.emit({ type: 'LINT_WARN', path: fp, error: lintErr });
            return { result: `File edited: ${fp} (whitespace-fuzzy match)`, isError: false };
          }
          return { result: `Edit failed: old_text not found in ${fp}.\nFirst 200 chars of file:\n${original.substring(0,200)}`, isError: true };
        }
        const updated = original.replace(oldText, args.new_text || '');
        fs.writeFileSync(fp, updated, 'utf8');
        const lintErr = lintCheck(fp, workDir);
        if (lintErr) session.emit({ type: 'LINT_WARN', path: fp, error: lintErr });
        return { result: `File edited: ${fp}`, isError: false };
      }

      case 'run_command': {
        const timeout = (args.timeout || 30) * 1000;
        try {
          const output = execSync(args.command, {
            cwd,
            timeout,
            maxBuffer: 2 * 1024 * 1024,
            encoding: 'utf8',
          });
          return { result: output.substring(0, 10000), isError: false };
        } catch (e) {
          const err = ((e.stderr || '') + (e.stdout || '') + (e.message || '')).substring(0, 5000);
          return { result: `Exit ${e.status || 1}: ${err}`, isError: true };
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
            const out = execSync(`find "${lsPath}" -maxdepth 3 -not -path "*/node_modules/*" -not -path "*/.git/*" | sort | head -200`, {
              timeout: 8000, encoding: 'utf8',
            });
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
          execSync('git add -A', { cwd: gitCwd, timeout: 10000 });
          const commitOut = execSync(
            `git commit -m "${(args.message || 'checkpoint').replace(/"/g, '\\"')}"`,
            { cwd: gitCwd, timeout: 15000, encoding: 'utf8' }
          );
          const hashMatch = commitOut.match(/\[.+\s+([a-f0-9]{7,})\]/);
          const hash = hashMatch ? hashMatch[1] : 'unknown';
          // Count changed files
          const diffStat = (() => {
            try { return execSync('git diff HEAD~1 --stat 2>/dev/null', { cwd: gitCwd, encoding: 'utf8', timeout: 5000 }); } catch { return ''; }
          })();
          const filesChanged = (diffStat.match(/\d+ file/) || [''])[0];
          const checkpoint = { hash, message: args.message || 'checkpoint', filesChanged, timestamp: new Date().toISOString() };
          session.gitCheckpoints.push(checkpoint);
          session.emit({ type: 'GIT_COMMIT', ...checkpoint });
          session.save();
          return { result: `Committed: ${hash} — ${args.message}`, isError: false };
        } catch (e) {
          const msg = (e.stderr || e.message || '').substring(0, 500);
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
            timeout: 8000,
          }, (res) => {
            let body = '';
            res.on('data', c => body += c);
            res.on('end', () => {
              try {
                const d = JSON.parse(body);
                let out = '';
                if (d.AbstractText) out += `${d.AbstractText}\n\n`;
                if (d.RelatedTopics) {
                  out += d.RelatedTopics
                    .slice(0, 5)
                    .map(t => t.Text || '')
                    .filter(Boolean)
                    .join('\n');
                }
                resolve(out || 'No results');
              } catch { resolve('Search failed'); }
            });
          });
          req.on('error', () => resolve('Search unavailable'));
          req.end();
        });
        return { result, isError: false };
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
    this.id       = id;
    this.task     = task;
    this.model    = model;
    this.status   = 'idle'; // idle | running | done | error | stopped
    this.messages = [];     // LLM conversation history
    this.events   = [];     // all emitted events (for replay)
    this.todos    = [];
    this.gitCheckpoints = [];
    this.workDir  = path.join(WORK_DIR(), id);
    this.createdAt = new Date().toISOString();
    this.updatedAt = new Date().toISOString();
    this.openrouterKey = '';
    this.anthropicKey  = '';
    this._ws = null;        // active WebSocket (nullable)
    this._stopped = false;
    this._seq = 0;

    // Create workspace directory
    if (!fs.existsSync(this.workDir)) {
      fs.mkdirSync(this.workDir, { recursive: true });
    }
  }

  emit(event) {
    event.seq = this._seq++;
    event.ts  = Date.now();
    this.events.push(event);
    // Keep last 1000 events
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
      id: this.id,
      task: this.task,
      model: this.model,
      status: this.status,
      messages: this.messages.slice(-40), // persist last 40 msgs
      events: this.events.slice(-200),    // persist last 200 events
      todos: this.todos,
      gitCheckpoints: this.gitCheckpoints,
      workDir: this.workDir,
      createdAt: this.createdAt,
      updatedAt: this.updatedAt,
    };
  }

  static fromJSON(data) {
    const s = new CodeSession(data.id, data.task, data.model);
    s.status = data.status || 'idle';
    s.messages = data.messages || [];
    s.events   = data.events   || [];
    s.todos    = data.todos    || [];
    s.gitCheckpoints = data.gitCheckpoints || [];
    s.workDir  = data.workDir  || s.workDir;
    s.createdAt = data.createdAt || s.createdAt;
    s.updatedAt = data.updatedAt || s.updatedAt;
    s._seq = s.events.length;
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
      // Mark running sessions as interrupted
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

function streamOpenRouter(messages, model, tools, openrouterKey, onDelta, signal) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model,
      messages,
      tools: tools.length > 0 ? toolsToOpenAI() : undefined,
      tool_choice: tools.length > 0 ? 'auto' : undefined,
      stream: true,
      max_tokens: 8192,
      temperature: 1.0,
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
      let toolCallMap = {}; // index → { id, name, argsStr }
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

            // Text delta
            if (delta.content) {
              fullText += delta.content;
              onDelta(delta.content);
            }

            // Tool call chunks
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
    req.on('timeout', () => { req.destroy(); reject(new Error('Timeout')); });
    req.write(body);
    req.end();
  });
}

// ============================================================
// ANTHROPIC STREAMING
// ============================================================

function streamAnthropic(messages, anthropicKey, systemPrompt, onDelta, signal) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model: 'claude-sonnet-4-6',
      max_tokens: 8192,
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
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
      timeout: 300000,
    }, (res) => {
      let buffer = '';
      let fullText = '';
      let toolUses = {}; // id → { id, name, inputStr }
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
    req.on('timeout', () => { req.destroy(); reject(new Error('Timeout')); });
    req.write(body);
    req.end();
  });
}

// ============================================================
// SYSTEM PROMPT
// ============================================================

function buildSystemPrompt(session) {
  return `You are Navi — an autonomous AI coding agent running on a dedicated Ubuntu server (Navi Brain).
You are working in: ${session.workDir}

## Working method (ReAct loop)
THINK   Understand the task deeply. Identify what you need to know.
PLAN    Break it into concrete steps. Call todo_write to track your plan.
ACT     Use tools actively. Read files before editing. Verify with run_command.
OBSERVE Analyze tool results. Adapt if unexpected.
REPEAT  Continue until the task is fully solved and verified.

## Rules
- Always read files before editing them (read_file first)
- Write production-quality code — no placeholders, no TODOs, no stubs
- Call todo_write at the start of any non-trivial task to create your plan
- Call git_commit after completing major milestones
- If an edit fails, read the file again to get current contents, then retry
- If tests fail, fix them before continuing
- Use run_command to verify your work (run tests, check syntax, etc.)
- Never give up — always find a way forward

## Communication style
Be concise. Short progress updates. Think aloud briefly at key decisions.
Use markdown: **bold** for key info, \`code\` for paths and commands, code blocks for code.

## Environment
Platform: Ubuntu Linux
Working directory: ${session.workDir}
Git: Available (git init if needed)
Package managers: npm, pip3, cargo available

## Task
${session.task}`;
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

async function compactContext(session) {
  const messages = session.messages;
  if (messages.length < 10) return;

  session.emit({ type: 'COMPACTING', reason: 'Context window approaching limit' });

  // Keep system-level messages: first user message + last 8 messages
  const head = messages.slice(0, 2);
  const tail = messages.slice(-8);
  const middle = messages.slice(2, -8);

  if (middle.length === 0) return;

  // Summarize middle (no tool calling, just summarize)
  const summaryText = middle
    .filter(m => typeof m.content === 'string')
    .map(m => `[${m.role}]: ${m.content?.substring(0, 300)}`)
    .join('\n');

  session.messages = [
    ...head,
    { role: 'user', content: `[Context summary — ${middle.length} messages compacted]\n${summaryText.substring(0, 3000)}` },
    { role: 'assistant', content: 'Understood. Continuing from where we left off.' },
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

  const modelId = isAnthropic ? 'claude-sonnet-4-6' : (MODELS[session.model] || MODELS.minimax);
  const systemPrompt = buildSystemPrompt(session);
  const MAX_ITER = 30;
  let doomCounter = 0;
  let lastToolNames = [];

  try {
    for (let iter = 0; iter < MAX_ITER; iter++) {
      if (abortCtrl.aborted || session._stopped) break;

      session.emit({ type: 'ITERATION', n: iter + 1, maxN: MAX_ITER });
      session.emit({ type: 'PHASE', phase: 'thinking', label: iter === 0 ? 'Thinking…' : `Thinking… (step ${iter + 1})` });

      // Context compaction if needed
      if (estimateTokens(session.messages) > 60000) {
        await compactContext(session);
      }

      let streamResult;

      if (isAnthropic) {
        streamResult = await streamAnthropic(
          session.messages,
          key,
          systemPrompt,
          (delta) => session.emit({ type: 'TEXT_DELTA', delta }),
          abortCtrl
        );
        // Anthropic: build content array for assistant message
        const assistantContent = [];
        if (streamResult.fullText) assistantContent.push({ type: 'text', text: streamResult.fullText });
        for (const tc of streamResult.toolCalls) {
          assistantContent.push({ type: 'tool_use', id: tc.id, name: tc.name, input: tc.args });
        }
        session.messages.push({ role: 'assistant', content: assistantContent });
      } else {
        // OpenRouter / OpenAI format
        const msgs = [
          { role: 'system', content: systemPrompt },
          ...session.messages,
        ];
        streamResult = await streamOpenRouter(msgs, modelId, CODE_TOOLS, key,
          (delta) => session.emit({ type: 'TEXT_DELTA', delta }),
          abortCtrl
        );
        // Build assistant message
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

      // Commit text block
      if (streamResult.fullText?.trim()) {
        session.emit({ type: 'TEXT_COMMIT', text: streamResult.fullText });
      }

      // No tool calls → task complete
      const { toolCalls, stopReason } = streamResult;
      if (toolCalls.length === 0 || stopReason === 'stop' || stopReason === 'end_turn') {
        session.emit({ type: 'PHASE', phase: 'done', label: 'Done' });
        break;
      }

      // Doom loop detection
      const toolNames = toolCalls.map(t => t.name).sort().join(',');
      if (toolNames === lastToolNames) {
        doomCounter++;
        if (doomCounter >= 3) {
          session.messages.push({ role: 'user', content: 'You are repeating the same actions. Stop and take a completely different approach, or report that the task cannot be completed as specified.' });
          doomCounter = 0;
        }
      } else {
        doomCounter = 0;
        lastToolNames = toolNames;
      }

      // Execute tool calls
      session.emit({ type: 'PHASE', phase: 'tools', label: `Running ${toolCalls.length} tool${toolCalls.length > 1 ? 's' : ''}…` });

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
          result: result.substring(0, 3000),
          isError,
          durationMs,
        });

        if (isAnthropic) {
          toolResults.push({ type: 'tool_result', tool_use_id: tc.id, content: result });
        } else {
          toolResults.push({ role: 'tool', tool_call_id: tc.id, content: result });
        }
      }

      // Add tool results to history
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
      session.emit({ type: 'RUN_FINISHED', summary: session.todos.length > 0
        ? session.todos.filter(t => t.done).length + '/' + session.todos.length + ' tasks completed'
        : 'Completed'
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

  // Heartbeat
  pingInterval = setInterval(() => {
    if (ws.readyState === 1) sendRaw({ type: 'PING', ts: Date.now() });
  }, 20000);

  ws.on('message', async (rawMsg) => {
    let msg;
    try { msg = JSON.parse(rawMsg.toString()); } catch { return; }

    switch (msg.type) {

      case 'SUBSCRIBE': {
        // Reconnect to existing session
        const s = codeSessions[msg.sessionId];
        if (!s) {
          sendRaw({ type: 'ERROR', error: 'Session not found' });
          return;
        }
        session = s;
        session._ws = ws;
        sendRaw({ type: 'CONNECTED', sessionId: s.id, hasHistory: s.messages.length > 0 });

        // State snapshot (current session state for UI reconstruction)
        sendRaw({
          type: 'STATE_SNAPSHOT',
          status: s.status,
          todos: s.todos,
          gitCheckpoints: s.gitCheckpoints,
          task: s.task,
          model: s.model,
          createdAt: s.createdAt,
        });

        // Replay missed events
        const lastSeq = msg.lastSeq ?? 0;
        s.replayFrom(ws, lastSeq);
        break;
      }

      case 'START': {
        // Create new session and start agent
        const id = uuidv4();
        const s = new CodeSession(id, msg.task || '', msg.model || 'minimax');
        s.openrouterKey = msg.openrouterKey || DEFAULT_OPENROUTER_KEY;
        s.anthropicKey  = msg.anthropicKey  || DEFAULT_ANTHROPIC_KEY;
        s._ws = ws;
        session = s;
        codeSessions[id] = s;

        sendRaw({ type: 'CONNECTED', sessionId: id, hasHistory: false });
        s.save();

        // Start agent asynchronously (persists when WS disconnects)
        runCodeAgent(s).catch(e => {
          console.error('[CODE-AGENT] Unhandled:', e.message);
        });
        break;
      }

      case 'SEND': {
        // Continue existing session with a new user message
        if (!session) { sendRaw({ type: 'ERROR', error: 'No active session' }); return; }
        if (session.status === 'running') { sendRaw({ type: 'ERROR', error: 'Agent is already running' }); return; }

        // Append user message and continue
        session.messages.push({ role: 'user', content: msg.text || '' });
        session.task = msg.text; // update task for system prompt
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
    // Session keeps running — just detach the ws reference
    if (session && session._ws === ws) {
      session._ws = null;
    }
  });

  ws.on('error', () => {
    clearInterval(pingInterval);
    if (session && session._ws === ws) {
      session._ws = null;
    }
  });
}

// ============================================================
// EXPRESS ROUTER
// ============================================================

function createRouter(express) {
  const router = express.Router();

  // POST /code/start — REST fallback to create a session without WS
  router.post('/start', (req, res) => {
    const apiKey = req.headers['x-api-key'];
    // Check is handled by caller
    const { task, model, openrouterKey, anthropicKey } = req.body;
    if (!task) return res.status(400).json({ error: 'task required' });

    const id = uuidv4();
    const s = new CodeSession(id, task, model || 'minimax');
    s.openrouterKey = openrouterKey || req.headers['x-openrouter-key'] || DEFAULT_OPENROUTER_KEY;
    s.anthropicKey  = anthropicKey  || req.headers['x-anthropic-key']  || DEFAULT_ANTHROPIC_KEY;
    codeSessions[id] = s;
    s.save();

    // Start agent in background
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

  return router;
}

// ============================================================
// INIT
// ============================================================

function init(wss, config = {}) {
  DATA_DIR               = config.dataDir || DATA_DIR;
  DEFAULT_OPENROUTER_KEY = config.openrouterKey || '';
  DEFAULT_ANTHROPIC_KEY  = config.anthropicKey  || '';

  // Ensure dirs exist
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
  if (!fs.existsSync(WORK_DIR())) fs.mkdirSync(WORK_DIR(), { recursive: true });

  // Load persisted sessions
  loadSessions();

  // WebSocket connections
  wss.on('connection', handleWebSocket);

  // Periodic save
  setInterval(() => {
    for (const s of Object.values(codeSessions)) {
      s.save();
    }
  }, 30000);

  console.log('[CODE-AGENT] Initialized — sessions:', Object.keys(codeSessions).length);
}

module.exports = { init, createRouter, codeSessions };
