# Partnership cancellation — design rules and build plan

Status: **planned, not implemented**
Scope: new feature. Replaces the accidental raw-`DELETE` break-up with an explicit,
two-party cancellation flow.

## 1. Goal

A paired user can ask to end the partnership **without deleting anything at that moment**.
The other member decides. Only an approval destroys the couple's data. An unanswered request
auto-expires back to `accepted`.

## 2. State machine (the rules)

`public.partnerships.status` gains a third value: `accepted | pending | cancelled`.

| From | Action | Who | To | Side effects |
|------|--------|-----|----|--------------|
| accepted | **request cancellation** | either member | cancelled, `cancel_requested_by = caller`, `cancel_expires_at = now() + 7 days` | Partner gets a push. No data deleted. Both are frozen out of couple features (`partnership_is_member()` requires `accepted`). Requester lands on PartnerScreen. |
| cancelled | **revert** (requester) / **decline** (partner) | either member | accepted, requester + expiry NULL | Data untouched. Both return to MainShell. If the partner did it, `cancel_declined_at = now()` and the partner gets a \"declined\" push. |
| cancelled | **accept** | **only the member who did not request it**, before expiry | row deleted | Couple data destroyed (§5). Requester gets an \"ended\" push. |
| cancelled | **expire** | system, after 7 days | accepted, requester + expiry NULL | Data untouched. No push. |
| pending | accept / reject | unchanged (11.1) | accepted / deleted | Unchanged. |
| any | re-point membership / swap requester | nobody | — | Blocked by the trigger (§3.2). |

Rules:

1. At most one cancellation request per partnership.
2. The requester can always undo it; the partner can decline it. Both restore `accepted`.
3. The requester **cannot** approve it — only the other member can.
4. Ignoring it freezes the partnership until either action or the 7-day expiry.
5. While `cancelled`, a member cannot start a new pairing or accept a different invitation.
6. After a partner decline, the same partnership cannot request again for **24 hours**.
7. Nothing is deleted on request, decline, undo, expiry, logout, or app close.
8. Acceptance is permanent: the row and the data are gone.
9. There is no grace window. Once `cancel_expires_at <= now()`, acceptance is rejected and the
   request is reverted.

## 3. Database changes

### 3.1 Columns and constraints — `public.partnerships`

```sql
ALTER TABLE public.partnerships
  ADD COLUMN cancel_requested_by integer REFERENCES public.users(id) ON DELETE CASCADE,
  ADD COLUMN cancel_expires_at   timestamptz,
  ADD COLUMN cancel_declined_at  timestamptz;

ALTER TABLE public.partnerships
  ADD CONSTRAINT partnerships_status_check
    CHECK (status IN ('pending', 'accepted', 'cancelled')),
  ADD CONSTRAINT partnerships_cancel_requester_check
    CHECK (cancel_requested_by IS NULL OR cancel_requested_by IN (user_id_1, user_id_2)),
  ADD CONSTRAINT partnerships_cancel_state_check
    CHECK ((status = 'cancelled') = (cancel_requested_by IS NOT NULL)
       AND (status = 'cancelled') = (cancel_expires_at IS NOT NULL));
```

- Existing rows (`pending` / `accepted`) satisfy the constraints with NULLs.
- `cancel_expires_at` is the single source for auto-expiry. `cancel_declined_at` is the single
  source for the 24h cooldown. `updated_at` keeps its current meaning and is not reused for
  either rule.
- `cancel_declined_at` is written by the trigger only, never by clients.

### 3.2 Trigger `partnership_guard_status` (extend, keep the name)

Keep 11.2 (membership immutable) and 11.1 (only `user_id_2` accepts a pending request).
Add a whitelist for `status` / `cancel_requested_by` / `cancel_expires_at` /
`cancel_declined_at`. Keep the existing `IF v_caller_id IS NOT NULL` escape so `service_role`
(backend, expiry job) still writes.

