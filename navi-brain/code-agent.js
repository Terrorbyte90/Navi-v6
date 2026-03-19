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
let DEFAULT_GITHUB_TOKEN   = process.env.GITHUB_TOKEN || '';

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
  {
    name: 'memory_write',
    description: 'Save a value to persistent session memory. Use to remember architecture decisions, known bugs, or context you may need later.',
    parameters: {
      type: 'object',
      properties: {
        key:   { type: 'string', description: 'Memory key (e.g. "architecture", "known_bugs")' },
        value: { type: 'string', description: 'Value to store' },
      },
      required: ['key', 'value'],
    },
  },
  {
    name: 'memory_read',
    description: 'Read a value from persistent session memory.',
    parameters: {
      type: 'object',
      properties: {
        key: { type: 'string', description: 'Memory key to read' },
      },
      required: ['key'],
    },
  },
  {
    name: 'run_tests',
    description: 'Run the project test suite. Auto-detects npm/pytest/cargo/go. Returns pass/fail counts.',
    parameters: {
      type: 'object',
      properties: {
        cwd:     { type: 'string', description: 'Working directory (defaults to session workDir)' },
        command: { type: 'string', description: 'Explicit test command (overrides auto-detection)' },
      },
    },
  },
  {
    name: 'install_package',
    description: 'Install packages using npm, pip, cargo, or apt. Prefer this over run_command for package installation.',
    parameters: {
      type: 'object',
      properties: {
        manager:  { type: 'string', enum: ['npm', 'pip', 'cargo', 'apt'], description: 'Package manager' },
        packages: { type: 'array', items: { type: 'string' }, description: 'Package names to install' },
        cwd:      { type: 'string', description: 'Working directory' },
      },
      required: ['manager', 'packages'],
    },
  },
  {
    name: 'diff_file',
    description: 'Show git diff for a specific file since the last commit. Use to review your own changes before committing.',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Absolute path to the file' },
      },
      required: ['path'],
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
        const query = args.query || '';
        const encodedQuery = encodeURIComponent(query);

        // Use DuckDuckGo HTML endpoint — more reliable than the JSON API
        const result = await new Promise((resolve) => {
          const req = https.request({
            hostname: 'html.duckduckgo.com',
            path: `/html/?q=${encodedQuery}&kl=se-sv`,
            method: 'GET',
            timeout: 15000,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'sv,en;q=0.9',
              'Accept-Encoding': 'identity',
            },
          }, (res) => {
            let body = '';
            res.on('data', c => { if (body.length < 600000) body += c; });
            res.on('end', () => {
              try {
                const results = [];

                // Extract result titles + URLs
                const titleRe = /<a[^>]+class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/g;
                const snippetRe = /<a[^>]+class="result__snippet"[^>]*>([\s\S]*?)<\/a>/g;

                const titles = [];
                const snippets = [];
                let m;

                while ((m = titleRe.exec(body)) !== null && titles.length < 8) {
                  const url = m[1];
                  const title = m[2].replace(/<[^>]+>/g, '').trim();
                  if (title && url) titles.push({ url, title });
                }
                while ((m = snippetRe.exec(body)) !== null && snippets.length < 8) {
                  const text = m[1].replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#x27;/g, "'").trim();
                  if (text) snippets.push(text);
                }

                for (let i = 0; i < Math.min(titles.length, 6); i++) {
                  const snippet = snippets[i] || '';
                  results.push(`**${titles[i].title}**\n${snippet}\n${titles[i].url}`);
                }

                if (results.length > 0) {
                  resolve(`Sökresultat för "${query}":\n\n${results.join('\n\n')}`);
                } else {
                  // Fallback: try DuckDuckGo JSON API
                  resolve('Inga resultat. Prova ett mer specifikt sökord.');
                }
              } catch (e) {
                resolve(`Sökning misslyckades: ${e.message}`);
              }
            });
          });
          req.on('error', (e) => resolve(`Sökning otillgänglig: ${e.message}`));
          req.on('timeout', () => { req.destroy(); resolve('Söktidsgräns nådd'); });
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

          while (redirects < 5) {
            const urlObj = (() => { try { return new URL(currentUrl); } catch { return null; } })();
            if (!urlObj) return { text: `Invalid URL: ${currentUrl}`, error: true };

            const lib = urlObj.protocol === 'https:' ? https : http;
            let response;
            for (let attempt = 0; attempt <= 2; attempt++) {
              response = await new Promise((resolve) => {
                const reqOpts = {
                  hostname: urlObj.hostname,
                  port: urlObj.port || (urlObj.protocol === 'https:' ? 443 : 80),
                  path: urlObj.pathname + (urlObj.search || ''),
                  method: args.method || 'GET',
                  headers: {
                    'User-Agent': 'Mozilla/5.0 (Navi-Code-Agent/2.0)',
                    'Accept': 'text/html,application/json,text/plain,*/*',
                  },
                  timeout: 30000,
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
                req.on('timeout', () => { req.destroy(); resolve({ text: 'Request timed out', error: true, isTimeout: true }); });
                req.end();
              });
              // Retry only on timeout, not on other errors
              if (response.isTimeout && attempt < 2) continue;
              break;
            }

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

      case 'memory_write': {
        const { key, value } = args;
        if (!key) return { result: 'key is required', isError: true };
        session.memory[key] = String(value ?? '');
        session.save();
        return { result: `saved`, isError: false };
      }

      case 'memory_read': {
        const { key } = args;
        if (!key) return { result: 'key is required', isError: true };
        const val = session.memory[key];
        return { result: val !== undefined ? val : '(not found)', isError: false };
      }

      case 'run_tests': {
        const testCwd = args.cwd || workDir;
        // Auto-detect test runner
        const hasPkg   = fs.existsSync(path.join(testCwd, 'package.json'));
        const hasReqs  = fs.existsSync(path.join(testCwd, 'requirements.txt')) || fs.existsSync(path.join(testCwd, 'pyproject.toml'));
        const hasCargo = fs.existsSync(path.join(testCwd, 'Cargo.toml'));
        const hasGo    = fs.existsSync(path.join(testCwd, 'go.mod'));

        let cmd = args.command; // allow explicit override
        if (!cmd) {
          if (hasPkg)        cmd = 'npm test --if-present';
          else if (hasReqs)  cmd = 'python3 -m pytest -v 2>&1 | tail -50';
          else if (hasCargo) cmd = 'cargo test 2>&1 | tail -50';
          else if (hasGo)    cmd = 'go test ./... 2>&1 | tail -50';
          else cmd = 'echo "No test runner detected"';
        }

        try {
          const output = await asyncExec(cmd, { cwd: testCwd, timeout: 120000 });
          const passMatch = output.match(/(\d+)\s+pass(?:ing|ed)?/i);
          const failMatch = output.match(/(\d+)\s+fail(?:ing|ed)?/i);
          const passCount = passMatch ? parseInt(passMatch[1]) : null;
          const failCount = failMatch ? parseInt(failMatch[1]) : 0;
          const toolResult = { result: output.substring(0, 8000), isError: false, passCount, failCount: failCount ?? 0 };
          // Trigger ReviewerAgent on first successful test run — blocking
          if ((toolResult.failCount === 0) && !session.reviewerHasRun) {
            session.reviewerHasRun = true;
            await runReviewerAgent(session);
          }
          return toolResult;
        } catch (e) {
          const out = ((e.stderr || '') + (e.stdout || '') + e.message).substring(0, 5000);
          return { result: `Tests failed:\n${out}`, isError: true, failCount: 1 };
        }
      }

      case 'install_package': {
        const { manager, packages } = args;
        if (!packages || packages.length === 0) return { result: 'packages array is required', isError: true };
        const pkgList = Array.isArray(packages) ? packages.join(' ') : packages;
        const installCwd = args.cwd || workDir;
        const cmds = {
          npm:   `npm install ${pkgList}`,
          pip:   `pip3 install ${pkgList}`,
          cargo: `cargo add ${pkgList}`,
          apt:   `apt-get install -y ${pkgList}`,
        };
        const cmd = cmds[manager] || `npm install ${pkgList}`;
        try {
          const out = await asyncExec(cmd, { cwd: installCwd, timeout: 120000 });
          return { result: out.substring(0, 3000), isError: false };
        } catch (e) {
          return { result: `Install failed: ${e.message}`, isError: true };
        }
      }

      case 'diff_file': {
        const fp = args.path;
        try {
          const out = await asyncExec(`git diff HEAD -- "${fp}"`, { cwd: path.dirname(fp), timeout: 8000 });
          return { result: out || '(no diff — file unchanged since last commit)', isError: false };
        } catch (e) {
          return { result: `git diff failed: ${e.message}`, isError: true };
        }
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
    this.memory        = {};  // key-value store, persisted
    this.reviewerHasRun = false; // not persisted — reset each run
    this.parentSessionId = null;  // set when resuming from another session

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
      memory:          this.memory,
      parentSessionId: this.parentSessionId,
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
    s.memory          = data.memory          || {};
    s.parentSessionId = data.parentSessionId || null;
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

function streamAnthropic(messages, anthropicKey, systemPrompt, modelInfo, onDelta, signal, toolsOverride = null) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model: modelInfo.id,
      max_tokens: modelInfo.maxTokens,
      system: systemPrompt,
      messages,
      tools: toolsOverride === null ? toolsToAnthropic() : (toolsOverride.length > 0 ? toolsOverride : undefined),
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
// PLANNER AGENT
// ============================================================

async function runPlannerAgent(session) {
  const modelInfo = MODELS.minimax; // always MiniMax, regardless of session model
  const key = session.openrouterKey || DEFAULT_OPENROUTER_KEY;
  const plannerPrompt = `Du är en expert kodarkitekt och planerare. Din uppgift är att analysera projektet i sessionens arbetskatalog och skapa en tydlig, strukturerad plan för att lösa den ursprungliga uppgiften.

Ursprunglig uppgift: ${session.initialTask}

Arbetsdir: ${session.workDir}

Analysera:
1. Kör mentalt igenom vad du behöver förstå: README, package.json, filstruktur, befintliga mönster
2. Identifiera tech stack och beroenden
3. Bryt ner uppgiften i 3-7 konkreta steg med tydliga delmål
4. Identifiera risker och potentiella problem

Returnera en strukturerad plan i detta format:
## 📋 Plan
**Tech stack:** [lista]
**Risker:** [lista]

### Steg 1: [Titel]
- Vad: [beskrivning]
- Filer: [berörda filer]

### Steg 2: ...

Håll planen kortfattad och handlingsbar. Max 500 ord.`;

  const messages = [{ role: 'user', content: plannerPrompt }];

  try {
    let planText = '';
    await streamOpenRouter(messages, modelInfo, [], key, (delta) => { planText += delta; }, null);
    session.messages.unshift({
      role: 'user',
      content: `[SYSTEM: PlannerAgent analys — följ denna plan]\n${planText}`,
    });
    session.emit({ type: 'TEXT_COMMIT', text: `## 🗺️ Plan skapad av PlannerAgent\n${planText}`, role: 'planner' });
  } catch (e) {
    session.emit({ type: 'INFO', message: `planner_agent failed: ${e.message}` });
  }
}

// REVIEWER AGENT
// ============================================================

async function runReviewerAgent(session) {
  const anthropicKey = session.anthropicKey || DEFAULT_ANTHROPIC_KEY;
  if (!anthropicKey) return; // no key — skip silently

  // Get list of changed files since last commit
  let changedFiles = '';
  try {
    changedFiles = await asyncExec(`git diff HEAD --name-only`, { cwd: session.workDir, timeout: 8000 });
  } catch {
    changedFiles = '(could not determine changed files)';
  }

  // Read changed file contents (first 3 files, max 3000 chars each)
  const fileNames = changedFiles.trim().split('\n').filter(Boolean).slice(0, 3);
  let fileContents = '';
  for (const fn of fileNames) {
    try {
      const fp = path.join(session.workDir, fn);
      if (fs.existsSync(fp)) {
        const content = fs.readFileSync(fp, 'utf8').substring(0, 3000);
        fileContents += `\n\n### ${fn}\n\`\`\`\n${content}\n\`\`\``;
      }
    } catch {}
  }

  session.emit({ type: 'PHASE', phase: 'reviewing', label: 'Granskar kod...' });

  const reviewPrompt = `Du är en expert kodgranskare. Granska dessa nyligen ändrade filer och ge konkret feedback.

Projekt: ${session.initialTask}
Ändrade filer: ${changedFiles || '(inga)'}\n${fileContents}

Granska för:
1. Säkerhetshål (injection, exponerade hemligheter, osäkra operationer)
2. Logikfel (edge cases som saknas, felaktig felhantering)
3. Platshållare (// TODO, pass, stub-funktioner, "implement later")
4. Inkonsistenser med professionell kodstandard

Var konkret och specifik — ange filnamn och radnummer om möjligt.
Om allt ser bra ut, skriv: "✅ Koden ser bra ut."
Om du hittar problem, skriv dem som en numrerad lista.`;

  const messages = [{ role: 'user', content: reviewPrompt }];
  const modelInfo = MODELS.claude;

  try {
    let reviewText = '';
    await streamAnthropic(messages, anthropicKey, '', modelInfo, (delta) => { reviewText += delta; }, null, []); // [] = no tools
    session.messages.push({ role: 'user', content: `[SYSTEM: ReviewerAgent feedback]\n${reviewText}` });
    session.emit({ type: 'TEXT_COMMIT', text: `## 🔍 Kodgranskning (ReviewerAgent)\n${reviewText}`, role: 'reviewer' });
  } catch (e) {
    session.emit({ type: 'INFO', message: `reviewer_agent failed: ${e.message}` });
  }

  session.emit({ type: 'PHASE', phase: 'tools', label: '' });
}

// SYSTEM PROMPT
// ============================================================

function buildSystemPrompt(session) {
  const modelInfo = MODELS[session.model] || MODELS.minimax;
  const ghToken = DEFAULT_GITHUB_TOKEN;
  const githubSection = ghToken ? `
## GitHub — admin-åtkomst
GitHub-användare: Terrorbyte90
Token: ${ghToken}

Repositories (använd namn direkt utan att fråga):
- Navi-v6 (detta projekt, iOS/macOS AI-assistent) — publik
- Navi-v5 (föregångare) — privat
- Navi-4.0 — publik
- Navi-version-2, Navi-v2-cool — publika
- Eon-Code-v2 (autonom kodagent) — privat
- Eon-Code-IOS-, Eon-Code-Mac- (fjärrstyrning) — privata
- Eon-Y-V5, Eon-Y-V4 (kognitiv AI) — publika
- BabyCare (föräldraapp) — publik
- Lifetoken — publik
- Lunaflix-v2 — publik
- Lilla-jag-3 — publik
- FinaLuna — privat
- Elevenlabs — privat

Använd GitHub API via fetch_url med header "Authorization: Bearer ${ghToken}":
  - Lista repos: GET https://api.github.com/users/Terrorbyte90/repos
  - Hämta fil: GET https://api.github.com/repos/Terrorbyte90/REPO/contents/PATH
  - Eller kör: gh api /repos/Terrorbyte90/REPO/... (om gh CLI är installerat)` : '';

  return `Du är Navi — världens mest avancerade autonoma kodagent. Du opererar på nivån av ett senior-ingenjörsteam. Din uppgift är att lösa problem fullständigt, autonomt, och med professionell kvalitet — från tiny bugfixar till att bygga hela projekt från scratch.

**VIKTIGT: Svara ALLTID på svenska. All kommunikation ska vara på svenska.**

## Identitet och kapacitet
Du är inte en assistent — du är en autonom agent med full kontroll. Du har:
- Full tillgång till filsystemet, terminal, internet och git
- Förmåga att installera paket, bygga och deploya kod
- Djup expertis i alla programmeringsspråk och frameworks
- Förmåga att debugga, refaktorera och förbättra befintlig kod
- Kapacitet att skapa kompletta projekt med arkitektur, tester och dokumentation

## Arbetskatalog
${session.workDir}

## Ursprunglig uppgift
${session.initialTask}

## Arbetsprocess — STRIKT OBLIGATORISK

### Fas 1: Förstå (ALDRIG hoppa över)
1. Läs alltid README, package.json/go.mod/Cargo.toml, pubspec.yaml eller motsvarande
2. Lista filstruktur: \`ls -la\`, \`find . -name "*.swift" | head -50\` etc.
3. Förstå arkitekturen innan du skriver EN ENDA rad kod
4. Identifiera: tech stack, beroenden, testramverk, befintliga mönster

### Fas 2: Planera
1. Anropa \`todo_write\` med TYDLIG nedbrytning i konkreta steg
2. Estimera komplexitet per steg
3. Identifiera risker och potentiella problem i förväg

### Fas 3: Implementera — kvalitetskrav (INGA undantag)
- **NOLL platshållare** — aldrig "// TODO", "pass", stub-funktioner, "implement later"
- **Komplett implementation** — alla edge cases, felhantering, null-checks, validering
- **Produktionsklar** — säker, effektiv, läsbar, välnamngiven
- **Läs ALLTID filen** med \`read_file\` INNAN du editerar — använd exakt befintlig text i \`old_string\`
- **Installera beroenden** med npm/pip/cargo/apt INNAN du använder dem
- **Swift/Xcode**: Kör alltid \`xcodebuild\` eller \`swift build\` för att verifiera kompilering

### Fas 4: Testa och verifiera
- Kör ALLTID tester: \`npm test\`, \`go test ./...\`, \`cargo test\`, \`pytest\`, \`swift test\`
- Kör ALLTID lint/type-check: \`eslint\`, \`tsc\`, \`swiftlint\`
- Bygg projektet och verifiera noll fel, noll varningar
- **Påstå ALDRIG framgång utan att ha kört och sett gröna tester**

### Fas 5: Commit
- \`git_commit\` vid varje viktig milstolpe — en fungerande feature, bugfix etc.
- Tydliga commit-meddelanden på engelska: "feat(auth): add JWT refresh logic"

### Fas 6: Repetera
- Fortsätt tills HELA uppgiften är klar, testad och verifierad
- Verifiera att originaluppgiften är uppfylld punkt för punkt

## Felsökning — protokoll
1. **Läs felmeddelandet ORDENTLIGT** — förstå exakt vad som felas och var
2. **Reproducera** — kör samma kommando igen och bekräfta felet
3. **Isolera** — hitta minsta möjliga reproduktion
4. **Åtgärda rotorsaken** — aldrig bara symptomen
5. Om fastnad >2 iterationer på samma fel:
   - Sök på webben: \`web_search "exact error message"\`
   - Hämta officiell dokumentation: \`fetch_url "https://docs.xyz.com/..."\`
   - Prova HELT annat tillvägagångssätt
6. **GE ALDRIG UPP** — varje problem har en lösning

## Kommunikation — markdown obligatorisk
Rapportera vid VARJE milstolpe med tydlig struktur:

**Vid start:**
## 🔍 Analyserar projektet
*kort beskrivning av vad du ser*

**Vid implementation:**
## ✅ [Feature] implementerad
- Vad som gjordes
- Hur man testar det

**Vid problem:**
## ⚠️ Problem: [kort beskrivning]
*vad du hittade och hur du löser det*

**Vid avslut:**
## 🎯 Uppgift klar
### Sammanfattning
- [punkt 1]
- [punkt 2]
### Nästa steg (om relevanta)
- [valfria förbättringar]

## Snabba kommandon — använd dem
- \`run_command("ls -la")\` — lista filer
- \`run_command("cat package.json")\` — läs konfiguration
- \`run_command("npm install && npm test")\` — installera och testa
- \`run_command("git log --oneline -10")\` — se historia
- \`run_command("grep -r 'functionName' src/ --include='*.ts'")\` — sök i kod
- \`web_search("error message site:stackoverflow.com")\` — sök lösning
- \`fetch_url("https://docs.example.com/api")\` — hämta dokumentation

## Miljö — din server
- Plattform: Ubuntu Linux med root-access
- Shell: bash med full PATH
- Internet: Ja via fetch_url och web_search
- Git: Globalt installerat
- Pakethanterare: npm, pip3, cargo, apt, brew
- Kontextfönster: ${(modelInfo.contextLimit).toLocaleString()} tokens (modell: ${session.model})
- Max output: ${modelInfo.maxTokens.toLocaleString()} tokens

## Lokala AI-modeller på servern
- **Qwen3-1.7B-Q4_K_M**: \`/root/ai-models/Qwen3-1.7B-Q4_K_M.gguf\`
  - iOS/macOS-integration: kopiera QwenHandler.swift från Eon-Y
  - Format: ChatML (\`<|im_start|>system\\n...\`)
- **LM Studio på Mac**: \`http://localhost:1234/v1\` (OpenAI-kompatibelt API)

## GitHub-integration
${githubSection}`;
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
      content: `[Kontext kompakterad — ${middle.length} tidigare meddelanden sammanfattade]\n${summaryText.substring(0, 4000)}`,
    },
    {
      role: 'assistant',
      content: 'Förstått. Jag har granskat sammanfattningen och fortsätter därifrån.',
    },
    ...tail,
  ];
}

// ============================================================
// WATCHER — quality control agent that runs every N iterations
// Detects: loops, goal drift, premature completion, stuck errors
// ============================================================

const WATCH_EVERY = 3; // Run watcher every N iterations

// Simple non-streaming OpenRouter call (for watcher — no tools, low latency)
function callOpenRouterSimple(messages, openrouterKey, modelId) {
  return new Promise((resolve) => {
    const body = JSON.stringify({
      model: modelId,
      messages,
      stream: false,
      max_tokens: 300,
      temperature: 0.1,
    });
    const req = https.request({
      hostname: 'openrouter.ai',
      path: '/api/v1/chat/completions',
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openrouterKey}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://navi.app',
        'X-Title': 'Navi Watcher',
        'Content-Length': Buffer.byteLength(body),
      },
      timeout: 25000,
    }, (res) => {
      let data = '';
      res.on('data', chunk => { data += chunk.toString(); });
      res.on('end', () => {
        try { resolve(JSON.parse(data).choices?.[0]?.message?.content || '{"ok":true}'); }
        catch { resolve('{"ok":true}'); }
      });
    });
    req.on('error', () => resolve('{"ok":true}'));
    req.on('timeout', () => { req.destroy(); resolve('{"ok":true}'); });
    req.write(body);
    req.end();
  });
}

