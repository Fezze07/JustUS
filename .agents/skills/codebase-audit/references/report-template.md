# Report templates

Two skeletons: §A the executable tracking list (`todo.md`), §B the evidence record (`docs/audits/<name>.md`). Fill, do not invent structure — consistency is what makes the next scan cheap.

---

## §A — Tracking list (`todo.md`, repo root)

````markdown
# <Project> — Fixing Phase · Master Todo List

> **Purpose**: Track every defect verified against the live codebase and the reverse-engineering documentation in `docs/`.
> Every item below has been re-verified in the current working tree (branch `<branch>`). Items completed carry a **Status: ✅ FIXED** line or a `✅ FIXED` marker (<list completed IDs> done); everything else is still open.
>
> **How to use**: tick `[ ]` → `[x]` as you complete an item. Each item lists the source doc(s), target file:line, the exact defect, the concrete fix, and acceptance criteria.
>
> **Finding-ID prefixes** (from the docs): `F-XX` <area> …
>
> **Priority tags**:
> - 🔴 `CRITICAL` — breaks core flows or leaks data for real users
> - 🟠 `HIGH` — significant functional defect / security gap
> - 🟡 `MEDIUM` — degraded UX / correctness under specific conditions
> - 🟢 `LOW` — cleanup, dead code, docs, test coverage

---

## Phase 0 — Ground truth & safety net (do first)

- [ ] **0.1 Baseline test run before touching anything**
  - Run `<real command>` and record the pass/fail baseline.
  - Docs: `<sources>`.
  - Acceptance: you know exactly which tests pass today; diff against this baseline after each fix.

- [ ] **0.2 Verify git branch strategy for the fixing phase**
  - Work in short-lived branches off `<main branch>`; one branch per Phase-1 item.
  - Acceptance: `<main branch>` stays green after each merge.

---

## Phase 1 — <Theme> (🔴 CRITICAL)

### 1.1 <Short imperative title> (optional finding ID)
- **Sources**: `docs/<area>/doc.md:12-40` (F-XX), or "no doc — code review".
- **Files**: `path/a.ext:12-34`, `path/b.ext`.
- **Defect**: <current behavior> → <expected behavior>. <Trigger conditions>. <User-visible impact>.
- **Fix**:
  1. <Concrete change, file by file.>
  2. <Chosen option and why; what you decided not to change.>
- **Acceptance**: <observable scenario or command with a before/after.>
- **Status: ✅ FIXED (YYYY-MM-DD, on `branch`)** — <what changed, `file:line`>. **Verification**: `<command>` (<result>). **Residual**: <what can still break>.

## Phase 2 — <Theme> (🟠 HIGH / 🟡 MEDIUM; 2.1 ✅ FIXED, 2.2 ✅, rest open)

- [x] **2.3 Chore-shaped item** — `file.ext:24` (`command`). Source `doc.md:25-33`.
  - **Status: ✅ FIXED (YYYY-MM-DD, on `branch`)** — <what changed>. **Verification**: `<command>` (<result>).

## Phase 8 — Testing gaps (quality gate; 🔴 for regression safety)

- [ ] **8.1 <missing coverage>** — cover 1.1/1.2: <scenarios to assert>.
- [ ] **8.N CI wiring** — <which workflow, which job, which gates>.

---

## Finding-to-section index

Kept only while the items are open. When an item is archived into `docs/fixing-phase-log.md`, its row leaves this table (see `.agents/skills/archive-fix-item/SKILL.md`); the section is dropped when the table is empty.

| ID(s) | Section | ID(s) | Section |
| :--- | :--- | :--- | :--- |
| <doc finding IDs> | 1.1, 1.2 | <other IDs> | 4.x, 7.5 |
| <audit doc name> | Phase 7 | <profile bugs> | 3.1, 3.7 |

---

## Suggested fix order (batch plan)

1. **Sprint A (<theme>)** — 1.1 → 1.2 → 1.3 (+ 8.1 tests). <Why they must ship together.>
2. **Sprint B (<theme>)** — 2.1 → 2.2 (+ 8.2 tests). <DB/remote prerequisites.>
3. **Ongoing** — Phase 8 tests folded into every sprint; CI gate enabled at Sprint B.

## Known non-bugs & deliberate decisions

- **<Behavior>** — deliberate. <Evidence: doc line / config value / comment.> Do not "fix".
- **<Item 7.x>** — reported from doc <X>, re-verified on <date>: no such code exists. Closed as stale.

> Keep this file at the repo root. Update it as findings are fixed; re-verify each item's "Acceptance" line before ticking. **Commit this file with the fix.**
````

### Item shape rules

- Full `###` shape when the fix needs a decision or spans files; one-line `- [ ]` shape for a deletion/mechanical edit.
- Check the box and add the status line **together**; never one without the other.
- Status-line variants: `✅ ALREADY CLEAN (verified DATE)`, `⚠️ PARTIAL (…)`, `⏭️ SUPERSEDED BY N.M`, `🚫 WON'T FIX (reason)`.
- A stale item keeps its number and gains a status line — do not delete items from the tracking file (only from findings docs).
- When an item is split, leave a pointer line: `> 3.1 was split into 3.5 / 3.7 / 3.8 / 3.10.`

---

## §B — Evidence record (`docs/audits/<name>.md`)

````markdown
# <Area> Audit

## Executive Summary

<What was evaluated, across which layers, and the headline result.>

All findings are backed by empirical code search and file analysis across <layers>.

---

## Findings Matrix Summary

| Category | Item | Location | Current Status | Risk / Impact |
| :--- | :--- | :--- | :--- | :--- |
| **<Category>** | <one-line item> | [`file.ext:12`](<link>) | **OPEN / STALE** (<why>) | <Severity> (<impact>) |

---

## Detailed Investigation

### 1. <Finding title>

* **File**: [`path`](<link>)
* **Stale Lines**:
  - Line 23: `<exact quoted text>`
* **Actual Code Implementation**:
  - [`path:27-36`](<link>):
    ```<lang>
    <short verbatim excerpt>
    ```
* **Classification**: **<STALE DOCUMENTATION | DEAD CODE | BUG | SECURITY | LEAK | RACE | MISSING UI | DRIFT | TEST GAP>**
* **Impact**: <who is affected, how, how often>
* **Remediation**: <one line, matching the tracking item>

---

## Recommended Cleanup Action Plan

1. **`<file>`**:
   - <action>

---

## Coverage

| Pass | Surfaces examined | Result |
| :--- | :--- | :--- |
| 1 Docs vs code | `<files>` | 1 finding |
| 3 Data layer | `<tables>` | Clean — verified by <query/grep> |
````

### Evidence-doc rules

- Findings sections describe **current** behavior only. When an item is fixed, **delete it from this file** (see the project's documentation rules); only the tracking file records that it existed.
- A finding stays here only if a **different** bug can still occur — then rewrite it to describe the remaining bug, not the fixed one.
- Never add a "Resolved" section listing what was fixed; an empty matrix plus a pointer to the tracking file is the correct end state.
- Quote the code verbatim; do not paraphrase the doc's own description of the code.
- Add a `## Coverage` table so a future reader knows which passes were clean and how that was proven.