| OLD.status | NEW.status | Requirement | Error |
|---|---|---|---|
| pending | accepted | `NEW.user_id_2 = caller`, cancel fields NULL | `API-VALIDATION-008` (existing) |
| accepted | cancelled | caller is a member, `cancel_requested_by = caller`, `cancel_expires_at` set | `API-VALIDATION-010` |
| cancelled | accepted | caller is a member, both cancel fields set to NULL | `API-VALIDATION-011` |
| cancelled | cancelled | cancel fields unchanged | `API-VALIDATION-012` |
| anything else | changed | rejected | `API-VALIDATION-012` |

Additional trigger rules:

- On `cancelled → accepted` by a caller that is **not** `OLD.cancel_requested_by` (partner
  decline), set `NEW.cancel_declined_at := now()`.
- On `cancelled → accepted` by the requester (restore), leave `cancel_declined_at` as-is.
- On every transition, force `NEW.cancel_declined_at := OLD.cancel_declined_at` except for the
  partner-decline case above, so a client cannot clear or forge the cooldown.
- A client cannot mutate `cancel_requested_by` while `cancelled` (blocks swapping the requester
  to become the eligible accepter).
- A client cannot mutate `cancel_expires_at` while `cancelled`.

The trigger is what makes the rules true for every writer, including a raw PostgREST
`PATCH`. A client may perform request/revert with a raw PATCH; it still cannot delete.

### 3.3 Policies and grants

- **Narrow `partnerships_delete_own` to `status = 'pending'`.** This is the 11.3 fix and is
  required here: no client may delete an accepted or cancelled row. `partnership_reject`
  keeps working (pending only).
- Revoke `DELETE` and `TRUNCATE` from `anon` on `partnerships` (`partnerships.sql:49`).
- `SELECT` / `UPDATE` policies unchanged. Members keep reading/updating their own row;
  access to couple data ends automatically because `partnership_is_member()` requires
  `status = 'accepted'`.
- Acceptance runs in a service-role-only RPC (§3.5), so no client DELETE policy exists for
  accepted/cancelled rows.

### 3.4 Moods — delete with the partnership

Moods are currently personal rows (`user_id` only), so a partnership delete would leave them
behind. Per the chosen design, new moods belong to the couple. The table is empty today, so
**no backfill is needed**.

```sql
ALTER TABLE public.moods
  ADD COLUMN partnership_id integer
    REFERENCES public.partnerships(id) ON DELETE CASCADE;

CREATE INDEX idx_moods_partnership_id ON public.moods (partnership_id);
```

- `mood_set` resolves the caller's `accepted` partnership and writes `partnership_id`
  (NULL only if the caller has none). One row per mood event, as today.
- Tighten `moods_manage_own` / `moods_update_own`:
  `(partnership_id IS NULL OR partnership_is_member(partnership_id))` in the `WITH CHECK`,
  so a client cannot attach a mood to someone else's pair.
- Deleting the partnership now cascades `drive_items` (+ favourites, reactions),
  `bucket_items`, `game_questions` (+ answers), `missyou`, and `moods`.

### 3.5 RPCs

All take `p_partnership_id integer` and use `public.user_current_id()` unless noted.

