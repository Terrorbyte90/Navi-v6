# Code Agent Server Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade `code-agent.js` with 5 new tools, 2 specialist sub-agents (Planner + Reviewer), a system prompt overhaul, cost tracking via `RUN_FINISHED`, and session resume support via a new snapshot endpoint.

**Architecture:** All changes are in `navi-brain/code-agent.js` (new tools + sub-agents + system prompt) and `navi-brain/server.js` (snapshot REST endpoint). The existing ReAct loop, tool dispatch switch, CodeSession class, and AG-UI protocol are extended — nothing is replaced. PlannerAgent fires at `iter===0` before the first LLM call. ReviewerAgent fires inside `executeTool()` when `run_tests` returns failCount===0.

**Tech Stack:** Node.js, Express, WebSocket (`ws`), OpenRouter API, Anthropic API. Deploy via `bash deploy.sh` (pm2 on DigitalOcean).

**Agent to use:** `navi-server-dev` subagent for all tasks.

**Spec:** `docs/superpowers/specs/2026-03-19-navi-improvements-design.md` — Sektion 1

---

## File Map

| File | Changes |
|---|---|
| `navi-brain/code-agent.js` | Add 5 tools to switch + definitions array; add PlannerAgent; add ReviewerAgent; upgrade fetch_url; extend CodeSession (memory, reviewerHasRun, parentSessionId); upgrade system prompt; add usage tracking to run loop |
| `navi-brain/server.js` | Add `GET /code/sessions/:id/snapshot` endpoint; handle `inheritSessionId` + `contextSnapshot` in START message handler |

---

## Task 1: Add `memory` field to CodeSession

**Files:**
- Modify: `navi-brain/code-agent.js` (CodeSession constructor ~line 568, toJSON ~line 619, fromJSON ~line 636)

- [ ] **Step 1: Add `this.memory = {}` and `this.reviewerHasRun = false` to constructor**

In `constructor(id, task, model)`, after line `this._seq = 0;`, add:
```javascript
    this.memory        = {};  // key-value store, persisted
    this.reviewerHasRun = false; // not persisted — reset each run
    this.parentSessionId = null;  // set when resuming from another session
```

- [ ] **Step 2: Add `memory` and `parentSessionId` to `toJSON()`**

In `toJSON()`, add after `updatedAt`:
```javascript
      memory:          this.memory,
      parentSessionId: this.parentSessionId,
```

- [ ] **Step 3: Restore `memory` and `parentSessionId` in `fromJSON()`**

In `fromJSON()`, after `s.updatedAt = ...`, add:
```javascript
    s.memory          = data.memory          || {};
    s.parentSessionId = data.parentSessionId || null;
```

- [ ] **Step 4: Verify syntax**
```bash
node --check navi-brain/code-agent.js
```
Expected: no output (clean).

- [ ] **Step 5: Commit**
```bash
git add navi-brain/code-agent.js
git commit -m "feat(code-agent): add memory{} and parentSessionId to CodeSession"
```

---

## Task 2: Add `memory_write` and `memory_read` tools

**Files:**
- Modify: `navi-brain/code-agent.js` (executeTool switch ~line 274, tools definitions array ~line 84)

- [ ] **Step 1: Add tool cases to `executeTool()` switch**

After the `web_search` case and before the final `default` case, add:
```javascript
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
```

- [ ] **Step 2: Add tool definitions to the tools array**

Find the `TOOLS` array (the array that `toolsToOpenAI()` and `toolsToAnthropic()` consume). Add after `web_search`:
```javascript
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
```

- [ ] **Step 3: Verify**
```bash
node --check navi-brain/code-agent.js
```

- [ ] **Step 4: Commit**
```bash
git add navi-brain/code-agent.js
git commit -m "feat(code-agent): add memory_write/read tools with session persistence"
```

---

## Task 3: Add `run_tests`, `install_package`, `diff_file` tools

**Files:**
- Modify: `navi-brain/code-agent.js`

- [ ] **Step 1: Add `run_tests` case to executeTool switch**

