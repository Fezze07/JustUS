---
name: fix-workflow
description: Project rules for the fixing phase of this repo - how to implement, document, verify, report and commit a bug fix tracked in todo.md. Use when asked to fix an item, resolve or implement a fix, work on the fixing phase, update the docs after a change, mark a todo item as done, or commit/push a fix. Triggers on "fix 2.4", "fix this item", "resolve the bug in todo.md", "finish the fixing phase", "update the docs", "commit the fix".
risk: unknown
source: local
version: "1.0"
tags: [workflow, fixing-phase, todo, documentation, verification, commit, rules]
---

# Fixing Phase Workflow

The rules that govern every change in this repo. `todo.md` (repo root) is the task list; `docs/**` is the documentation; this file is the process.

**One item at a time, with explicit user consent.** Never start the next item, and never batch items, unless asked.

---

## 1. The loop

1. **Pick only one item** from `todo.md`. The user must decide it.
2. **Consult the sources** the item lists (`docs/**` files, `.agents/skills/**`, the finding doc and its finding ID). The item's `Sources` line tells you which doc claims the defect exists.
3. **Re-verify the defect before changing anything.** Item text can be stale — the code may already be clean, or the file/line may have moved. An item that turns out to be already correct is closed with `**Status: ✅ ALREADY CLEAN (verified YYYY-MM-DD)**` and nothing else. Never "fix" what is not broken.
4. **Implement the fix**, following the item's `Fix` field. If the item is ambiguous or the right fix is a choice, decide, state the chosen option and the reason in the status line, and say what you deliberately did not change.
5. **Update every affected doc/test** (`docs/** and Backend/test - Flutter/test - supabase/test`) so it describes the new implementation: no stale descriptions, line references, tables, status matrices or flow diagrams. See §2.
6. **Verify** with the tooling in §5 before reporting the item complete.
7. **Write the status line** in `todo.md` (§4) and tick the box — always both, never one alone.
8. **Commit the code, the updated docs and `todo.md`, then push to `origin/dev`** (short message, ≤ 15 words, existing `type(scope): …` style).
9. **Schema changes also go to the remote database.** This repo has no tracked `supabase/migrations/`; `supabase/schemas/**` is the source of truth. After editing any schema SQL (tables, functions, views, policies), apply it to the linked remote project so it matches the commit:
   `npx supabase@3.0.0 db query --remote --yes --file <script>.sql`
   (CLI 3 targets the local stack by default, so `--remote` is required; `--yes` covers the hosted-write confirmation. Needs `supabase login`, so if not working ask user for it). A SQL-only edit is not a finished item.

---

## 2. Documentation rules