| Function | Security | Behaviour |
|---|---|---|
| `partnership_request_cancel(p_partnership_id)` | INVOKER | Lock the caller's `accepted` row. Reject if `cancel_declined_at > now() - interval '24 hours'` (`API-VALIDATION-013`). Update → `cancelled`, requester = caller, `cancel_expires_at = now() + interval '7 days'`. Zero rows → `API-VALIDATION-010`. |
| `partnership_cancel_revert(p_partnership_id)` | INVOKER | Update a non-expired `cancelled` row → `accepted`, clear both cancel fields. Either member. The trigger records `cancel_declined_at` only when the caller is the partner. Zero rows → `API-VALIDATION-011`. |
| `partnership_cancel_accept(p_partnership_id, p_actor_id)` | **DEFINER**, service_role only | Validate `p_actor_id` is a member, is not `cancel_requested_by`, the row is `cancelled`, and `cancel_expires_at > now()`. `DELETE` the partnership row (cascades §3.4). Zero rows / expired → `API-VALIDATION-012` / `-014`. Takes the actor because the backend calls it with no JWT. |
| `partnership_get_cancellation()` | DEFINER, `authenticated` only | First call `partnership_expire_cancellations()` (lazy expiry), then return the caller's cancelled row: `partnership_id`, `partner_id`, `partner_display_name`, `partner_profile_pic_url`, `requested_by_me`. No expiry timestamp exposed (the UI shows no countdown). |
| `partnership_get_cancellation_partner(p_user_id)` | DEFINER, service_role only | Return the other member of the `cancelled` row involving `p_user_id`. Used by the request push. |
| `partnership_expire_cancellations()` | DEFINER, service_role only | `UPDATE ... SET status='accepted', cancel fields NULL WHERE status='cancelled' AND cancel_expires_at <= now()`. Returns the number expired. Called by the retention job and by `partnership_get_cancellation`. |

Grants: `REVOKE ALL FROM PUBLIC, anon`; `GRANT EXECUTE` to `authenticated` for the request,
revert and read; to `postgres, service_role` only for accept, partner lookup and expire.

### 3.6 Pairing guards

- **Kept in this feature:** `partnership_accept` rejects a recipient who already has an
  `accepted` or `cancelled` row. A second accepted row makes `v_active_partnership`
  (`maybeSingle`) fail and the cancellation state ambiguous.
- **Kept in this feature:** `partnership_request` treats `cancelled` like `accepted` for the
  **sender**, so a cancelled user cannot start a new pairing.
- **Deferred to `todo.md`:** blocking a request where the **recipient** already has an
  `accepted`/`cancelled` partnership (the third-party-invite bug), and any cleanup of
  unrelated pending invitations. On acceptance, this feature deletes **no** other pending
  rows.

## 4. Backend (Node)

### 4.1 Ex-partner helper

`Backend/utils/misc/partnershipUtils.js` gains:

```js
// Resolve the counterpart of a cancelled partnership row.
async function getCancellationPartnerId(userId) { ... } // via partnership_get_cancellation_partner
```

Implemented: `getCancellationPartnerId` added, `getPartnerId` unchanged.

- Do **not** loosen `getPartnerId()` (accepted-only): it is used by media upload
  authorization.
- `getCancellationPartnerId` is used by the request-push resolver and by `media-complete`
  (§4.3). Device tokens stay where they are: `sendNotificationToUser()` resolves them via
  `user_devices`; the helper resolves identity.

### 4.2 Acceptance endpoint

`POST /api/v1/partnership/cancel/accept` — new `features/partnership/` module
(`.routes.js`, `.controller.js`, `.service.js`, `.schemas.js`), mounted in `routes/v1.js`,
registered in `config/apiRoutes.js`. Middleware: `authenticated()`, rate limit,
`signed("partnership-cancel-accept")`, `validated({ body })` with `{ partnershipId }`.
The Flutter call uses `requireSignature: true`.

Implemented in `Backend/features/partnership/*`, mounted at `/api/v1/partnership`.

Controller sequence:

1. Load the row as service_role: `id, user_id_1, user_id_2, status, cancel_requested_by,
   cancel_expires_at`.
2. Require `status = 'cancelled'`, caller is a member, and
   `cancel_requested_by !== caller` (`API-VALIDATION-012`).
3. If `cancel_expires_at <= now()`: call `partnership_expire_cancellations()`, return
   `API-VALIDATION-014`. The client refreshes and is back to `accepted`; nothing is swept.
4. Remember the requester id (the other member).
5. Call `partnership_cancel_accept(partnershipId, caller)`.
6. Best-effort R2 sweep: delete `uploads/<user1>/` and `uploads/<user2>/` via
   `deleteObjectsByPrefix` (`features/media/r2.service.js`). **Do not touch `profile/`.**
   Log failures; the existing orphan sweep catches leftovers. The DB delete is not rolled
   back if R2 fails.