```javascript
      case 'run_tests': {
        const testCwd = args.cwd || workDir;
        // Auto-detect test runner
        const hasPkg   = fs.existsSync(path.join(testCwd, 'package.json'));
        const hasReqs  = fs.existsSync(path.join(testCwd, 'requirements.txt')) || fs.existsSync(path.join(testCwd, 'pyproject.toml'));
        const hasCargo = fs.existsSync(path.join(testCwd, 'Cargo.toml'));
        const hasGo    = fs.existsSync(path.join(testCwd, 'go.mod'));

        let cmd = args.command; // allow explicit override
        if (!cmd) {
          if (hasPkg)   cmd = 'npm test --if-present';
          else if (hasReqs)  cmd = 'python3 -m pytest -v 2>&1 | tail -50';
          else if (hasCargo) cmd = 'cargo test 2>&1 | tail -50';
          else if (hasGo)    cmd = 'go test ./... 2>&1 | tail -50';
          else cmd = 'echo "No test runner detected"';
        }

        try {
          const output = await asyncExec(cmd, { cwd: testCwd, timeout: 120000 });
          // Parse pass/fail counts from common output formats
          const passMatch = output.match(/(\d+)\s+pass(?:ing|ed)?/i);
          const failMatch = output.match(/(\d+)\s+fail(?:ing|ed)?/i);
          const passCount = passMatch ? parseInt(passMatch[1]) : null;
          const failCount = failMatch ? parseInt(failMatch[1]) : 0;
          return { result: output.substring(0, 8000), isError: false, passCount, failCount };
        } catch (e) {
          const out = ((e.stderr || '') + (e.stdout || '') + e.message).substring(0, 5000);
          return { result: `Tests failed:\n${out}`, isError: true, failCount: 1 };
        }
      }
```

- [ ] **Step 2: Add `install_package` case**

```javascript
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
```

- [ ] **Step 3: Add `diff_file` case**

```javascript
      case 'diff_file': {
        const fp = args.path;
        const diffCwd = path.dirname(fp);
        try {
          const out = await asyncExecFile('git', ['diff', 'HEAD', '--', fp], { cwd: diffCwd, timeout: 8000 });
          return { result: out || '(no diff — file unchanged since last commit)', isError: false };
        } catch (e) {
          return { result: `git diff failed: ${e.message}`, isError: true };
        }
      }
```

- [ ] **Step 4: Add tool definitions for all three**

Add to tools array:
```javascript
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
```

- [ ] **Step 5: Verify**
```bash
node --check navi-brain/code-agent.js
```

- [ ] **Step 6: Commit**
```bash
git add navi-brain/code-agent.js
git commit -m "feat(code-agent): add run_tests, install_package, diff_file tools"
```

---

## Task 4: Upgrade `fetch_url`

**Files:**
- Modify: `navi-brain/code-agent.js` — `fetch_url` case starts at line ~484

**⚠️ Critical context:** The timeout handler at line 537 calls `resolve({ text: 'Request timed out', error: true })` — it **resolves**, not rejects. A try/catch wrapper will NOT catch timeouts. The retry must check the resolved value.

- [ ] **Step 1: Change `while (redirects < 3)` → `while (redirects < 5)` (line ~492)**

- [ ] **Step 2: Change `timeout: 15000` → `timeout: 30000` (line ~507)**

- [ ] **Step 3: Add `isTimeout: true` to the timeout resolve (line ~537)**

Change:
```javascript
req.on('timeout', () => { req.destroy(); resolve({ text: 'Request timed out', error: true }); });
```
To:
```javascript
req.on('timeout', () => { req.destroy(); resolve({ text: 'Request timed out', error: true, isTimeout: true }); });
```

- [ ] **Step 4: Add retry loop around the inner `await new Promise` block**

The current structure in the `while (redirects < 5)` loop is:
```
const response = await new Promise(...);
if (response.redirect) { ...; continue; }
return response;
```

Change it to:
```javascript
let response;
for (let attempt = 0; attempt <= 2; attempt++) {
  response = await new Promise((resolve) => {
    // ... identical Promise body (no changes inside) ...
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
```

- [ ] **Step 5: Verify**
```bash
node --check navi-brain/code-agent.js
```

- [ ] **Step 6: Commit**
```bash
git add navi-brain/code-agent.js
git commit -m "feat(code-agent): upgrade fetch_url — 30s timeout, 5 redirects, retry×2 on timeout"
```

---

## Task 5: Add PlannerAgent

**Files:**
- Modify: `navi-brain/code-agent.js` — add `runPlannerAgent()` function and call at `iter===0`

- [ ] **Step 1: Add `runPlannerAgent()` function**

Add this function before the main `run()` function (or wherever `buildSystemPrompt` is):