1. **Never write "RESOLVED" / "FIXED" entries inside a doc's findings section** (e.g. "Potential Bugs and Inconsistencies", "Discovered Bugs, Defects and Inconsistencies").
2. **When a bug is fixed, remove it entirely** from that findings section.
3. Keep a finding in place only if a **different possible bug can still happen**; then rewrite it to describe the *remaining* bug, never the fixed one. Example: the dual-refresh race stays documented as a still-possible concurrency bug (architecture `F8`) while the fixed token-desync finding is removed.
4. `todo.md` is the single place that tracks status (`[x]`, status lines). Docs describe **current behavior, not history** — no changelogs, no "what we fixed" sections.
5. Renumber a findings section after a removal, and fix every cross-reference to the renumbered IDs (other docs, `todo.md`'s § Open finding IDs). Leaving a dangling `F-SC9` pointer is a doc bug.
6. Update the doc's **status matrix / implementation status table** and test tables when the change moves an item from "not implemented" to implemented. A stale matrix is the most common leftover.
7. When a doc is the *source* of the finding, close the loop there: the finding leaves the doc, and the resolution is recorded in `todo.md` only.

---

## 3. Code rules

1. Do **not** add code comments unless explicitly requested.
2. Do **not** create branches unless explicitly requested; commits and pushes follow the loop in §1.
3. Follow existing code conventions and verify changes compile/lint clean.
5. No drive-by refactors, reformatting or renames outside the item's scope. A follow-up belongs in `todo.md`.

---

## 4. Status line

Canonical form:

    **Status: ✅ FIXED (YYYY-MM-DD, on `branch`)** — what changed, with `file:line` · **Verification**: command + result · **Residual**: what can still break

- **Date + branch** are mandatory.
- **What changed**: the decision, not a diff summary. Include the option you chose and why when there was one.
- **Verification**: the command you ran and its result (`flutter analyze` clean, `flutter test` 95 pass, 1/1 finding, `grep` 0 call sites). A status line without verification is incomplete.
- **Residual**: what can still break, what was deliberately left out of scope, and any new item ID the fix creates.
- Tick `[x]` **and** add the line in the same edit.

Variants: `✅ ALREADY CLEAN (verified YYYY-MM-DD)` · `⚠️ PARTIAL (…)` (say what remains) · `⏭️ SUPERSEDED BY N.M` · `🚫 WON'T FIX (reason, and who decided)`.

Also update the header sentence at the top of `todo.md` when items complete, and the "Suggested fix order" markers when a sprint advances.

---

## 5. Verification

Run the narrowest command that proves the change, plus the broad suite when the change is structural.

| Change | Minimum verification |
| :--- | :--- |
| Dart/Flutter code | `flutter analyze` (must be clean) + `flutter test` (or the single test file) |
| Localization (ARB / `AppLocalizations`) | `flutter gen-l10n` + `flutter analyze` — every new key in **all** locales |
| Backend JS | `cd Backend && npm test`; `npm run lint` if style-sensitive |
| SQL / RLS / RPC | apply to the linked remote DB (§1.9) + a query that exercises the new path; add a policy assertion test (tracked in Phase 8) |
| New endpoint / route | backend test hitting the route + client call site updated + both sides of the contract (path, signature, error codes) verified |
| Docs only | re-read every factual claim you touched against the code — a doc fix is verified by grep, not by tests |
| Structural / cross-cutting | root `npm run validate` (backend lint + circular-dependency + syntax + Jest, `jscpd` duplication scan, `flutter analyze` + hardcoded-string check + Flutter tests) |

Record the exact command and result in the status line. If something could not be run (no credentials, no device, no Docker), say so in the item instead of implying success.

The commit re-runs all of this anyway (§6) — so use this section to get a fast answer while iterating, and let the hook be the backstop.

---

## 6. Commit rules

`.husky/pre-commit` is exactly:

    git add Flutter/lib/all_imports.dart Backend/all_imports.js

Two things to expect:

- **The hook stages the two barrel files itself.** If your change added or removed anything `lib/` exports, the regenerated `all_imports.*` belongs in the same commit — check `git status` afterwards and include what the hook added.

- Commit code + every updated doc + `todo.md` together.
- Message: `type(scope): short summary`, ≤ 15 words, imperative, matching the existing log (`fix(nav): …`, `feat(auth): …`, `chore(dead-code): …`, `refactor(theme): …`).
- Push to `origin/dev` after the item is complete. No force-push, no history rewriting, no `--no-verify`.
- Check `git status` before staging; stage only the files this item touched. Unrelated pre-existing modifications stay untouched.

---

## 7. Guardrails

- **Do not trust the item text.** Re-read the code. Items get renumbered, superseded, or invalidated by earlier fixes (see the `ALREADY CLEAN` precedents in `todo.md`).
- **Do not mark an item done on a partial fix** without a `⚠️ PARTIAL` line naming exactly what remains.
- **Do not leave a doc describing the old behavior**, and do not "fix" a doc that is right about intended behavior while the code is wrong.
- **Do not expand scope.** If the fix reveals a second defect, add it to `todo.md` (new item, correct phase, priority) and mention the new ID as **Residual**.
- **Do not skip the source doc.** The item's `Sources` line is where the intended behavior is written down; contradicting it is a design decision, not a free choice.
- **One item, one commit, one push.** Ask before starting the next.

## 8. Related skills

- `.agents/skills/archive-fix-item` — the last step of the loop: move a closed item from `todo.md` into `docs/fixing-phase-log.md` and keep the log's format.
- `.agents/skills/codebase-audit` — how findings are discovered and how the report (`todo.md` + `docs/audits/<name>.md`) is structured. Read before adding or restructuring items.
- `.agents/skills/testing-implementation` — the test runner, mock services and infrastructure.
- `.agents/skills/supabase` — schema, RLS and Auth work; pair with §1.9 for applying changes to the remote project.
- `.agents/skills/security-hardening` — request signing, JWT validation, RBAC and abuse controls.
