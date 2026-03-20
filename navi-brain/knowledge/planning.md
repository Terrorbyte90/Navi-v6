# NAVI — PLANNING MODE
**Trigger:** User wants a plan, roadmap, or structured approach before execution.

---

## WHEN THIS FILE IS ACTIVE

Load this when:
- "Planera [projekt/feature]"
- "Vad ska jag göra härnäst med [projekt]?"
- "Hjälp mig prioritera"
- "Skapa en roadmap"
- User wants structure before action, not immediate execution

---

## PLANNING PROTOCOL

### Understand the Goal
```
Before planning:
1. What is the END STATE? What does "done" look like?
2. What are the constraints? (time, skills, dependencies)
3. What's the priority order? (what matters most?)
4. What are the risks? (what could derail this?)
```

### Plan Structure

#### For projects (multiple weeks):
```
## [Project] Roadmap

### Fas 1: Foundation (Vecka 1)
Goal: [What this phase achieves]
[ ] Task 1 — [Description] — Est: [time]
[ ] Task 2 — [Description] — Est: [time]
Done when: [Clear definition]

### Fas 2: Core (Vecka 2–3)  
Goal: [What this phase achieves]
[ ] Task 3
[ ] Task 4
Done when: [Clear definition]

### Fas 3: Polish & Ship (Vecka 4)
[ ] Task 5
[ ] Task 6
Done when: [Ship criteria]

### Risker
- [Risk 1]: [Mitigation]
- [Risk 2]: [Mitigation]
```

#### For features (days):
```
## Plan: [Feature Name]

### Steg 1: [Name] (est: Xh)
[ ] Sub-task 1
[ ] Sub-task 2

### Steg 2: [Name] (est: Xh)
[ ] Sub-task 3

### Test
[ ] Verifiering 1
[ ] Verifiering 2

### Definition of done
- [Criterion 1]
- [Criterion 2]
```

---

## PROJECT HEALTH CHECK

When asked "vad ska jag göra härnäst?":

```
1. Read the project (GitHub, latest branch)
2. Check git log for recent work
3. Look for TODO/FIXME comments
4. Check any open GitHub issues
5. Assess current state: what's missing for the next meaningful milestone?

Report:
- Current status (1 sentence)
- Top 3 priorities (ordered)
- Quick wins (can be done in <1h)
- Blockers (if any)
```

---

## PRIORITIZATION FRAMEWORK

When there are many things to do:
```
Quadrant:
                    | Important     | Not Important
--------------------|---------------|---------------
Urgent              | DO NOW        | DELEGATE/SKIP
Not Urgent          | PLAN          | LATER/NEVER

For app development:
HIGH: Crashes, broken core flows, blocker for launch
MEDIUM: Missing features users expect, performance issues
LOW: Nice-to-have polish, edge cases, future features
```

---

*Planning alltid innan execution för Level 4–5 tasks.*
*Kombinera med develop.md när planen är godkänd.*
