---
name: archive-fix-item
description: Move closed fix items out of todo.md into docs/fixing-phase-log.md - the archiving step that runs after items are fixed, verified and committed. Log first, then the worklist. Use when asked to archive an item or a batch, move todo items into the fixing-phase log, clean up todo.md, retire a closed phase, or hand closed work over to git history. Triggers on "archive this item", "archive 10.12-10.21", "move it to fixing-phase-log", "clean up todo.md", "close out phase 8", "remove the finished item from todo".
risk: low
source: local
version: "1.5"
tags: [workflow, fixing-phase, todo, archive, documentation, history]
---

# Archive Fix Items

Moves **already closed** items from `todo.md` (the live worklist) into `docs/fixing-phase-log.md` (the permanent history), and leaves both files consistent.

**Never renumber an item or a phase, never invent history.**

Read `.agents/skills/fix-workflow/SKILL.md` first — this skill starts where its §1 loop ends. Read `references/log-format.md` for the exact shape of every block in the log.

---

## 1. The order (this is the whole procedure)

1. **Read** the items in `todo.md` (§3).
2. **Fix any doc a decision will point at** — a decision with no home in `docs/**` is not a decision of record. The doc first, then the log.
3. **Write the log** (§4) — every item of the batch, in one pass. **This happens before `todo.md` is touched.**
4. **Remove the items from `todo.md`** (§5) — one item's block at a time, each anchored on its own heading.
5. **Repair every reference** (§6).
6. **Verify** (§7).
7. **Commit the log and the doc fixes the log's pointers depend on** (§8).

**Log first, then the worklist.** The worklist is the only place an item's `Defect` / `Fix` / `Acceptance` text exists; once the block is deleted the log's one-line row is all that remains. A batch is one log pass + one worklist pass — never interleaved per item.

---

## 2. Preconditions (per item)

- The item's **status line** in `todo.md` is written and the box is ticked (`fix-workflow` §1.7-§1.8).
- The **acceptance criterion** has been re-verified, and the verification command + result are recorded in the status line.
- The code and every affected `docs/**` file are **committed and pushed** (`fix-workflow` §1.8).
- The owning docs now describe the *current* behavior; the finding is gone from the doc's findings section (`fix-workflow` §2).
- The item closes as **Fixed**, **Clean** or **By design** (mapping in §4). `⚠️ PARTIAL` is not archivable — the partial work belongs to a new item, which stays in `todo.md`.
- `🚫 WON'T FIX` is archivable **only** when the premise was wrong (it was never a defect) — that is the `**By design**` slot, precedent 5.4. A WON'T FIX that means "a real defect we chose not to fix" is still open work and stays in `todo.md`. If neither reading fits, stop and ask; whichever mapping you choose, **say it in the final report**.

---

## 3. Read the item, do not paraphrase it

Read the item's own block in `todo.md` and extract, verbatim where possible:

| Need | Source in the item |
| :--- | :--- |
| ID | the `8.4` / `### 9.1` heading |
| Short title | the bolded title, ≤ 10 words |
| Outcome | the status line: fixed, already clean, by design, won't fix |
| Date | the status line's date — the day the item **closed**, not the day you are archiving |
| Theme | the phase's theme, from the phase heading |
| Decision | a constraint a future reader could undo (most items have none) |

`⚠️` items, superseded items and new IDs the fix created in **Residual** stay in `todo.md` — they are still open work.

---

## 4. Write into `docs/fixing-phase-log.md`

In this order, all in one pass:

1. **§ Item index** — append the item's row, inside its phase's block, **in the order the items were closed** (a later ID may sit before an earlier one). Mandatory for every archived item.
2. **§ Outcome by phase** — update each touched phase's row: outcome wording for the new state and the `Items` cell. A phase that is now closed **drops** its `Still open — carried in todo.md` note; one with open items keeps it.
3. **§ Decisions of record** — append a numbered entry **only** if **all three** hold: the choice is non-obvious, it still binds future code, and a reader who lacks the reasoning could plausibly undo it. The fix's mechanism belongs in the § Item index outcome cell; do not restate it here. One sentence, bolded, then the reasoning, then `→ doc § Section`. Most items add none. Keep the list contiguous: removing an entry renumbers the rest, and every `(decision N)` reference must be updated.
4. **Intro paragraph** — only if this closes the last open phase: replace the "Nothing open is tracked here" sentence with what is still open.