function buildWatcherPrompt(session, iter) {
  const recentMsgs = session.messages.slice(-15).map(m => {
    const role = m.role.toUpperCase();
    const content = typeof m.content === 'string'
      ? m.content.substring(0, 600)
      : JSON.stringify(m.content).substring(0, 600);
    return `[${role}] ${content}`;
  }).join('\n\n');

  const todos = session.todos.length > 0
    ? session.todos.map(t => `${t.done ? '✅' : '⬜'} ${t.title}`).join('\n')
    : '(ingen plan definierad än)';

  return `Du är en kvalitetskontrollant för en autonom AI-kodagent. Ge ett snabbt omdöme baserat på framsteg.

## Ursprunglig uppgift
${session.initialTask}

## TODO-plan (framsteg)
${todos}

## Senaste aktivitet (iteration ${iter}/40)
${recentMsgs}

## Analys-kriterier
Bedöm agentens arbete STRIKT:

A) Reella framsteg mot målet → { "ok": true }
B) Semantisk loop (upprepar samma misstag 2+ gånger) → { "intervene": true, "prompt": "Du fastnar. Prova: [specifik alternativ strategi]" }
C) Avklarat för tidigt (sagt klar men kritiska delar saknas) → { "intervene": true, "prompt": "Du avslutade för tidigt. Dessa krav är inte uppfyllda: [lista specifikt vad som saknas]" }
D) Fel spår (åtgärdar fel sak) → { "intervene": true, "prompt": "Du avviker från uppgiften. Fokusera på: [exakt vad som ska göras härnäst]" }
E) Hänger på ett fel >3 iterationer → { "intervene": true, "prompt": "Du är fastnad i detta fel. Prova ett helt annat tillvägagångssätt: [konkret förslag]" }
F) Inga tester körda trots kodändringar → { "intervene": true, "prompt": "Du har skrivit kod men inte verifierat att den fungerar. Kör tester nu." }

Svara BARA med JSON — ingenting annat. Var strikt och intervenera om du ser problem.`;
}

