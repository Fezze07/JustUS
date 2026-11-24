# Per-pass checklists

Load this before running passes 1–7. Each pass lists **look for · how to prove it · traps**.

Repo-agnostic; the "JustUS" line maps a pass to the local convention. Replace those lines freely in another repo.

---

## Pass 1 — Docs vs code

**Look for**
- Architecture claims that migrated: old vendors, models, protocols, ports, SDKs, storage providers, auth flows.
- Wrong file paths, wrong directory names, wrong casing, paths that moved to another root.
- Wrong entry points: a script, command or endpoint that no longer exists or was renamed.
- Version requirements (Node, language runtime, framework) that contradict the manifest.
- Env setup instructions pointing at the wrong directory or missing the variables that have no default.
- Behavior claims contradicted by code: caching, quotas, cadence ("every 24h"), ownership ("X validates the token"), dead-end buttons, unsupported media types.
- Documented test commands that do not match `package.json` scripts or the CI workflow.
- Directory trees that no longer match the tree on disk.

**How to prove it**
1. Extract the falsifiable claim from the doc.
2. Locate the code that implements it (`grep` the identifier, the config key, the endpoint).
3. Run the documented command, or read the manifest, and compare.
4. Cite the doc line *and* the code line that contradicts it.

**Traps**
- A doc's own `file:line` references are stale by definition — re-derive them.
- Absence of a mention is not a defect; a *wrong* claim is.
- Do not "fix" docs for behavior that is itself a bug — if the code is wrong, the doc is right; that is a Phase-C code item, and the doc gets fixed by the fixing workflow afterwards.
- README overhauls are how you discover Phase-1 drifts you were not looking for. Budget time to re-read top-level docs line by line against the code.

---

## Pass 2 — Dead code & unused surface

**Look for**
- Dependencies installed but never imported (`package.json`, `pubspec.yaml`, transitive bloat).
- Constants, storage keys, capabilities/permissions, feature flags, enum members, route constants, model fields — declared, written, never read.
- Exported functions/extensions with no call site; barrel files re-exporting removed symbols.
- Named routes nothing pushes; widgets with no entry point; screens unreachable from the router.
- Shadowed private fields in subclasses (duplicate of a base-class field) — silent divergence.
- Unused imports, params, locals flagged by the linter; long-lived timers/subscriptions never cancelled.
- DB objects not exercised by any app path (function, view, trigger, index, storage policy, table).
- Doc-internal inconsistencies: a findings doc pointing at code that has since changed.

**How to prove it**
- Grep the identifier repo-wide, case-insensitively, including `lib/`, `test/`, SQL, workflows, env templates, docs. Include string literals — many "dead" flags are read by string key.
- For dependencies: remove it, then run lint + tests + build. Absence of `require`/`import` is a hint; a green build is the proof.
- For storage keys: list producer and consumer explicitly. A write-only key is dead; a read-only key with no producer is a missing feature.

**Traps**
- A key read only by a Postgres view/function or a native platform channel is live.
- Fields used by serialization (`toMap`/`fromMap`, `json`), reflection, or template strings are live — grep the serializer.
- An unused *capability* may be a security smell (a granted permission nobody checks) rather than dead code: the fix is often "remove the grant", sometimes "the feature is missing". Decide and say which.
- Deleting a write-only key may be wrong when the *intent* was a missing consumer. Read the design doc: implement the consumer or delete the key, and state which, with the reason.

---

## Pass 3 — Data layer (schema / RLS)

**Look for**
- `SELECT` policies without a restrictive partner-scope predicate → cross-user read.
- Missing explicit `WITH CHECK` on write policies (defaults to the `USING` clause; silently allows what a reader would be denied).
- Policies on the wrong role (`anon`, `authenticated`, `service_role`) or missing `TO` clause.
- Unaccepted / revoked / dissolved partnerships still granting access.
- Broad `FOR ALL` policies wrapping narrower ones, or multiple permissive policies OR-ing into a hole.
- Referential integrity gaps: no FK, no `ON DELETE`, so deletes orphan rows.
- Retention conflicts: two retention jobs with different windows; retention that only deletes in one layer.
- Missing indexes on the hot query paths; RPCs that bypass RLS (`SECURITY DEFINER` without a scope check).
- Schema drift: a local file not applied to the remote project, or vice versa.

**How to prove it**
- Read every policy for a table side by side with the code that queries it. Write the predicate as a sentence ("user can see rows where …") and check it matches the intended sentence.
- For each table, ask: which role can read? write? through which policy? Is the answer the same on every table of the same data class?
- Verify drift with a real query against the linked DB, not by reading files.