7. Push `cancellationAccepted` to the remembered requester.
8. Return `{ success: true }`.

Decline/undo stay client RPCs (`partnership_cancel_revert`); after that the row is `accepted`,
so the normal notify path works for `cancellationDeclined`.

### 4.3 In-flight uploads

`media-complete` (and only that route) may complete a file whose signed URL was issued while
the partnership was `accepted`. If the row is now `cancelled`, resolve the other member via
`getCancellationPartnerId` and insert the drive item normally; it will be cascade-deleted if
the partner accepts, or kept if they decline.

Implemented in `Backend/features/media/mediaWorkflow.service.js`.

- `createUploadUrl` stays accepted-only, so no new uploads can start while cancelled.
- If the partnership row is gone (accepted), `media-complete` fails with the normal
  \"no partner\" error; the object becomes an orphan and the sweep removes it.
- Signed-URL expiry bounds how long this exception can apply.

## 5. What \"delete everything\" means

On acceptance (server, in order):

1. `partnership_cancel_accept` deletes the partnership row. FK cascades delete drive items
   (+ favourites, reactions), bucket items, game questions (+ answers), miss-you, and moods
   (§3.4).
2. The backend deletes **drive media only**: `uploads/<user1>/`, `uploads/<user2>/`.
   Profile pictures (`profile/<uid>/`) and all non-partnership objects are kept.
3. Unrelated pending invitations for either user are **not** touched (§3.6).
4. The row is gone; there is no restore.

No `debug_wipe_user_data` / `/users/wipe` involved.

## 6. Notifications

Three keys, EN + IT, in both `Backend/features/notifications/notification.utils.js` and the
Flutter `_localizeNotification` switch + arb + generated files:

| Key | Sent by | Receiver | When |
|---|---|---|---|
| `cancellationRequested` | requester's client, after the RPC (`notifyPartnerOnce`) | partner | request created |
| `cancellationDeclined` | client, after `partnership_cancel_revert` (normal path) | the other member | partner decline or requester restore |
| `cancellationAccepted` | acceptance endpoint (server) | requester | row deleted |

- `cancellationRequested` must resolve through `getCancellationPartnerId` (the row is
  `cancelled`, so accepted-only `getPartnerId()` returns null). Special-case by
  `notificationKey` in `resolveNotificationTarget`.
- `cancellationAccepted` is sent server-side by the acceptance endpoint.
- **No notification on expiry.**
- Notification tap: no new tab. While cancelled, `MainShell` redirects to PartnerScreen
  (`hasPartner` false); cold start lands there via `AuthNavigationUtils`.

## 7. Client (Flutter)

### 7.1 Profile button (part 1)

`Flutter/lib/features/settings/screens/profile_screen.dart`, above the logout tile:

- Same visual pattern as the logout tile (`InkWell` + bordered container + icon + label),
  danger colour, `Icons.heart_broken_outlined`, label
  `REQUEST PARTNERSHIP CANCELLATION`.
- Visible only when `AuthState.hasPartner` is true; not debug-gated.
- Tap → **simple confirmation dialog** explaining that the partner must approve and that the
  app pauses until then. No type-to-confirm.
- Confirm → `PartnerState.requestCancellation()`.
  - success: clear partnership cache/storage, refresh auth/partner state, show message,
    navigate with `Navigator.pushReplacementNamed(AppRoutes.partner)`.
  - failure: show the mapped error (including the 24h cooldown), stay on Profile.

### 7.2 Data layer

- `PartnershipRepository`:
  - `requestCancellation(int partnershipId)` → RPC `partnership_request_cancel`
  - `revertCancellation(int partnershipId)` → RPC `partnership_cancel_revert`
  - `acceptCancellation(int partnershipId)` → **backend endpoint** (§4.2), signed
  - `getCancellation()` → RPC `partnership_get_cancellation`, new
    `PartnershipCancellation` model (`partnershipId`, partner id/name/pic,
    `requestedByMe`).
- Do **not** extend `PartnershipResponse` / `v_active_partnership`; `AuthState.hasPartner`
  must stay false while cancelled.
