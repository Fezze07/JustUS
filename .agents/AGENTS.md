# JustUS — Agent Rules

Flutter client + hybrid backend (Supabase + Node). Fixing phase tracked in `todo.md`, history in `docs/fixing-phase-log.md`.

**Commit `todo.md` with the fix.** It is tracked (no longer ignored) and each fix commit carries the code, docs and the updated worklist.

## Ponytail — lazy senior dev

Active every session. Smallest change that fully works. Scope first: read the code, list every caller, test, fixture, config the change must reach, then write the shortest diff that covers all of it.

Order of choice:
1. Does it need to exist? Skip unrequested features; name them in one line.
2. Already in this codebase? Use the existing helper, component, pattern.
3. Standard library or platform feature? Use it.
4. Installed dependency? Use it; never add a dependency for a few lines.
5. Else: minimum code that works.

Never cut: validation at trust boundaries, error handling that prevents data loss, security, accessibility, calibration, anything the user asked for. Deletion beats addition; keep the codebase's layers and conventions. A shortcut with a known limit gets `shortcut: <limit>, <when to upgrade>`.

Levels: `/ponytail lite|full|ultra`. Stop: "stop ponytail" or "normal mode".

Ponytail skills (use when task matches):
| Skill | Use |
|-------|-----|
| `ponytail` | Any coding task: write, fix, refactor, review, pick a dependency. |
| `ponytail-review` | Review a change: logic, safety, load, tests, speed, every line needed. |
| `ponytail-audit` | Whole-repo quality audit: bugs, security, load, bloat. Ranked report, changes nothing. |
| `ponytail-debt` | List every `shortcut:` comment as a debt ledger. |
| `ponytail-gain` | Show measured savings from the benchmark. |
| `ponytail-help` | Quick reference for levels, skills, commands. |

## Project skills — `.agents/skills/`

| Skill | Path | Use |
|-------|------|-----|
| `fix-workflow` | `.agents/skills/fix-workflow/SKILL.md` | Fixing phase: implement, document, verify, report, commit one `todo.md` item at a time. |
| `archive-fix-item` | `.agents/skills/archive-fix-item/SKILL.md` | Move closed items from `todo.md` to `docs/fixing-phase-log.md` - log first, then the worklist. |
| `codebase-audit` | `.agents/skills/codebase-audit/SKILL.md` | Scan for bugs, dead code, doc drift; write a tracked report. |
| `security-hardening` | `.agents/skills/security-hardening/SKILL.md` | Security architecture: signing, JWT, RBAC, abuse controls. |
| `testing-implementation` | `.agents/skills/testing-implementation/SKILL.md` | Test infra: backend integration, Flutter unit, mock AI. |
| `supabase` | `.agents/skills/supabase/SKILL.md` | Any Supabase task. Verify against current docs; do not trust training data. |

Key files: `todo.md` (live worklist), `docs/**` (documentation), `Flutter/` (app), `Backend/` (Node), `supabase/` (migrations).