**Traps**
- A permissive policy for `authenticated` is OR-ed with the default `anon` policy — check both roles.
- `USING` covers reads and the pre-image of updates; `WITH CHECK` covers the post-image. A policy with only `USING` lets a user move a row to another partnership.
- Triggers that enforce scope at write time are an alternative to `WITH CHECK` — verify the trigger exists for *every* write path, including admin/service-role paths.

---

## Pass 4 — Backend services

**Look for**
- Env handling: vars without defaults that do not fail fast; loader that resolves a different path than documented; secrets with insecure fallbacks; a default that silently contradicts the platform (e.g. a token-lifetime cap vs the auth provider's issue window).
- Auth: lifetime/expiry policy mismatch with the identity provider; refresh paths that can run concurrently or write inconsistent state; a session written to one store but read from another; silent failure that leaves a signed request unsigned.
- Request integrity: signature/secret acquisition that cannot recover; unsigned-by-default paths; nonce/timestamp replay windows; idempotency keys with a TTL that contradicts the documented "once per day".
- Rate limits keyed on something spoofable, or per-layer limits that multiply unexpectedly.
- Error mapping: backend codes with no client mapping, or a client mapping that triggers the wrong UI (e.g. "session expired" dialog on a wrong password).
- Resource lifecycle: objects created but not deleted on the failure path (upload-then-fail leaves an orphan), delete paths that miss one storage backend, jobs that can run in two instances.
- Middleware order: validation after the side effect, sanitization after logging, auth after the handler.
- Unhandled promise rejections, `await` missing in an async handler, `res` used after `return`.

**How to prove it**
- Trace one request end to end: client call → middleware chain → controller → service → DB, and read each hop's assumption about the previous one.
- For env/fail-fast: delete the var and boot it. For signature paths: call the endpoint without the secret and observe.
- For orphans: instrument or grep the failure branches for the compensating delete.

**Traps**
- The frontend's native captcha/callback may be validated by the identity provider, not your backend — a "dead verification endpoint" is a doc bug, not a security hole. Check the provider's actual behavior before claiming a bypass.
- A compensating sweep job can make an apparent leak a non-issue — search for it before writing the item.
- Framework auto-refresh can serialize concurrent refreshes; read the SDK's own guarantee before proposing a mutex.

---

## Pass 5 — Client state & UI

**Look for**
- Lifecycle asymmetry: `init` sets up what `dispose`/`logout`/`wipe` does not clear — timers, subscriptions, caches, in-memory state, controllers. And the reverse: `clear()` wiping a *user preference* that should survive (theme, language).
- Cache keys not namespaced by user or by partnership → cross-partnership contamination on a re-link.
- Optimistic updates without rollback on failure; rollback that does not restore derived state; concurrent writes to the same cache key.
- Error codes: unmapped backend code, mapped code that is not in the `requiresReauth`/critical set, message keys missing from one ARB locale.
- Dead affordances: buttons that do nothing, "analytics"/"soon" labels, fields the model has but no UI edits.
- Missing affordances: a backend capability with no UI (camera vs gallery picker, audio/PDF upload, display-name editing).
- Design-system bypass: screens building their own theme colors, buttons, spacing; hardcoded strings bypassing ARB; a11y gaps on interactive components.
- Bootstrap/mount errors, `dispose` after `init` failure, missing `const` on widget constructors, `BuildContext` used after `await`.
- Rebuild storms: listeners registered inside `build`, `notifyListeners` in a loop, `Selector` tuples narrower than the fields read.

**How to prove it**
- For every state class, tabulate `init` / `dispose` / `logout` / `wipe` and diff the four lists.
- For every persisted key, tabulate producer / consumer / cleared-by and check the triangle closes.
- Run `flutter analyze` and the existing tests; then write a throwaway test that reproduces the lifecycle bug (e.g. clear then re-hydrate) before filing the item — a reproducing test is the strongest evidence you can attach, and it becomes the acceptance criterion.

**Traps**
- A field that "looks unused" may be the debounce guard or the error message consumed by a child — read the whole class.
- Hardcoded-string and duplication checks in CI are objective findings; do not eyeball them.
- Do not file a11y/design-system items as bugs; they are LOW hygiene with a measurable list.

---

## Pass 6 — Cross-layer contracts

**Look for**
- Incremental sync: rows that change without a version/`updated_at` bump become invisible; deletions not propagated; tombstones missing.
- Realtime pipelines: debounce buffers that drop intermediate events or only keep the last actor; coalescing that loses field updates; subscriptions surviving a partnership change or a logout.
- Checkpoints/snapshots keyed globally instead of per partnership, and writes racing the clears that a wipe/logout performs.
- Token lifetime vs policy vs refresh window — all three must agree; measure each.
- Retention: two layers, two windows, one wins; a log table that grows because a job's driver guard is per-instance.
- Storage: upload limits, MIME allow-lists and the pickers the UI actually offers; pre-compression vs post-compression caps; thumbnails generated client-side vs expected server-side.
- Push: signing/permission alignment with the backend, token lifecycle vs logout, notification targets after a re-link.
- Version/update: manifest source, forced vs optional upgrade, and the R2/GitHub URL the client trusts.

**How to prove it**
- Write the timeline of the failing sequence and mark the hop where state diverges.
- Simulate the sequence at the lowest level available (a unit test on the buffer, a service method, a SQL fixture).
- Compare the two sides' numbers, not their intent: limits, windows, TTLs, quotas.

**Traps**
- A "lost update" may be intentional eventual consistency — check the design doc's stated guarantee before filing.
- Debounce coalescing that keeps only the last event is a bug *only* if the field is a scalar, not an accumulating set.

---

## Pass 7 — Tests & tooling

**Look for**
- Regressions this scan found that no test would catch → the missing test *is* the Phase-8 item.
- Test infra claims that are false: a documented command that does not exist, a mock that no longer matches the real protocol, a test file that no runner picks up, a CI job that runs nothing.
- Suites with no assertions, tests asserting the mock instead of the code, snapshot tests nobody updates.
- Uncovered shared infrastructure (base classes, HTTP layer, cache layer) — the highest-value gap because everything depends on it.
- Duplication (`jscpd`) that indicates a copy-paste bug waiting to diverge.
- Missing CI: the unified suite not wired to the branch, no lint/format gate.

**How to prove it**
- Change one line of the code under test and see whether any test fails. If nothing fails, that path is uncovered — that is the evidence.
- Run the documented commands and paste the real output.

**Traps**
- A test that passes against a mock proves the mock, not the integration; require at least one test per external boundary contract.
- Do not propose a test for code that is about to be deleted in the same plan.

---

## Evidence quality bar

The right-hand column is the shape to imitate: **behavior → divergence → trigger → impact → fix**. `<angle brackets>` are placeholders — fill them from the code you actually read. Concrete worked examples live in this repo's `todo.md`; do not copy identifiers from it without re-grepping, because fixes have since changed the code these examples describe.

| Weak (do not file) | Strong (file this) |
| :--- | :--- |
| "This looks like a race condition." | "Two refresh paths (`<sdk auto-refresh>` at `<a.ext:12-30>` and the `<401>` handler at `<b.ext:88-120>`) can both call `<POST /token>`; with rotation the second call invalidates the first session → forced logout. Repro: expire the token mid-request. Fix: one refresh coordinator." |
| "`<symbol>` seems unused." | "Grepped `<symbol>` across `<lib/>`, `<test/>`, SQL, workflows and env templates: 0 call sites; the extension is re-exported by the barrel only. Delete `<symbol>` and its barrel export." |
| "Captcha isn't verified." | "`<service>.<method>()` (`<file>:<n>`) has no call site after `<route removal>`; the identity provider validates the `captchaToken` in Managed mode, so no token ever reaches this service. Delete the service and its env keys, and correct the doc that claims backend verification." |
| "Docs are outdated." | "`<doc>:<n>` claims '<cadence/behavior>'; the code exposes only `<route/function>` and the `<window>` value at `<file>:<n>` is the `<request-cache TTL>`. No `<scheduler>` exists." |
| "RLS might be wrong." | "`<table>` `<policy name>` (`<schema file>:<n>`) has a `USING` clause but no `WITH CHECK`, so a row can be `<moved to another partnership>`; the intended scope sentence is '<…>'. Fix: explicit `WITH CHECK` + assertion test under Phase 8." |
| "The user can be logged out wrongly." | "`<error code>` maps into the `requiresReauth` set, so a `<wrong password>` on the login form triggers the non-dismissible session-expired dialog (`<file>:<n>`) and stacks `/login` over itself. Fix: client-only code for credential failures." |

Every finding should be able to fill the right-hand column. If it cannot, move it to the "not confirmed" list.