- `PartnerState`: hold `PartnershipCancellation? cancellation`, fetched with
  `fetchPartnership` / refresh / realtime.
- After request/revert/accept: clear the static partnership cache, refresh `PartnerState` +
  `AuthState`, then navigate.
- Realtime: the `partnerships` binding already refetches on UPDATE. Treat a `delete` event as
  relevant too (delete payloads may be PK-only), so the requester learns the partner accepted.
  On any change that makes `hasPartner` false while a cancellation was known, the client shows
  the \"ended\" copy once (local state, no server tombstone).
- **Teleport, no dialog:** the realtime update makes `MainShell` replace the current route with
  PartnerScreen. This must also work from pushed routes (e.g., a full-screen media viewer), so
  the redirect is not limited to the shell's own build. PartnerScreen explains why the user
  landed there.
- Lost accept response: on error, refresh `getCancellation` + auth. If the row is gone, treat it
  as success and show the \"ended\" state instead of an error.

### 7.3 PartnerScreen states (parts 3–5)

Add a branch before the normal content:

- **Cancelled, requested by me**
  - Card: \"Cancellation requested. Waiting for <partner> to approve before continuing.\"
    No countdown, no expiry date.
  - Button `Restore partnership` → `revertCancellation` → refresh → MainShell.
  - Hide personal-code card, \"New Connection\", and pending invitations.
  - Stay here until restore, the partner's decision, or expiry.
- **Cancelled, requested by partner**
  - Reuse the invitation tile: \"<partner> asked to end the partnership\" with accept and
    decline actions.
  - Decline → `revertCancellation` → MainShell.
  - Accept → **simple confirmation dialog** → `acceptCancellation` (the backend endpoint) →
    clear local caches/states → stay on PartnerScreen with \"Partnership ended. All shared
    data was deleted.\" → user may add a new partner.
  - If the endpoint fails, refresh; if the row is gone show the ended state (lost response),
    otherwise show the error and remain cancelled. Nothing has been deleted unless the server
    reached step 5 of §4.2 — the copy must say the deletion is final.
  - On expiry, the page refreshes to the normal accepted/paired state (via the read RPC) and
    the user can go back to MainShell.
- **Normal**: unchanged.
- Logout stays available on PartnerScreen (existing footer) and works while cancelled.

### 7.4 Modular invitation tile

Add optional `title`, `subtitle`, `leadingIcon`, `acceptTooltip`, `rejectTooltip`,
`showAccept`, `showReject` to `InvitationTile`, with defaults preserving the current
invitation callers. The cancellation card passes its own copy.

### 7.5 Localization / error codes

- New keys: profile button + dialog + snackbar; both PartnerScreen states; restore/accept/
  decline copy; the three notification title/body pairs; the \"ended\" copy.
- Add `API-VALIDATION-010/011/012/013/014` to `error_codes.dart` (constants, allowlist,
  `userMessage`) and `intl_en.arb` / `intl_it.arb`.

## 8. Auto-expiry

- 7 days from the request, stored in `cancel_expires_at` (set by
  `partnership_request_cancel`; one SQL constant to change).
- `Backend/core/jobs/retentionJob.js`: new `sweepExpiredCancellations()` calling
  `adminSupabase.rpc('partnership_expire_cancellations')`; interval constant
  `CANCEL_SWEEP_INTERVAL_MS = 6 * 60 * 60 * 1000`, matching the existing `*_INTERVAL_MS`
  pattern. Add it to the initial `Promise.all`, the interval list, `stopRetentionJobs`, and
  the startup log (`retention.cancellations`). Implemented.
- Expiry is silent in v1 (no push).
- Lazy expiry: `partnership_get_cancellation` runs the sweep for the caller before returning,
  so a user who opens the app after the deadline sees `accepted` immediately instead of waiting
  for the next job tick.
- No expiry timestamp is shown in the UI.

## 9. Docs to update (part 7)

