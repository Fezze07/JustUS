# Media Delete & R2 Orphan Audit

Scope: the drive-item deletion path (`POST /api/v1/media/delete`), its R2 object cleanup, and the storage safety net. Related todo item: **5.2 R2 orphan on drive-item deletion**.

## Current Implementation

### Delete flow

```
DriveScreen context menu → DriveState.deleteItem(id) (optimistic removal + cache rewrite)
  → DriveRepository.deleteDriveItem(id) → ApiService.deleteMediaItem(id)
  → POST /api/v1/media/delete { id } (HMAC-signed, capability can_media_upload)
  → Backend deleteMediaController:
      - Reads drive_items(id, user_id, partner_id, filename) via adminSupabase
      - Idempotent: row already gone → 200 success (no-op)
      - Rejects 403 if the caller is not user_id/partner_id (AUTH-FAIL-004)
      - Deletes the drive_items row first (favorites/reactions cascade), re-asserting
        ownership in the DELETE predicate (user_id.eq.X,partner_id.eq.X) — defense in depth
      - Best-effort R2 cleanup via purgeR2Object(): failures are logged
        (media.delete.r2_cleanup_failed) and never block the response — an orphaned
        object is reclaimed by the retention sweep (below)
  → Success → snackbar; failure → local list restored
```

Rationale for the DB-first ordering:

- Deleting the row first means a failed row delete (the only transactional step) never leaves a dangling `drive_items` row pointing at a deleted object.
- R2 is a non-transactional side effect; a best-effort failure leaves an orphaned object, which the safety net below reclaims. An R2 outage therefore no longer blocks the user from deleting media.

Client idempotency: `DriveRepository.deleteDriveItem` maps a `DB-NOT_FOUND-001` response (`_isAlreadyDeleted`) to success, so an optimistic delete is never resurrected by a stale retry.

### Orphan safety net

- `retentionJob.js` runs `sweepStaleOrphanObjects()` every 6 h: lists finalized objects under `uploads/` and `profile/` (via the new `r2.service.listObjects`, which also returns `LastModified`), cross-checks against `drive_items.filename`, `drive_items.metadata.thumbnail`, and `user_profiles.profile_pic_url`, and batch-deletes objects older than 24 h that no DB row references.
- A grace window (24 h) protects objects uploaded-but-not-yet-registered (in-flight `/complete`).
- Incomplete multipart uploads remain handled by `sweepStalMultipartUploads()` (48 h).
- Backend helpers exposed through `all_imports.js`: `listObjects` (new), `deleteObjects`, `listObjectKeys`.

## Findings

The following item is intentionally retained — it is a low-severity observation, not a bug in the delete path:

- **F-5. Delete shares the media rate-limit bucket with uploads** — `POST /media/delete` uses the same `mediaRateLimit` (ipMax 60 / userMax 40 per window) as `upload-url` + `complete` (media.routes.js:25-30, 66-76). A bulk-delete pass burns the same allowance as uploads. Kept as-is for consistency with the other media routes.

Optimistic delete still restores the item locally on a genuine network error when the server state is unknown; an idempotent retry and the next refresh reconcile it.

---

**Tracking**: todo.md item 5.2 (status tracked only there, per AGENTS.md).