```javascript
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
    // ⚠️ Anthropic API rejects role:'system' inside messages array — use role:'user' with prefix marker instead.
    // This works for all models (OpenRouter and Anthropic).
    session.messages.unshift({
      role: 'user',
      content: `[SYSTEM: PlannerAgent analys — följ denna plan]\n${planText}`,
    });
    session.emit({ type: 'TEXT_COMMIT', text: `## 🗺️ Plan skapad av PlannerAgent\n${planText}`, role: 'planner' });
  } catch (e) {
    session.emit({ type: 'INFO', message: `planner_agent failed: ${e.message}` });
  }
}
```

- [ ] **Step 2: Call `runPlannerAgent` at iter===0 in the run loop**

Find the main iteration loop. It will look like `for (let iter = 0; iter < maxIter; iter++)`. At the very beginning of the loop body (before the LLM call), add:

```javascript
    // Run PlannerAgent once at the start
    if (iter === 0) {
      await runPlannerAgent(session);
    }
```

- [ ] **Step 3: Verify**
```bash
node --check navi-brain/code-agent.js
```

- [ ] **Step 4: Commit**
```bash
git add navi-brain/code-agent.js
git commit -m "feat(code-agent): add PlannerAgent — fires at iter=0, injects structured plan"
```

---

## Task 6: Add ReviewerAgent

**Files:**
- Modify: `navi-brain/code-agent.js` — add `runReviewerAgent()` and trigger in `executeTool`

- [ ] **Step 1: Add `runReviewerAgent()` function**

```javascript
async function runReviewerAgent(session) {
  if (!session.anthropicKey && !DEFAULT_ANTHROPIC_KEY) return; // no key — skip silently

  // Get list of changed files since last commit
  let changedFiles = '';
  try {
    changedFiles = await asyncExecFile('git', ['diff', 'HEAD', '--name-only'], { cwd: session.workDir, timeout: 8000 });
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
  const key = session.anthropicKey || DEFAULT_ANTHROPIC_KEY;

  // ⚠️ streamAnthropic always passes toolsToAnthropic() internally (line 782 of code-agent.js).
  // To avoid sending all 15+ tools to the reviewer model, first modify streamAnthropic to accept
  // an optional tools override parameter:
  //
  //   function streamAnthropic(messages, anthropicKey, systemPrompt, modelInfo, onDelta, signal, toolsOverride = null) {
  //     ...
  //     tools: toolsOverride !== null ? toolsOverride : toolsToAnthropic(),
  //     ...
  //   }
  //
  // Then call it with an empty tools array:
  try {
    let reviewText = '';
    await streamAnthropic(messages, key, '', modelInfo, (delta) => { reviewText += delta; }, null, []); // [] = no tools
    // ⚠️ role:'system' not allowed in Anthropic messages array — use role:'user' with prefix
    session.messages.push({ role: 'user', content: `[SYSTEM: ReviewerAgent feedback]\n${reviewText}` });
    session.emit({ type: 'TEXT_COMMIT', text: `## 🔍 Kodgranskning (ReviewerAgent)\n${reviewText}`, role: 'reviewer' });
  } catch (e) {
    session.emit({ type: 'INFO', message: `reviewer_agent failed: ${e.message}` });
  }

  session.emit({ type: 'PHASE', phase: 'tools', label: '' });
}
```

**Before Step 1, modify `streamAnthropic` signature** to accept optional tools override:

In `streamAnthropic` (line ~775), change the function signature from:
```javascript
function streamAnthropic(messages, anthropicKey, systemPrompt, modelInfo, onDelta, signal) {
```
To:
```javascript
function streamAnthropic(messages, anthropicKey, systemPrompt, modelInfo, onDelta, signal, toolsOverride = null) {
```

And change the `tools:` line in the request body from:
```javascript
      tools: toolsToAnthropic(),
```
To:
```javascript
      // ⚠️ Anthropic API rejects tools:[] — omit the field entirely when no tools needed
      tools: toolsOverride === null ? toolsToAnthropic() : (toolsOverride.length > 0 ? toolsOverride : undefined),
```

- [ ] **Step 2: Trigger ReviewerAgent in `executeTool` after successful `run_tests` — blocking**

The spec requires ReviewerAgent to be **blocking** (tool returns only after review completes). Change the success return in `run_tests` to `await`:

```javascript
          const toolResult = { result: output.substring(0, 8000), isError: false, passCount, failCount: failCount ?? 0 };
          // Trigger ReviewerAgent on first successful test run — blocking (spec requirement)
          if ((toolResult.failCount === 0) && !session.reviewerHasRun) {
            session.reviewerHasRun = true;
            await runReviewerAgent(session); // blocking — reviewer feedback is injected before next LLM call
          }
          return toolResult;
```

- [ ] **Step 3: Verify**
```bash
node --check navi-brain/code-agent.js
```

- [ ] **Step 4: Commit**
```bash
git add navi-brain/code-agent.js
git commit -m "feat(code-agent): add ReviewerAgent — fires on first successful test run, uses Claude Sonnet"
```

---

## Task 7: Upgrade system prompt

**Files:**
- Modify: `navi-brain/code-agent.js` — `buildSystemPrompt()` function (~line 860)

- [ ] **Step 1: Add output quality and communication directives**

In `buildSystemPrompt()`, find the `## Kommunikation — markdown obligatorisk` section and replace it with an expanded version:

```javascript
// Replace the communication section with:
`## Kommunikation — markdown obligatorisk, kvalitet avgörande

Du kommunicerar på nivån av ett world-class senior-ingenjörsteam. Varje svar ska:
- Förklara **varför**, inte bara vad — motivera varje arkitekturellt val
- Vara specifikt: ange alltid filnamn, radnummer, exakt felmeddelande
- Vara komplett: aldrig truncka förklaringar, inga ellipser (\`...\`) i kod
- Vara strukturerat: tydliga rubriker, punktlistor, kodblock

### Chain-of-thought (OBLIGATORISKT innan kod)
Tänk högt INNAN du skriver kod:
\`\`\`
Jag ska göra X. Anledningen är Y.
Alternativa lösningar: [A], [B]. Jag väljer A för att [motivering].
Edge cases att hantera: [lista].
\`\`\`

### Self-correction (OBLIGATORISKT efter kod)
Efter varje kodblock, fråga dig själv:
- Är detta produktionsklar kod? Finns det edge cases jag missade?
- Hanterar jag alla felfall?
- Skulle en senior ingenjör godkänna detta?
Om svaret är nej på något — skriv om koden.

### Rapporteringsformat
**Vid start:**
## 🔍 Analyserar: [vad du ser]
*arkitektur, tech stack, nyckelobservationer*

**Vid implementation:**
## ✅ [Feature] — implementerat
- **Vad:** exakt vad som gjordes (filnamn, radnummer)
- **Varför:** motivering till valet
- **Testa:** hur du verifierar det

**Vid problem:**
## ⚠️ Problem: [exakt beskrivning]
*rotorsak, vad du hittat, hur du löser det*

**Vid avslut:**
## 🎯 Uppgift klar — verifierad
### Vad som gjordes
- [konkret punkt 1 med filnamn]
- [konkret punkt 2 med filnamn]
### Verifiering
- Tester: [resultat]
- Build: [resultat]`
```

- [ ] **Step 2: Verify**
```bash
node --check navi-brain/code-agent.js
```

- [ ] **Step 3: Commit**
```bash
git add navi-brain/code-agent.js
git commit -m "feat(code-agent): upgrade system prompt — chain-of-thought, self-correction, senior-engineer communication"
```

---

## Task 8: Add usage tracking to `RUN_FINISHED`

**Files:**
- Modify: `navi-brain/code-agent.js` — track token counts per session, emit in RUN_FINISHED

- [ ] **Step 1: Add token accumulator to CodeSession**

In `CodeSession` constructor, add:
```javascript
    this._inputTokens  = 0;
    this._outputTokens = 0;
```

- [ ] **Step 2: Capture usage from OpenRouter SSE stream in `streamOpenRouter()`**

OpenRouter sends usage in the final data chunk as `json.usage.prompt_tokens` and `json.usage.completion_tokens`. In the existing `res.on('data', ...)` parsing loop (line ~714), the code processes `json.choices[0]` but discards `json.usage`. Add a `lastUsage` variable:

**Add before the `res.on('data', ...)` block** (after `let stopReason = null;`):
```javascript
      let lastUsage = null;
```

**Inside the for loop that processes SSE lines** (after the `try { const json = JSON.parse(raw); ...` block), add before `} catch {}`:
```javascript
            // Capture usage from any chunk that has it (OpenRouter sends it in the final chunk)
            if (json.usage) {
              lastUsage = json.usage;
            }
```

**In `res.on('end', ...)` resolve call** (line ~758), change:
```javascript
        resolve({ fullText, toolCalls, stopReason });
```
To:
```javascript
        resolve({ fullText, toolCalls, stopReason, usage: lastUsage });
```

**After each `await streamOpenRouter(...)` call in the run loop**, add:
```javascript
    if (streamResult.usage) {
      session._inputTokens  += streamResult.usage.prompt_tokens     || 0;
      session._outputTokens += streamResult.usage.completion_tokens || 0;
    }
```

- [ ] **Step 3: Include usage in `RUN_FINISHED` event**

Find where `RUN_FINISHED` is emitted and add:
```javascript
session.emit({
  type: 'RUN_FINISHED',
  summary: '...',
  usage: {
    inputTokens:  session._inputTokens,
    outputTokens: session._outputTokens,
    model:        session.model,
  },
});
```

- [ ] **Step 4: Verify**
```bash
node --check navi-brain/code-agent.js
```

- [ ] **Step 5: Commit**
```bash
git add navi-brain/code-agent.js
git commit -m "feat(code-agent): emit usage{inputTokens, outputTokens, model} in RUN_FINISHED"
```

---

## Task 9: Session resume — snapshot endpoint + START message extensions

**Files:**
- Modify: `navi-brain/server.js` — add snapshot endpoint + handle inheritSessionId/contextSnapshot in START handler
- Modify: `navi-brain/code-agent.js` — handle contextSnapshot in session initialization

- [ ] **Step 1: Add snapshot endpoint to `server.js`**

Find the existing `/code/sessions` GET endpoint. Add after it:

```javascript
// GET /code/sessions/:id/snapshot — returns live state of session workDir
app.get('/code/sessions/:id/snapshot', auth, async (req, res) => {
  const session = codeAgent.getSession(req.params.id);
  if (!session) return res.status(404).json({ error: 'Session not found' });
  const workDir = session.workDir;
  if (!fs.existsSync(workDir)) return res.status(400).json({ error: 'workDir does not exist' });

  try {
    const [fileTree, gitLog, gitStatus] = await Promise.all([
      execPromise(`find "${workDir}" -type f -not -path "*/.git/*" -not -path "*/node_modules/*" | sort | head -100`, { timeout: 8000 }).catch(() => ''),
      execPromise(`git -C "${workDir}" log --oneline -10`, { timeout: 5000 }).catch(() => '(no git history)'),
      execPromise(`git -C "${workDir}" status --short`, { timeout: 5000 }).catch(() => '(no git status)'),
    ]);
    res.json({ fileTree, gitLog, gitStatus });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});
```

Note: `execPromise` is a promisified `exec` — use existing `asyncExec` or add a local wrapper.

- [ ] **Step 2: Handle `contextSnapshot` and `inheritSessionId` in START message handler**

In the WebSocket message handler where `type === 'START'` is processed, after the session is created and before `session.run()` is called:

```javascript
    if (msg.inheritSessionId) {
      session.parentSessionId = msg.inheritSessionId;
    }
    if (msg.contextSnapshot) {
      const snap = msg.contextSnapshot;
      const contextMsg = `[Ärvd kontext från föregående session]\n\nFilstruktur:\n${snap.fileTree || ''}\n\nGit-historik:\n${snap.gitLog || ''}\n\nGit-status:\n${snap.gitStatus || ''}`;
      // ⚠️ role:'system' not allowed in Anthropic messages array — use role:'user' with prefix
      session.messages.unshift({ role: 'user', content: `[SYSTEM: ${contextMsg}]` });
    }
```

- [ ] **Step 3: Export `getSession` from code-agent.js**

At the bottom of `code-agent.js` in the `module.exports`, add `getSession`:
```javascript
module.exports = {
  // ... existing exports ...
  getSession: (id) => codeSessions[id] || null,
};
```

- [ ] **Step 4: Verify both files**
```bash
node --check navi-brain/code-agent.js && node --check navi-brain/server.js
```

- [ ] **Step 5: Commit**
```bash
git add navi-brain/code-agent.js navi-brain/server.js
git commit -m "feat(code-agent): session resume — snapshot endpoint + contextSnapshot injection"
```

---

## Task 10: Deploy and verify

- [ ] **Step 1: Deploy to server**
```bash
cd navi-brain && bash deploy.sh
```

- [ ] **Step 2: Check server is running**
```bash
curl -H 'x-api-key: navi-brain-2026' http://209.38.98.107:3001/
```
Expected: JSON with version and uptime.

- [ ] **Step 3: Check sessions endpoint**
```bash
curl -H 'x-api-key: navi-brain-2026' http://209.38.98.107:3001/code/sessions
```
Expected: JSON array (may be empty).

- [ ] **Step 4: Check server logs for startup errors**
```bash
ssh root@209.38.98.107 'pm2 logs navi-brain --lines 30 --nostream'
```
Expected: No errors, `Navi Brain listening on port 3001`.

- [ ] **Step 5: Final commit with version bump**
```bash
git add navi-brain/
git commit -m "chore: deploy code-agent v3.5 — 5 new tools, PlannerAgent, ReviewerAgent, session resume"
```