- `docs/features/partnership/doc.md`: state machine, columns (including
  `cancel_declined_at`), cooldown, RPCs, flows, freeze rule, acceptance sequence, lazy expiry,
  no-grace rule, unrelated invitations untouched.
- `docs/features/profile-settings/doc.md`: new button + simple dialog.
- `docs/features/mood/doc.md`: `partnership_id`, cascade, insert rule, no backfill.
- `docs/supabase/schema/doc.md`: partnership columns/constraints/trigger, moods column,
  functions, expiry.
- `docs/supabase/rls/doc.md`: pending-only delete policy, grants, mood check, matrix rows.
- `docs/app/notifications/doc.md`: three new keys, senders, media-complete exception, no
  expiry push.
- `docs/app/localization/doc.md`: new keys and error strings.
- `docs/app/architecture/doc.md`: repository/state, backend endpoint, helper, in-flight uploads.
- `docs/app/navigation/doc.md`: cancelled state teleports to PartnerScreen from any route.
- Backend/data-retention docs: new sweep interval + lazy expiry.

## 10. Verification (part 8)

### SQL — `supabase/test/rls_partnership_cancellation.test.sql`

Fixtures follow `rls_partnership_creation.test.sql` (transaction + ROLLBACK, `pg_temp.rls_try`,
`request.jwt.claims`, `SET LOCAL ROLE`).

- A: request as `user_id_1` and as `user_id_2` → cancelled + correct requester + expiry about
  7 days ahead; non-member/anon rejected; second request rejected.
- B: raw `DELETE` of accepted denied; raw `DELETE` of cancelled denied for **both** members
  (11.3 regression); raw DELETE of pending still works.
- C: revert by requester and by partner → accepted + NULLs; `cancel_declined_at` set only for
  the partner; non-member rejected; revert of a non-cancelled row rejected.
- D: cooldown — with `cancel_declined_at = now() - interval '1 hour'`, request rejected with
  `API-VALIDATION-013`; with `-25 hours`, allowed.
- E: tamper — cancelled row cannot swap `cancel_requested_by`, cannot change
  `cancel_expires_at`, cannot clear `cancel_declined_at`.
- F: accept by requester rejected; accept by partner deletes the row; drive/bucket/games/
  miss-you **and moods** gone; unrelated pending invitations for both users still present.
- G: expiry — force `cancel_expires_at` into the past as superuser, call
  `partnership_expire_cancellations()`, row back to accepted; data intact;
  `partnership_get_cancellation` lazily expires.
- H: 11.1/11.2 regressions (forged insert, sender accepts own, membership re-pointing).
- I: cancelled sender cannot request a new partnership; recipient with an accepted/cancelled
  row cannot accept another.
- J: mood insert attaches the accepted `partnership_id`; a mood cannot be attached to someone
  else's partnership.
- Update `rls_policy_matrix.test.sql` and `rpc_execute_grants.test.sql` for the narrowed
  delete policy and new function grants.

Run against the linked project: the new file plus `rls_partnership_creation.test.sql`,
`updated_at_triggers.test.sql`, `rls_self_scoped_with_check.test.sql`,
`rpc_execute_grants.test.sql`, `rls_policy_matrix.test.sql`, `rpc_error_codes.test.sql`.

### Backend

- `notification.service.test.js`: `cancellationRequested` resolves via the cancellation
  helper; other keys still use `getPartnerId`.
- New partnership endpoint tests: signature required, non-member rejected, requester cannot
  accept, expired request rejected (`-014`), R2 prefixes for both users and **no** `profile/`
  prefix, push sent once, R2 failure still returns success.
- `mediaWorkflow` tests: `media-complete` succeeds while `cancelled` and after the row is gone
  fails; `createUploadUrl` fails while `cancelled`.
- `retentionJob.test.js`: expired cancellations revert; non-expired untouched; RPC called.
- Full backend suite.

### Flutter

