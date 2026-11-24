---
name: codebase-audit
description: Use when asked to scan, audit, analyze or review a codebase for bugs, defects, dead code, security gaps or documentation drift, and to turn the result into a tracked report such as todo.md. Triggers on "find all the bugs", "audit the code", "codebase scan", "bug hunt", "review this repo", "what is broken", "check for dead code", "docs out of date", "generate a fix plan / report findings".
risk: unknown
source: local
version: "1.0"
tags: [audit, bug-hunt, code-review, dead-code, doc-drift, security, reporting, todo]
---

# Codebase Audit & Defect Report

Two deliverables, always in this order:

1. **Evidence** — every defect verified in the *live working tree*, cited as `file:line` plus the actual code.
2. **A report the next agent can execute** — a tracked list (`todo.md`) and/or an evidence doc (`docs/audits/<name>.md`) where each item states the defect, the concrete fix and how to tell it is done, so nobody has to re-derive the analysis.

A scan that produces prose instead of an executable item list is not finished.

---

## 1. Non-negotiables

1. **Evidence or it does not exist.** Each finding carries `file:line`, a quote or paraphrase of the real code, and the end-to-end failure scenario. A line number quoted *by a doc* is a claim to be re-verified, never evidence.
2. **Search for the consumer before calling anything dead.** Prove the negative across the whole repo: identifier, barrel files, dynamic/string use, SQL, tests, configs, env templates, workflows. A capability, flag, key or dependency is only dead when nothing reads it *and* nothing needs it (a schema column read by a Postgres view is not dead).
3. **Code is the truth; docs are the claim under test.** Never infer current behavior from documentation.
4. **Check both sides of every contract.** client ↔ backend, app ↔ DB policy, env template ↔ env loader, doc ↔ code, test ↔ command that runs it. Most real defects live exactly on the seam.
5. **Execute before you assert.** Prefer `flutter analyze`, `flutter test`, `npm test`, `npm run lint`, a SQL query, a throwaway script over reasoning. If a claim cannot be executed here (needs credentials, a device, a live backend), label it in the item: `Unverified — needs <what>`.
6. **Separate bug from decision.** Behavior that is deliberate is a documentation fix, not a code fix. Record the evidence that made it deliberate (a comment, a config value, an audit doc) so the next scan does not re-raise it.
7. **No speculative findings.** If you cannot name the trigger conditions and the user-visible symptom, it is not a finding — it is a suspicion. Put suspicions in a clearly separate "not confirmed" list.
8. **Status lives in exactly one place** — the tracking file. Findings docs describe *current* behavior and never accumulate history (see §6.4).

---

## 2. Phase A — Baseline and inventory (report as Phase 0)

Produce these before hunting, because they decide what you can prove later:

- **Component map**: each deployable unit, its entry point, its config loader, its public surface.
- **Contracts**: client→API route list, API→DB tables/RPCs, env var → consumer mapping (loader, defaults, fail-fast behavior).
- **Test entry points**: the real commands, not the documented ones; and the current pass/fail state.
- **Unverifiable surfaces**: live DB, R2, FCM, OAuth, device builds. List them; items touching them get the `Unverified` label.
- **Branch strategy**: what stays green while fixes land.

---

## 3. Phase B — The passes

Run them in order. Each pass is scoped; each finding is re-verified in the next pass's context.

| # | Pass | Question it answers |
| :-- | :--- | :--- |
| 1 | Docs vs code | Where does the documentation describe a system that no longer exists? |
| 2 | Dead code & unused surface | What is declared, shipped or paid for but never reached? |
| 3 | Data layer | Can one user read or write another user's data? What leaks or is orphaned? |
| 4 | Backend services | Does configuration, auth and resource lifecycle fail safe? |
| 5 | Client state & UI | Does every feature actually work end-to-end for the user? |
| 6 | Cross-layer contracts | Do the layers still agree with each other after earlier changes? |
| 7 | Tests & tooling | Would the existing suite have caught any of this? |
| 8 | Triage | What is the real, deduplicated, ranked fix list? |

**Per-pass detail — look-for lists, evidence standards, traps, and grep recipes: `references/checks.md`.** Load it before running passes 1–7.

Report coverage in the deliverable, e.g. a coverage table with `pass → surfaces examined → findings → "clean, verified by <command/grep>"`. A pass that found nothing is a result and must be stated, not skipped.

---

## 4. Phase C — Triage (pass 8)

- **One defect = one item.** Merge duplicates across passes; cross-reference the doc IDs instead of repeating them.
- **Split composites.** If a finding contains independently fixable parts, split it into sibling items and leave a pointer. A single "profile settings is broken" finding becomes four items only when each can be fixed and verified on its own.
- **Cite symbols, not just lines.** `foo_bar():112-134` plus the file — line numbers drift as you fix earlier items; symbols do not.
- **Re-verify every reference at write time**, after all analysis edits are done.
- **Rank by user impact**: 🔴 breaks a core flow or leaks real user data · 🟠 significant functional or security gap · 🟡 degraded under specific conditions · 🟢 cleanup, docs, tests. Answer "who is hurt, how often, what do they see?" — if you cannot, it is 🟡 or 🟢.
- **Group into phases by theme**, not by file or by pass (auth, security/data, feature-blocking, sync correctness, leaks, UI/UX, hygiene, test gaps).
- **Keep a "known non-bugs / deliberate decisions" list** in the report so the next scan does not re-raise resolved questions.
- **Prefer 30 executable items over 200 speculative ones.** Depth beats breadth; a scan that stops at the first plausible smell is worse than useless.