Do **not** add: a per-item narrative section, a "retired findings" section, a finding-to-section index, a tests-added table, changelog prose, or any status summary. Those are not part of the log's shape.

### Outcome mapping (the status line → the Outcome cell)

| todo.md status line | Outcome cell |
| :--- | :--- |
| `✅ FIXED`, code changed | `Fixed (short mechanism)` — not bolded |
| `✅ FIXED`, docs only, no code change | `Fixed (docs clarification; no code change)` (precedent 9.6) |
| `✅ RESOLVED via N.M` | `Fixed (via N.M — the dead path was deleted)` |
| `✅ ALREADY CLEAN` | `**Clean** — <why>` |
| `🚫 WON'T FIX`, premise was wrong | `**By design** — <why>` (precedent 5.4) |

The parenthetical is the *mechanism*, not a diff summary. Only non-`Fixed` outcomes are bolded.

### Phase row (batch of several items)

- `Items`: the closed range, en dash inside a range, comma-separated in numeric order when non-contiguous (`10.1–10.5, 10.8–10.21`).
- `Outcome` lead phrase: `All fixed.` · `N fixed, M closed as *not a defect* (…)` · `Still open — carried in todo.md`. Then a period, then the notable mechanisms of the phase.
- Count the items: the closed set minus the ones closed as *not a defect* = the `N fixed`.

---

## 5. Remove from todo.md

> **`todo.md` is tracked now, so `git diff` is a real safety net — but a bulk archive can still lose work between commits.** Take a copy before a multi-item archive and diff the result; treat each large edit as reviewable, not disposable.
>
> - **Edit it with the file-editing tool, never with a shell script.** A scripted splice fails *silently*: PowerShell method exceptions are non-terminating by default, so `List.AddRange()` can throw twice and `WriteAllLines` still overwrites the whole file with whatever survived in the list. The editing tool validates and fails loudly.
> - **Before the first edit of a multi-item archive, take a copy** — `Copy-Item todo.md "$env:TEMP\todo-$(Get-Date -f yyyyMMdd-HHmmss).md"`. It is the quickest rollback; the commit history is the second.
> - **Never delete a contiguous line range by index.** Locate the block by its heading text and delete the item's own lines, so a mis-located marker can cost one item instead of the file.

- Delete the item's whole block (checkbox line, or the `###` heading + its `Sources` / `Files` / `Defect` / `Fix` / `Acceptance` / `Status` lines) — **one item at a time**, each edit anchored on that item's own heading text.
- Delete the `---` separator that belonged to the block, when the item was the last of its group.
- Delete its row from **§ Open finding IDs**, if it has one there. A row that also points at still-open items stays — narrow it instead (`| \`debug_wipe_user_data\` | 11.6, 12.3 |`).
- When the phase is closed but a **triaged tail** (claims that are *not* items) remains, keep the phase heading and that table, and rewrite the phase intro to say the items are archived and only the triaged tail is left. When nothing of the phase remains, delete the phase heading, its intro and its `---` too, and renumber nothing — phase numbers are permanent, they just stop appearing in `todo.md`.
- Update **§ Suggested fix order** when it names the archived phase (`close 8.x and 10.x` → `close 8.x`).
- Keep the file's header block: purpose, the tracked-file note, the finding-ID prefixes and the priority tags. Update the header's archive sentence to match what the log actually contains today.

---

## 6. Repair every reference

- `todo.md` header → link the log and name its sections exactly as they are headed (`§ Outcome by phase`, `§ Item index`, `§ Decisions of record`).
- Any `§ <section>` pointer to `docs/fixing-phase-log.md` in `todo.md` → it must name a section that exists after this archive. A pointer to a deleted section is a broken reference; repoint it or drop the sentence.
- Any other `docs/**` file that referenced the archived item ID → keep the ID (IDs stay resolvable) and name the log as its home: `(10.17, see \`docs/fixing-phase-log.md\` § Item index)`.
- A `grep` for the archived IDs across `docs/**` and `README.md` must return only intentional historical mentions.

---

## 7. Verification

Run before reporting done:

