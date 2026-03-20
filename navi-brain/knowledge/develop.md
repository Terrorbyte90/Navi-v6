# NAVI — DEVELOP MODE
**Trigger:** User asks to build, add, improve, or develop a feature or project.

---

## WHEN THIS FILE IS ACTIVE

Load this when the request involves:
- Adding a new feature to an existing project
- Developing a specific component or module
- Improving or extending existing functionality
- Building something within a known project context

---

## DEVELOP PROTOCOL

### Phase 1 — Project Discovery
**NEVER skip this step, even if you think you know the project.**

```
1. Identify which project the user is referring to
2. Find the latest version:
   a. Check GitHub — list all branches, identify the active feature branch
   b. Check server filesystem for cloned repos
   c. Check iCloud if relevant
   d. The latest work is often NOT on main — check ALL branches
3. Clone or pull the latest version to work from
4. Read the project structure — understand what exists before touching anything
```

```bash
# Standard discovery commands
gh repo list --limit 50
gh repo view [repo-name] --json defaultBranchRef,branches
gh api repos/[owner]/[repo]/branches
git clone [repo] && cd [repo] && git branch -a
git log --oneline -20  # Understand recent work
```

### Phase 2 — Deep Codebase Understanding
```
1. Read the main entry points (AppDelegate, main.swift, index.ts, etc.)
2. Understand the architecture pattern being used
3. Identify the state management approach
4. Note the coding style, naming conventions, existing patterns
5. Find any CLAUDE.md, README, or documentation files
6. Understand what's already built vs. what's needed
```

**Key questions to answer:**
- What design patterns are in use? (MVVM, Redux, etc.)
- What dependencies exist?
- What's the build/test setup?
- Are there any obvious issues or TODOs already in the code?

### Phase 3 — Feature Planning
```
1. Define exactly what needs to be built
2. Identify which existing files will be modified
3. Identify what new files need to be created
4. Consider: edge cases, error handling, performance
5. Research best practices for this specific type of feature
6. Write a concrete implementation plan
```

**Always ask before implementing if:**
- The scope is larger than expected
- There are multiple valid implementation approaches with real tradeoffs
- The feature would require architectural changes

### Phase 4 — Implementation
```
1. Work on the correct branch (never main without asking)
2. Implement in logical chunks — don't write everything at once
3. Follow the existing code style exactly
4. Handle errors properly — not just the happy path
5. Add comments only where logic is non-obvious
6. Test as you go (build, run, verify)
```

### Phase 5 — Verification
```
1. Does it compile/build without errors?
2. Does it do what was asked?
3. Does it break anything existing?
4. Is the code consistent with the rest of the project?
5. Are there any obvious edge cases unhandled?
```

### Phase 6 — Report
```
Summarize in Swedish:
- What was built
- Which files were changed/created
- Any decisions made and why
- Any known limitations or follow-up items
- Next logical step
```

---

## iOS/SWIFTUI STANDARDS

Since most projects are iOS/macOS SwiftUI:

```swift
// Architecture: MVVM unless project uses something else
// State: @State, @StateObject, @ObservableObject / @Observable (iOS 17+)
// Async: async/await — never completion handlers in new code
// UI: SwiftUI native — never UIKit unless bridging existing code
// Data: SwiftData preferred for new projects, CoreData if existing
// Design: Follow the project's existing design system exactly
```

**Premium UI checklist:**
- [ ] Smooth animations (`withAnimation`, `.animation`)
- [ ] Proper loading states (ProgressView, skeleton screens)
- [ ] Error states handled gracefully
- [ ] Empty states designed, not just absent
- [ ] Haptic feedback where appropriate
- [ ] Dynamic Type support
- [ ] Dark mode works correctly

---

## GIT WORKFLOW

```bash
# Before starting
git fetch --all
git branch -a  # See ALL branches

# Create feature branch if needed
git checkout -b feature/[descriptive-name]

# Commit as you go — never one giant commit
git add -p  # Stage selectively
git commit -m "feat: [what it does]"

# Never force push to main
# Never push without user confirmation for shared branches
```

---

## RESEARCH INTEGRATION

If the feature requires technology you're unfamiliar with:
1. Research it first (load research.md logic)
2. Find the best implementation approach
3. Find examples of it done well
4. Then implement

Don't guess at APIs or library usage — look it up.

---

*Ladda newproject.md istället om det är ett helt nytt projekt.*
*Ladda debug.md om du stöter på problem under implementation.*

---

## Navi-v6 Specifika Mönster

### iOS-bygge och verifiering
```bash
# Verifiera Swift-kompilering på server (om xcodebuild finns):
run_command("xcodebuild -scheme 'Navi-iOS' -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -30")

# Verifiera server-kod:
run_command("cd /root/navi-brain && node -e \"require('./code-agent')\" 2>&1")

# Restart server och kolla loggar:
run_command("pm2 restart navi-brain && sleep 3 && pm2 logs navi-brain --lines 20 --nostream")
```

### SwiftUI-mönster (detta projekt)
- Använd `NaviTheme.bodyFont(size:)` och `NaviTheme.headingFont(size:)` — inte `.font(.system(...))`
- Färger: `.accentNavi`, `Color.chatBackground`, `Color.userBubble`, `Color.inputBackground`, `Color.sidebarBackground`
- Animationer: `NaviTheme.Spring.smooth`, `NaviTheme.Spring.quick`
- Platform-guards: `#if os(iOS) ... #else ... #endif` för plattformspecifik kod

### Server-mönster (detta projekt)
- Alla routes kräver `auth` middleware
- WebSocket-events: `session.emit({ type: 'EVENT_TYPE', ...data })`
- Persistens: `saveSessions()`, `saveTasks()` — anropas automatiskt var 60:e sekund
- Loggning: `addLog('KATEGORI', 'Beskrivning', 'projekt', tokens?)`