- `partner_state_test.dart` (fake repository) for cancellation fetch/transitions.
- Widget tests: profile button hidden without a partner; simple confirmation; PartnerScreen
  \"requested by me\" (plain restore, no expiry copy) and \"requested by partner\"
  (accept/decline); accept failure with the row gone → ended state; cooldown error.
- Realtime redirect test from a pushed route (not just MainShell) with no dialog.
- `flutter analyze` + `flutter test`.

### Manual, two accounts/devices

1. A requests → A waits on PartnerScreen; B is teleported there + push; no data visible to
   either.
2. B declines → both back in MainShell, data intact, A gets a push; A cannot re-request for
   24h, then can.
3. A requests, then restores → both back, data intact; A can re-request immediately (no
   cooldown for a self-restore).
4. A requests, B accepts → row + couple tables + moods gone, drive R2 folders empty, profile
   pictures still render, both on PartnerScreen, A gets the \"ended\" push; unrelated pending
   invitations still present.
5. Restart both apps while cancelled → state persists, no data loss.
6. Raw `DELETE` of the accepted/cancelled row with either JWT → denied.
7. Let a test request expire (forced column) → both back to accepted; B's accept at that point
   is rejected with \"expired\".
8. Kill the backend mid-accept (after DB delete, before R2) → rows gone, objects either swept
   or left for the orphan sweep; no crash loop.
9. Start a drive upload, then have the partner accept before it completes → the upload may
   finish (`media-complete` succeeds); a new upload cannot start.

### Rollout

- **Pre-flight duplicate check.** Because bug #2 allowed a user to hold two `accepted` rows,
  run before applying the trigger/guards:
  ```sql
  SELECT user_id, count(*)
  FROM (
    SELECT user_id_1 AS user_id FROM partnerships WHERE status = 'accepted'
    UNION ALL
    SELECT user_id_2 AS user_id FROM partnerships WHERE status = 'accepted'
  ) t
  GROUP BY user_id HAVING count(*) > 1;
  ```
  If any rows come back, repair them manually (the known temporary trigger-disable procedure)
  before rollout. There is no mood backfill; the mood table is empty.
- Apply the `ALTER` statements, trigger/RPC replacements, and policies to the linked project;
  update the declarative schema files to match (there is no migrations folder).
- Update docs, run the suites, commit feature files + docs only (never `todo.md`). Add the
  `todo.md` entry for the deferred recipient-side invite guard.

## 11. Bugs found while planning

1. `partnership_request` only checks the sender → third party can invite a paired user.
   **Deferred to `todo.md`** (§3.6); the sender-side check is extended to `cancelled` here.
2. `partnership_accept` does not check the recipient is already paired → second accepted row.
   **Fixed here.**
3. `partnerships_delete_own` (11.3) lets either member delete an accepted row from the client.
   **Fixed here** (§3.3).
4. `isRelevantPartnership` may ignore delete payloads (PK-only) → requester keeps seeing
   \"waiting\" after acceptance. Handled in §7.2 + pull-to-refresh.
5. `anon` still holds `DELETE`/`TRUNCATE` on `partnerships`. Revoked here (§3.3).

## 12. Decisions already taken

- Status `cancelled`; columns `cancel_requested_by`, `cancel_expires_at`, `cancel_declined_at`.
- Both users frozen while cancelled; no read access until resolved.
- Acceptance deletes all couple tables **and moods**; drive R2 files deleted; profile pictures
  and non-partnership objects kept.
- Backend resolves the ex-partner through one helper reused by the request push and
  `media-complete`.
- Auto-expiry: 7 days, no grace, silent, lazy read + 6h job, JS sweep-interval constant.
- 24h cooldown after a partner decline, via `cancel_declined_at`.
- Result pushes for decline and acceptance; zero notification on expiry.
- Real-time teleport to PartnerScreen, no intermediate dialog.
- No \"ended\" tombstone; no expiry date/countdown in the UI.
- Simple confirmation dialogs for both the request and the accept.
- Unrelated pending invitations are not deleted.
- Double-accept bug fixed here; recipient-side invite guard deferred.
- Acceptance endpoint is signed and is the only path that deletes.