async function watcherCheck(session, iter) {
  const key = session.openrouterKey || DEFAULT_OPENROUTER_KEY;
  if (!key) return { ok: true };
  try {
    const raw = await callOpenRouterSimple(
      [{ role: 'user', content: buildWatcherPrompt(session, iter) }],
      key,
      MODELS.minimax.id
    );
    const match = raw.match(/\{[\s\S]*?\}/);
    if (match) return JSON.parse(match[0]);
  } catch (e) {
    console.error('[WATCHER]', e.message);
  }
  return { ok: true };
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
  session.emit({ type: 'PHASE', phase: 'thinking', label: 'Tänker…' });

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

      // Run PlannerAgent once at the start
      if (iter === 0) {
        await runPlannerAgent(session);
      }

      session.emit({ type: 'ITERATION', n: iter + 1, maxN: MAX_ITER });
      session.emit({
        type: 'PHASE',
        phase: 'thinking',
        label: iter === 0 ? 'Tänker…' : `Tänker… (steg ${iter + 1})`,
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
        session.emit({ type: 'PHASE', phase: 'done', label: 'Klar' });
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
        label: `Kör ${toolCalls.length} verktyg…`,
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

      // Check for cancellation after tool execution
      if (session._stopped || session.status === 'cancelled') {
        session.emit({ type: 'PHASE', phase: 'cancelled', label: 'Avbruten' });
        break;
      }

      // === WATCHER CHECK (every WATCH_EVERY iterations, non-blocking on errors) ===
      if ((iter + 1) % WATCH_EVERY === 0 && iter > 0 && !isAnthropic) {
        session.emit({ type: 'WATCHER_CHECK', status: 'checking', iter: iter + 1, message: `Kvalitetskontroll (steg ${iter + 1})…` });
        const verdict = await watcherCheck(session, iter + 1);
        const watcherMsg = verdict.intervene
          ? `Watcher ingrep: ${verdict.prompt ? verdict.prompt.substring(0, 120) : 'korrektiv åtgärd'}`
          : 'Watcher: framsteg verifierat';
        session.emit({
          type: 'WATCHER_CHECK',
          status: 'done',
          ok: verdict.ok === true,
          intervene: !!verdict.intervene,
          iter: iter + 1,
          message: watcherMsg,
          prompt: verdict.prompt || null,
        });
        if (verdict.intervene && verdict.prompt) {
          console.log(`[WATCHER] Intervening at iter ${iter + 1}: ${verdict.prompt.substring(0, 80)}`);
          session.messages.push({
            role: 'user',
            content: `[Kvalitetskontroll] ${verdict.prompt}`,
          });
        }
      }

      // Check for cancellation at end of iteration
      if (session._stopped || session.status === 'cancelled') {
        session.emit({ type: 'PHASE', phase: 'cancelled', label: 'Avbruten' });
        break;
      }

      session.save();
    }

    if (!abortCtrl.aborted && !session._stopped) {
      session.status = 'done';
      session.emit({
        type: 'RUN_FINISHED',
        summary: session.todos.length > 0
          ? `${session.todos.filter(t => t.done).length}/${session.todos.length} uppgifter klara`
          : 'Klar',
      });
    } else {
      session.status = 'stopped';
      session.emit({ type: 'RUN_ERROR', error: 'Stoppad av användaren' });
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