---

## 5. Phase D — Produce the report

Two artifacts, choose by request:

| Artifact | Use for | Template |
| :--- | :--- | :--- |
| `todo.md` (repo root) | the executable fix list — phases, items, status | `references/report-template.md` §A |
| `docs/audits/<name>.md` | the evidence record — findings matrix + evidence | `references/report-template.md` §B |

Usually both: the audit doc is the *why*, `todo.md` is the *what now*.

### 5.1 Item anatomy

Full shape — use whenever Defect + Fix + Acceptance are needed:

    ### N.M Short imperative title (optional finding ID)
    - **Sources**: `path/doc.md:12-40` (F-ID), or "no doc — code review".
    - **Files**: `path/a.ext:12-34`, `path/b.ext`.
    - **Defect**: current behavior → expected behavior → trigger conditions → user impact.
    - **Fix**:
      1. Concrete change, file by file.
      2. When options exist, state the chosen one *and why*, plus what you decided not to change.
    - **Acceptance**: an observable scenario or command with a before/after. Never "works correctly".
    - **Status: ...** (only when done — see §5.3)

Chore shape — one line, for a deletion or mechanical edit:

    - [ ] **N.M Remove unused `thing`** — `file.ext:24` (`command`). Source `doc.md:25-33`.

### 5.2 Required sections in the tracking doc

Header block (purpose · current status sentence listing completed items · how to use · finding-ID prefixes · priority tags) · Phase 0 · themed phases with priority in the heading and a `✅ FIXED` roster in the heading once partially done · the finding-to-section index table · the batch/fix order with dependencies.

### 5.3 Status line grammar

    **Status: ✅ FIXED (YYYY-MM-DD, on `branch`)** — what changed, with `file:line` · **Verification**: command + result · **Residual**: what can still break

Variants:
- `**Status: ✅ ALREADY CLEAN (verified YYYY-MM-DD)**` — the item was stale; the code/docs already match. Keep the item: a later reader needs to know the question was asked and answered.
- `**Status: ⚠️ PARTIAL (…)**` — only part was fixable; name what remains.
- `**Status: ⏭️ SUPERSEDED BY N.M**` — another item absorbed it.
- `**Status: 🚫 WON'T FIX (reason)**` — with the user's decision recorded.

Never write `[x]` without a status line, or a status line without verification. The full writing rules for status lines live in `.agents/skills/fix-workflow/SKILL.md` §4 — that file is canonical; keep the two in sync if you change this one.

### 5.4 Forbidden in reports

- Status/"RESOLVED" text inside a findings doc — fixed findings are **removed** from the doc entirely; only `todo.md` remembers. If a *different* bug can still occur there, rewrite the finding to describe that remaining bug only.
- A finding doc that grows a "what we fixed" section.
- Copy-pasted evidence: quote the current code, not the doc's paraphrase of it.

---

## 6. Phase E — Self-review gate

Do not deliver until all of these hold:

- [ ] Every item has evidence, a concrete fix and an observable acceptance criterion.
- [ ] Every "dead" claim has a documented negative search (what you grepped, where).
- [ ] Every contract claim is checked on **both** sides.
- [ ] Every `file:line` was re-verified after the last analysis edit.
- [ ] Composite findings are split; duplicates merged with cross-references.
- [ ] Priorities have a stated user impact; nothing is 🔴 without a data-loss or core-flow argument.
- [ ] Deliberate behavior is labeled a decision, not a bug.
- [ ] Unverifiable-by-runtime items say so explicitly.
- [ ] Findings docs no longer contain any fixed item; the tracking doc contains all of them.
- [ ] The report states its own coverage, including the passes that came back clean.

---

## 7. Operating in this repo (JustUS)

- **Read `.agents/skills/fix-workflow/SKILL.md`** — it holds the project rules that govern any change (the fixing loop, doc rules, verification and commit discipline). Scan ≠ fix: this skill stops at the report; fixing stays one item at a time with explicit user consent.
- **`todo.md` is the single source of truth for status** and the canonical worked example of this format (header block, Phase 0, themed phases, index table, batch plan, status grammar).
- **Docs rules**: a fixed finding leaves the doc's findings section; `docs/**` describes current behavior only.
- **Commit `todo.md` with the work it tracks.**
- **Schema changes must reach the remote project** (`supabase/schemas/**` is the source of truth; apply with the Supabase CLI against the linked DB) — an item that only edits SQL is not done until that is done.
- **Verify with**: `npm run validate` (backend lint + circular-dependency + syntax + tests, jscpd, `flutter analyze` + hardcoded-string check + Flutter tests) or the narrow target (`flutter analyze`, `flutter test <file>`, `cd Backend && npm test`).
- Optional aid: if a `graphify-out/` knowledge graph exists, use a graph query to trace cross-file impact of a finding before triaging it.
