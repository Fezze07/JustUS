# `docs/fixing-phase-log.md` — format

The shape of the closed-history file, copied from the file as it stands. Match it exactly: same headings, same column order, same outcome vocabulary, same punctuation. When in doubt, read `docs/fixing-phase-log.md` itself — this reference only describes it.

The file has **three** sections, in this order, plus the intro block:

1. `## Outcome by phase`
2. `## Item index`
3. `## Decisions of record`

Anything else (a finding-to-section index, a retired-findings list, a per-item narrative, a tests-added table, a status summary) does not belong here.

---

## Intro block

Three bolded sentences, before the first `---`, in this order. No counts, no phase ranges, no claims about what is closed.

```markdown
**What this is**: the permanent record of the closed fixing work on `dev` — every item and the decisions of record. Nothing open is tracked here (that lives in `todo.md`).

**Relationship to `todo.md`**: `todo.md` is the *live worklist* (tracked, see `.agents/skills/fix-workflow/SKILL.md`). This file is the *closed history*: what was found, what was decided, and where the reasoning now lives. When `todo.md` is retired, this file plus `git log` are what remain.

**How it was produced**: a layered scan of the codebase (docs-vs-code drift, dead code, RLS/data layer, backend services, client state, cross-layer contracts, test gaps) that produced one item per independently-fixable defect, each with `file:line` evidence, a concrete fix and an observable acceptance criterion. Items were fixed one at a time, each with its own commit.
```

> The intro is descriptive prose, not a status block. If a section it names no longer exists, edit the sentence; do not append a new claim.

---

## Outcome by phase

One row per phase, in phase order. Housekeeping phases (phase 0) are **not** archived and get no row.

```markdown
| Phase | Theme | Items | Outcome |
| :--- | :--- | :--- | :--- |
| 1 | Auth & session integrity | 1.1–1.6 | All fixed. Session ownership consolidated on the Supabase SDK; the backend refresh proxy was deleted |
| 5 | Data retention & media leaks | 5.1–5.6 | 5 fixed, 5.4 closed as *not a defect* (the 15 MB pre-compression cap is intended). R2 orphan sweep, thumbnails, audio/PDF |
| 7 | Dead code & docs hygiene | 7.1–7.9 | All fixed. 7.7 closed as *already clean* (stale item). README rebuilt against the code |
| 8 | Testing gaps | 8.1–8.8 | Still open — the only substantive work carried forward in `todo.md` |
```

- **Phase**: bare integer, no `P`.
- **Items**: the ID range with an en dash (`1.1–1.6`); list non-contiguous IDs comma-separated in numeric order (`2.1–2.4, 2.6, 2.8`).
- **Outcome**: a lead phrase, then a period, then the notable mechanisms of that phase. The lead phrase is one of `All fixed.` · `N fixed, M closed as *not a defect* (…)` · `Still open — carried in todo.md`.
- A phase that is fully closed never keeps a `Still open` note; a phase with open items must keep one.
- `N` counts the items closed as fixed; the ones closed as *not a defect* are counted separately in the same lead phrase. The `Items` cell lists every archived ID of the phase, fixed or not.
- A phase archived in a batch writes the whole range at once: `10.1–10.5, 10.8–10.21`.

---

## Item index

The mandatory section. One row per archived item.

Legend line directly under the heading:

```markdown
`Outcome`: **Fixed** = code changed · **Clean** = the item was stale, nothing to do · **By design** = not a defect.
```

```markdown
| ID | Item | Outcome | Date |
| :--- | :--- | :--- | :--- |
| 4.5 | Cross-partnership checkpoint contamination | Fixed (per-partnership namespacing) | 2026-09-22 |
| 4.11 | Realtime follow-ons (F-RT3…F-RT10) | Fixed (idempotency keys, version guards, dedup keys) | 2026-09-20 → 09-23 |
| 5.4 | Pre-compression 15 MB fast-fail | **By design** — the cap is intentional | 2026-09-24 |
| 7.7 | Remove dead mood `note` property | **Clean** — no such property existed; stale item | 2026-09-28 |
| 7.9 | `HomepageState._isLoading` never used | Fixed (it was the debounce guard, shadowing `BaseState`) | 2026-09-28 |
```

- **ID**: `N.M`, never renamed.
- **Item**: the defect as it was written, in the present tense, ≤ 10 words, with `backticks` for identifiers.
- **Outcome**:
  - code changed → `Fixed` or `Fixed (short mechanism)` — **not bolded**
  - the item was stale → `**Clean** — <why>`
  - not a defect → `**By design** — <why>`
  - the parenthetical is the *mechanism*, not a diff summary: `refreshSession()` + `tokenRefreshed` listener.
- **Date**: the day the item closed, `YYYY-MM-DD`. A span is `YYYY-MM-DD → MM-DD`.
- **Order**: phase blocks in phase order; inside a block, rows in the order the items were **closed** (so a later ID can sit before an earlier one — 2.8 sits between 2.3 and 2.4 because it was fixed then).

The item's `todo.md` status line maps to the Outcome cell like this:

| todo.md status line | Outcome cell |
| :--- | :--- |
| `✅ FIXED`, code changed | `Fixed (short mechanism)` |
| `✅ FIXED`, docs only, no code change | `Fixed (docs clarification; no code change)` |
| `✅ RESOLVED via N.M` | `Fixed (via N.M — the dead path was deleted)` |
| `✅ ALREADY CLEAN` | `**Clean** — <why>` |
| `🚫 WON'T FIX`, the premise was wrong | `**By design** — <why>` |

A `🚫 WON'T FIX` that means "a real defect we chose not to fix" is **not** archivable — that work is still open. Only the "it was never a defect" reading maps to `**By design**` (precedent 5.4).

---

## Decisions of record

Append-only numbered list. One entry per non-obvious constraint.

```markdown
Non-obvious constraints that still bind the code. Each one now lives in its owning doc; do not "fix" them back without reading the doc.

1. **Checkpoint writes are epoch-gated.** A checkpoint computed by a fetch is discarded if a `clear()` (logout, wipe, partnership switch) landed while the fetch was in flight, so a stale snapshot cannot resurrect purged data. → `docs/app/storage-and-caching/doc.md` § How checkpoints work.
2. **The 15 MB upload cap is a pre-compression hard limit, by design.** It rejects large *source* files before compression; it is not a bug. → `docs/features/shared-drive/doc.md` § 15 MB Size Limit.
```

- Continue the existing numbering; keep it contiguous. Removing an entry renumbers the rest and updates every `(decision N)` reference. Never reorder or change an entry's rule; trimming a change-summary tail is allowed.
- Structure: `**Bolded claim.**` → explanation (one or two sentences) → `→` + doc path + ` § ` + section name.
- The doc named must be the one that now holds the reasoning. A decision with no home in `docs/**` is not a decision of record — put it in the doc first.
- Only entries that pass **all three**: non-obvious, still binding on future code, and plausible to undo without the reasoning. The mechanism of a fix belongs in the Item index row; a change summary is not a decision.
- Removing an entry renumbers the remaining entries consecutively; update every internal `(decision N)` reference.

---

## House style

- Em dash `—` for asides, en dash `–` inside ID ranges and date spans, `…` for elision in a list of IDs.
- Inline code for every identifier, path, endpoint, error code and doc section.
- `→` points from a claim to its owning doc.
- No emojis, no checkboxes, no status icons — this file is not a worklist.
- No relative links (`../`) between the two files; `todo.md` links to the log with a repo-root-relative path.