```powershell
# the log gained exactly one row per item, in close order
Select-String -Path docs/fixing-phase-log.md -Pattern '^\| 10\.(1[2-9]|2[01]) \|'

# the worklist lost exactly the archived blocks — the backup diff is the check that matters
git diff --no-index --unified=0 "$env:TEMP\todo-<stamp>.md" todo.md

# the worklist is intact, not just edited: the sections on BOTH sides of every
# deleted block still exist, and the line count fell by roughly the block size
([System.IO.File]::ReadAllLines('todo.md',[System.Text.Encoding]::UTF8)).Count
Select-String -Path todo.md -Pattern '^## |^### '

# no dangling section pointers
Select-String -Path todo.md,docs\**\*.md -Pattern 'fixing-phase-log\.md §'

# the archived IDs survive only as intentional historical mentions
Get-ChildItem -Recurse -Path docs -Filter *.md |
  ForEach-Object { Select-String -Path $_.FullName -Pattern '10\.1[2-9]|10\.2[01]' }

# todo.md is tracked: the archive commit must list it
git status --short
```

- The **backup diff is the check that matters**: it must show only the archived blocks, the phase intro, the § Open finding IDs rows and the fix-order line. A line count alone can hide a lost tail.
- `git status --short` must list both `todo.md` and `docs/fixing-phase-log.md`.
- The item ID must appear exactly once in the log's item index.
- Read the log's tables after editing: pipe alignment, `YYYY-MM-DD` dates, bold on non-`Fixed` outcomes, em dash `—` for asides and en dash `–` inside ID ranges.

### Tooling notes (this repo is UTF-8; the shell will lie to you)

- PowerShell's console and `Get-Content` mangle the repo's UTF-8 (em dash → `?` or `â€"`). For counts and character checks use .NET: `[System.IO.File]::ReadAllLines($path,[System.Text.Encoding]::UTF8)`, and set `[Console]::OutputEncoding=[System.Text.Encoding]::UTF8` before printing non-ASCII.
- The read/grep tools truncate long lines (~2000 chars) and render non-ASCII as mojibake. A long `todo.md` line must be dumped as UTF-8 chunks and then deleted with an exact-match edit.
- The file's em dash (U+2014) and arrow (U+2192) are real UTF-8, **not** mojibake. To edit a line that contains them, split it into ASCII-only segments and edit segment by segment — a full-line `oldString` with the em dash typed by hand will not match.

---

## 8. Commit

Commit **the log** (`docs/fixing-phase-log.md`), **`todo.md`**, **plus any doc fix needed for the log's pointers to be truthful** (the doc a decision points at, when that doc still described the pre-fix behavior):

```
chore(docs): archive fix items 10.12-10.21
chore(docs): archive fix item 8.4          # single item
```

This is a documentation commit; no code changed, so no test run is required. The items' own code commits already exist.

---

## 9. Guardrails

- **Never archive an unclosed item**, and never archive "partly".
- **Never delete an item's content before it is in the log.** Sequence: log first, then `todo.md`.
- **Never script an edit to `todo.md`,** and never trust a write you have not diffed against the backup. A tracked file still deserves the care of a `git push --force`, because a bad write between commits loses work.
- **Stop when a command's output contradicts what you asked for.** A script that reports `wrote 21 lines (was 651)` has failed, whatever its exit code says. This single check would have prevented the 2026-10-03 truncation of `todo.md`, where two swallowed exceptions produced exactly that line in the output.
- **Never renumber** an item or a phase. The IDs in the log must stay resolvable against the old `git log` messages and the status lines still in `todo.md`.
- **Never rewrite the outcome of an archived item.** If the log turns out to be wrong, fix the log in a new commit with a reason; do not silently change history.
- **Do not "improve" the log's shape.** Its sections and their order are the format; add rows, not sections.
- **Do not archive a decision that belongs in a doc.** A design choice is documented in its owning `docs/**` file; the log only points at it.
- **A decision of record is a constraint, not a change summary.** If the § Item index row already says it, it is not a decision. Removing one compacts the numbering: renumber the rest and fix internal references. Trim a mixed entry to its rule; never change the rule.
- **Commit `todo.md` with the log** — one archive, one commit; do not leave the worklist removal for a later commit.

---

## 10. Related skills

- `.agents/skills/fix-workflow` — the loop this skill finishes; status lines, verification, commit rules.
- `.agents/skills/codebase-audit` — how items and their `Sources` were discovered; read before restructuring a phase.
- `references/log-format.md` — the verbatim format of every block in the log.
