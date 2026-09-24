# Shared Drive & Media Gallery Subsystem - JustUS

## Overview

This document provides a comprehensive reverse-engineered analysis of the **Shared Drive & Media Gallery Subsystem** in the JustUS application. It traces the full execution lifecycle of media uploads, client-side validation and compression, Cloudflare R2 presigned URL generation, S3 object storage transfers, backend database registration, real-time synchronization, disk caching, and media playback for images, videos, audio, and documents.

The Shared Drive serves as a private, shared cloud gallery ("Violet Archive") for linked couples, allowing them to store memories, react with emojis, toggle favorite items, and stream media securely.

---

## Architecture & Component Mapping

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          FLUTTER FRONTEND LAYER                         │
│  DriveScreen • DriveItemScreen • FavoritesScreen • DriveGridItem        │
│  DriveUploadProgressBanner • DriveState • DriveRepository               │
│  MediaService • CompressionService • MediaCacheManager                  │
└────────────────────┬───────────────────────────────▲────────────────────┘
                     │                               │
       REST API /    │                               │ Supabase Realtime
       Supabase SDK  │                               │ Postgres Changes
                     ▼                               │ (table: drive_items)
┌───────────────────────────────────────┐            │
│       NODE.JS / EXPRESS API LAYER     │            │
│  POST /api/v1/media/presign-upload    │            │
│  POST /api/v1/media/complete-upload   │            │
│  GET /api/v1/media/download-signed    │            │
│  (Validates capability, size & MIME,  │            │
│   generates AWS S3 presigned URLs,    │            │
│   registers DB metadata)              │            │
└────────────────────┬──────────────────┘            │
                     │ AWS S3 Protocol               │
                     ▼ (Presigned PUT)               │
┌───────────────────────────────────────┐            │
│         CLOUDFLARE R2 BUCKET          │            │
│  Direct S3 Object Storage             │            │
│  Keys: uploads/{userId}/{uuid}-{name} │            │
└───────────────────────────────────────┘            │
                                                     │
┌────────────────────────────────────────────────────┴────────────────────┐
│                             SUPABASE LAYER                              │
│  Tables: public.drive_items, public.favorites, drive_item_reactions     │
│  View: v_drive_dashboard (security_invoker = true)                      │
│  RPC: get_or_create_emoji                                               │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Roles

1. **Flutter Frontend**:
   - [drive_screen.dart](file:///f:/JustUS/Flutter/lib/features/drive/screens/drive_screen.dart): UI rendering for memories gallery grid, category filter chips (All, Photos, Videos, Likes), FAB upload trigger, pull-to-refresh, and upload progress banner.
   - [drive_item_screen.dart](file:///f:/JustUS/Flutter/lib/features/drive/screens/drive_item_screen.dart): Full-screen viewer supporting interactive zoom for images (`InteractiveViewer`), video playback (`VideoPlayerController`), audio streaming (`AudioPlayer`), emoji reaction picker modal, and favorite toggling.
   - [favorites_screen.dart](file:///f:/JustUS/Flutter/lib/features/drive/screens/favorites_screen.dart): Filtered view rendering media items marked as favorite by the current user.
   - [drive_state.dart](file:///f:/JustUS/Flutter/lib/features/drive/drive_state.dart): State manager handling incremental sync, cache loading, optimistic deletions/favorites, reactions, and R2 upload triggers.
   - [drive_repository.dart](file:///f:/JustUS/Flutter/lib/features/drive/drive_repository.dart): Interacts with `v_drive_dashboard` view, Supabase database, and `MediaService`.
   - [media_service.dart](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart): Orchestrates MIME validation, pre-compression size checks, media compression, presigned URL acquisition, direct HTTP PUT to Cloudflare R2, thumbnail generation/upload for image items, and backend upload completion.
   - [compression_service.dart](file:///f:/JustUS/Flutter/lib/core/media/compression_service.dart): Performs image compression (~80% quality JPEG), video compression (MediumQuality), and low-res thumbnail generation (~320 px JPEG).
   - [media_cache_manager.dart](file:///f:/JustUS/Flutter/lib/core/media/media_cache_manager.dart): Custom `CacheManager` intercepting R2 storage keys, acquiring fresh signed URLs from backend, and caching media files locally on disk for up to 30 days.

2. **Node.js / Express API**:
   - [r2.service.js](file:///f:/JustUS/Backend/features/media/r2.service.js): AWS S3 SDK (`@aws-sdk/client-s3`) integration for Cloudflare R2. Sanitizes filenames, validates MIME/size, and generates S3 presigned PUT upload and GET download URLs.
   - [mediaWorkflow.service.js](file:///f:/JustUS/Backend/features/media/mediaWorkflow.service.js): Enforces upload permissions (`can_upload_large` capability for files > 5 MB), verifies storage key ownership (`/{userId}/`), updates user profile pictures or inserts `public.drive_items` records.
   - [media.controller.js](file:///f:/JustUS/Backend/features/media/media.controller.js): Route handlers `presignUploadController`, `completeUploadController`, and `redirectToSignedDownloadController`.

3. **Database Layer (Supabase / PostgreSQL)**:
   - `public.drive_items`: Main metadata table storing media items. Columns: `id`, `user_id`, `partner_id`, `type`, `filename` (R2 storage key), `original_name`, `mime_type`, `size`, `metadata` (JSONB), `created_at`, `updated_at`.
   - `public.favorites`: Stores user favorites (`user_id`, `item_id`).
   - `public.drive_item_reactions`: Stores emoji reactions (`id`, `item_id`, `user_id`, `emoji_id`).
   - `v_drive_dashboard`: Security invoker database view returning drive items for the calling user's partnership, joined with user favorites (`is_favorite` boolean) and aggregated emoji reactions (`reactions` JSONB array).

---

## Complete Upload Pipeline Trace

### Sequence Diagram

```
User App (Flutter)            Node.js Backend             Cloudflare R2          Supabase DB          Partner App
      │                             │                          │                      │                    │
      │ ── 1. Select File ─────────>│                          │                      │                    │
      │    (MediaPickerService)     │                          │                      │                    │
      │                             │                          │                      │                    │
      │ ── 2. MIME & Size Check ───>│                          │                      │                    │
      │    (MIME check + 15MB limit)│                          │                      │                    │
      │                             │                          │                      │                    │
      │ ── 3. Compression ─────────>│                          │                      │                    │
      │    (JPEG / Video Compress)  │                          │                      │                    │
      │                             │                          │                      │                    │
      │ ── 4. POST /presign-upload ─>│                          │                      │                    │
      │                             │ ── Generate PutObject ──>│                      │                    │
      │                             │    (Presigned URL 300s)  │                      │                    │
      │ <─ Returns Presigned URL ───│                          │                      │                    │
      │                             │                          │                      │                    │
      │ ── 5. HTTP PUT Media Bytes ───────────────────────────>│                      │                    │
      │                                (Direct R2 Upload)      │                      │                    │
      │ <─ HTTP 200 OK ────────────────────────────────────────│                      │                    │
      │                             │                          │                      │                    │
      │ ── 5b. PUT Thumbnail JPEG (image) ─────────────────────>│                      │                    │
      │    (2nd presigned URL, best-effort)                    │                      │                    │
      │ ── 6. POST /complete-upload ──>                        │                      │                    │
      │                             │ ── Insert drive_items ─────────────────────────>│                    │
      │ <─ Returns DB DriveItem ────│                          │                      │                    │
      │                             │                          │                      │                    │
      │ ── 7. Push & Realtime ────────────────────────────────────────────────────────────────────────────>│
      │    (notifyPartnerOnce + Supabase Realtime INSERT broadcast)                                        │ ── Refresh Drive
```

### Detailed Component Steps

1. **File Selection & Picker Bottom Sheet**
   - File: [media_picker_service.dart:15-113](file:///f:/JustUS/Flutter/lib/shared/utils/ui/media_picker_service.dart#L15-L113)
   - User taps the FAB (`+` icon) on `DriveScreen`.
   - `MediaPickerService.showPickerSheet(context)` opens a modal bottom sheet offering "Take Photo" (`ImageSource.camera`), "From Gallery" (`ImageSource.gallery`), "Audio" (`FileType.audio`), and "Document (PDF)" (`FileType.custom` with `['pdf']` extensions).
   - Uses `image_picker` for camera/gallery; `file_picker` for audio/PDF; returns an `XFile` with a MIME type (inferred from the file extension when the platform does not provide one).

2. **Client Validation & Compression Order**
   - File: [media_service.dart:38-60](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L38-L60) & [compression_service.dart:43-46](file:///f:/JustUS/Flutter/lib/core/media/compression_service.dart#L43-L46)
   - **Step A: MIME Inferencing & Validation**: `_inferMime()` infers MIME type from extension if not provided. Validates against `_allowedMimes` map. If invalid, throws `Exception('Invalid MIME type')`.
   - **Step B: Size Guard BEFORE Compression (Fast-Fail)**: Checks `CompressionService.isWithinSizeLimit(file)`. If the original uncompressed file exceeds 15 MB (`15 * 1024 * 1024` bytes), it throws `Exception('File exceeds 15 MB limit before compression')` immediately.
   - **Step C: Compression Execution**:
     - `MediaType.image`: Compressed via `FlutterImageCompress.compressAndGetFile(quality: 80)` to ~80% quality JPEG.
     - `MediaType.video`: Compressed via `VideoCompress.compressVideo(quality: VideoQuality.MediumQuality)`.
     - `MediaType.audio` / `MediaType.file`: No compression applied (returns original file).
   - **Step D: Final Size & Filename Extraction**: `finalSize = await compressed.length()`. Extracts `originalName` from file path.

3. **Backend Presigned Upload URL Request**
   - File: [media_service.dart:65-81](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L65-L81) & [r2.service.js:76-96](file:///f:/JustUS/Backend/features/media/r2.service.js#L76-L96)
   - Flutter calls `ApiService.createMediaUploadUrl()` sending `POST /api/v1/media/presign-upload`.
   - Backend `presignUploadController` -> `createPresignedUpload()`:
     - Checks user capability `can_upload_large` if `size > 5 MB` (`largeUploadThresholdBytes`).
     - Validates size <= `maxUploadBytes` (15 MB) and checks allowed MIME types in `r2.service.js`.
     - Sanitizes filename into a safe base name.
     - Builds object key: `uploads/{userId}/{timestamp}-{uuid}-{basename}{extension}` (or `profile/{userId}/...`).
     - Uses `@aws-sdk/s3-request-presigner` `getSignedUrl` with `PutObjectCommand` to generate an S3 presigned PUT URL valid for **300 seconds (5 minutes)** (`mediaUploadUrlExpiresSeconds`).
   - Returns `{ success: true, uploadUrl, filename, expiresIn }`.

4. **Direct R2 S3 HTTP PUT Upload**
   - File: [media_service.dart:84-94](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L84-L94)
   - Flutter executes direct binary upload: `http.put(Uri.parse(uploadUrl), body: await compressed.readAsBytes(), headers: {'Content-Type': mime})`.
   - Bypasses Node.js backend server memory for heavy file transfers.
   - Verifies response `statusCode == 200`.

4b. **Thumbnail Generation & Upload (image drive items, best-effort)**
   - File: [compression_service.dart:25-38](file:///f:/JustUS/Flutter/lib/core/media/compression_service.dart#L25-L38) & [media_service.dart:96-126](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L96-L126)
   - For `type == image` drive uploads (`skipRegistration == false`), `CompressionService.createThumbnail` produces a small (≤320 px, ~70% quality) JPEG.
   - A second `POST /media/upload-url` (existing endpoint, `thumb.jpg` filename) yields a fresh presigned URL; the thumb is PUT to R2 under the same `uploads/{userId}/...` prefix.
   - Any presign/PUT failure is logged and results in **no thumbnail** (never fails the main upload).
   - The thumbnail storage key is passed in `metadata.thumbnail` to `/complete-upload` and stored in `drive_items.metadata` (JSONB) — no new column.

5. **Backend Database Registration**
   - File: [media_service.dart:97-125](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L97-L125) & [mediaWorkflow.service.js:43-100](file:///f:/JustUS/Backend/features/media/mediaWorkflow.service.js#L43-L100)
   - Flutter sends `POST /api/v1/media/complete-upload` containing `{ kind, type, filename, originalName, mimeType, size, metadata }`.
   - Backend `registerCompletedUpload()`:
     - Verifies storage key contains expected user segment `/${user.profileId}/` to prevent key hijacking.
     - **Profile Picture Flow** (`kind === 'profile'`): Updates `user_profiles.profile_pic_url = filename` for `user_id = user.profileId`.
     - **Drive Item Flow** (`kind === 'drive'`): Fetches partner ID via `getPartnerId()`. Inserts record into `public.drive_items` returning created `item` object.

6. **Realtime Sync & Partner Notification**
   - File: [drive_repository.dart:73-78](file:///f:/JustUS/Flutter/lib/features/drive/drive_repository.dart#L73-L78) & [refetch_realtime_handler.dart](file:///f:/JustUS/Flutter/lib/core/realtime/refetch_realtime_handler.dart)
   - Flutter triggers push notification `notifyPartnerOnce(notificationKey: 'driveItemAdded')`.
   - Supabase Realtime emits `INSERT` event on `public.drive_items`.
   - Partner's `RefetchRealtimeHandler.handle` catches the event, debounces for 150 ms, and calls `DriveState.refreshFromRealtime()`.

7. **Gallery UI Update**
   - File: [drive_state.dart:185-190](file:///f:/JustUS/Flutter/lib/features/drive/drive_state.dart#L185-L190)
   - `DriveState` prepends newly created `DriveItem` to `_driveItems`, updates `_favoriteItems`, persists updated list to `StorageService.saveDriveItems()`, and notifies UI listeners.

---

## Item Deletion Flow

- Files: [drive_repository.dart:88-113](file:///f:/JustUS/Flutter/lib/features/drive/drive_repository.dart#L88-L113), [drive_state.dart:263-283](file:///f:/JustUS/Flutter/lib/features/drive/drive_state.dart#L263-L283), [media.controller.js](file:///f:/JustUS/Backend/features/media/media.controller.js).
```
DriveScreen context menu → DriveState.deleteItem(id) (optimistic removal + cache rewrite)
  → DriveRepository.deleteDriveItem(id) → ApiService.deleteMediaItem(id)
  → POST /api/v1/media/delete { id } (HMAC-signed, capability can_media_upload)
  → Backend deleteMediaController:
      - Reads drive_items(id, user_id, partner_id, filename, metadata) via adminSupabase
      - Idempotent: row already gone → 200 no-op (stale retries never resurrect the item)
      - Rejects 403 if the caller is not user_id/partner_id (AUTH-FAIL-004)
      - Deletes the drive_items row first (favorites/reactions cascade), re-asserting
        ownership in the DELETE predicate (defense in depth)
      - Best-effort R2 cleanup (purgeR2Object): deletes the full-size object and the
        thumbnail (metadata.thumbnail) when present; failures logged, never block the
        response; orphaned objects are reclaimed by retentionJob sweepStaleOrphanObjects
        (24 h cutoff, which also references metadata.thumbnail keys)
  → Success → snackbar; failure → local list restored (drive_state.dart:277-281)
```
- Obsolete direct SQL deletion (`sbClient.from('drive_items').delete()`) was replaced by this backend endpoint so R2 cleanup can never leave a dangling row (row delete is the transactional step; R2 is a best-effort side effect).
- The client treats a `DB-NOT_FOUND-001` response (`drive_repository.dart` `_isAlreadyDeleted`) as success, so a lost-response retry does not restore an already-deleted item locally.
- The same R2 deletion primitive (`deleteObjectsByPrefix`) is reused by the account wipe to purge all objects under a user's prefixes.

---

## Media Type Specifications & Format Handling

| Media Type | Supported MIME Types | Client Compression | Gallery Rendering | Full-Screen Viewer Widget |
|---|---|---|---|---|
| **Image** | `image/jpeg`, `image/png`, `image/webp`, `image/gif` | `FlutterImageCompress` (~80% quality JPEG) | `CachedNetworkImage` via `MediaCacheManager` | `InteractiveViewer` + `ProtectedNetworkImage` |
| **Video** | `video/mp4`, `video/quicktime`, `video/x-msvideo` | `VideoCompress` (`MediumQuality`) | `CachedNetworkImage` with Play Icon overlay | `VideoPlayerController.networkUrl` |
| **Audio** | `audio/mpeg`, `audio/mp4`, `audio/ogg`, `audio/wav` | None (Original file) | N/A (UI picker unexposed) | `AudioPlayer` (`audioplayers` package) |
| **PDF / File**| `application/pdf`, `application/octet-stream` | None (Original file) | `Icon(Icons.insert_drive_file)` | Generic File Icon + Filename text |

---

## Validation & Compression Order Analysis

### Exact Sequence of Execution

```
[1] MIME Validation  ──>  [2] Size Guard (<=15MB)  ──>  [3] Compression  ──>  [4] Thumbnail (image)  ──>  [5] Presign + PUT main  ──>  [6] PUT thumbnail  ──>  [7] Complete
```

1. **MIME Validation**: Executed first in `MediaService.uploadMedia()` ([media_service.dart:39-43](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L39-L43)). Infers MIME from extension and checks against allowed MIME map.
2. **Size Guard**: Executed second in `MediaService.uploadMedia()` ([media_service.dart:46-48](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L46-L48)). Calls `CompressionService.isWithinSizeLimit(file)`.
3. **Compression**: Executed third in `MediaService.uploadMedia()` ([media_service.dart:52-59](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L52-L59)). Compresses images/videos.
4. **Thumbnail**: For image drive items, `CompressionService.createThumbnail` produces a ≤320 px JPEG ([compression_service.dart:32](file:///f:/JustUS/Flutter/lib/core/media/compression_service.dart#L32)).
5. **Upload**: Presign + PUT of the compressed main file ([media_service.dart:65-95](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L65-L95)).
6. **Thumbnail Upload**: Second presign + PUT of the thumbnail (best-effort, image items only).
7. **Complete**: `POST /media/complete-upload` registers the `drive_items` row (metadata includes `thumbnail` when present).

### 15 MB Size Limit (intended behavior)

The 15 MB limit (`15 * 1024 * 1024` bytes) is a deliberate hard cap on **source files**, evaluated **BEFORE compression** as a fast-fail guard on the client ([media_service.dart:46](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L46)). This is intended behavior, not a defect (todo 5.4):

- **Client Guard**: `CompressionService.isWithinSizeLimit(file)` rejects any original file larger than 15 MB immediately, before any compression work is started. Files at or under the cap are then compressed (~80% quality JPEG / medium H.264) so the payload that actually reaches R2 is typically far smaller.
- **Backend Check**: The backend additionally validates the size sent at presign against `env.maxUploadBytes` (15 MB) in `r2.service.js`. That size is the **post-compression** `finalSize`, so the R2 upload itself never exceeds the cap.

---

## Cloudflare R2, Presigned URLs & Caching

### Presigned URL Specifications

- **Upload URL Lifetime**: **300 seconds (5 minutes)** (`MEDIA_UPLOAD_URL_EXPIRES_SECONDS` in [env.js:38](file:///f:/JustUS/Backend/config/env.js#L38)).
- **Download URL Lifetime**: **300 seconds (5 minutes)** (`MEDIA_DOWNLOAD_URL_EXPIRES_SECONDS` in [env.js:39](file:///f:/JustUS/Backend/config/env.js#L39)).
- **Signed Download Route**: `GET /api/v1/media/download-signed?filename=...`
  - Validates caller authentication.
  - Queries `public.drive_items` to confirm `media.user_id === userId || media.partner_id === userId`.
  - Generates S3 `GetObjectCommand` presigned URL and returns an HTTP `302 Redirect` to Cloudflare R2.

### Disk Caching Architecture (`MediaCacheManager`)

- File: [media_cache_manager.dart:8-43](file:///f:/JustUS/Flutter/lib/core/media/media_cache_manager.dart#L8-L43)
- Flutter uses a custom `CacheManager` (`MediaCacheManager`) for gallery grid images:
  - **Stale Period**: **30 days** (`Duration(days: 30)`).
  - **Max Cache Objects**: 300 items.
  - **Custom File Service (`_R2FileService`)**:
    - Intercepts image URLs in `CachedNetworkImage`.
    - If URL starts with R2 storage key pattern `users/`, it exchanges the key for a fresh signed URL by calling `MediaService.getDownloadUrl(url)`.
    - Streams and caches the binary image file locally on device disk under cache key `justus_media_cache`.
    - Subsequent gallery renders load the image directly from local disk cache without contacting backend or Cloudflare R2, bypassing signed URL expiration issues for cached items.

---

## Incremental Synchronization & Checkpoint Strategy

### Sync Pipeline

- File: [drive_state.dart:70-104](file:///f:/JustUS/Flutter/lib/features/drive/drive_state.dart#L70-L104) & [drive_repository.dart:24-40](file:///f:/JustUS/Flutter/lib/features/drive/drive_repository.dart#L24-L40)
- **Checkpoint Key**: `CacheService.kDriveItems` (`chk_drive_items`).
- **Execution Flow**:
  1. `DriveState.initialLoad()` invokes `loadWithChangeDetection()`.
  2. Checks `_hasDriveChanges()` using `DriveRepository.hasNewDriveItems()`, which queries `v_drive_dashboard` for `updated_at > checkpoint_timestamp`.
  3. If changes exist, `syncDriveItems()` executes `fetchDriveItemsIncremental()`:
     - Queries `v_drive_dashboard` filtering `updated_at > lastSyncTimestamp`.
     - Merges new/updated records into `_driveItems` (overwriting existing items with matching IDs).
     - Sorts list by `createdAt DESC`.
     - Updates `_favoriteItems`.
     - Persists merged list to `StorageService.saveDriveItems()`.
     - Updates max timestamp checkpoint via `saveMaxTimestampCheckpointFromItems()`.

---

## Favorites & Emoji Reactions Subsystem

Favorites and emoji reactions are architecturally decoupled from media object storage:

### Favorites Subsystem

- Table: `public.favorites` (`user_id`, `item_id`).
- RLS Policy: `favorites_own` (FOR ALL) — users can manage only their own favorites, and the referenced `item_id` must belong to an **accepted** partnership (`WITH CHECK user_id = current_user_id() AND item in accepted partnership`).
- Toggle Execution: `DriveRepository.toggleFavorite(itemId, isFavorite)` ([drive_repository.dart:88-103](file:///f:/JustUS/Flutter/lib/features/drive/drive_repository.dart#L88-L103)).
  - If `isFavorite == true`: Inserts row into `public.favorites`.
  - If `isFavorite == false`: Deletes row matching `user_id` and `item_id`.
- View Integration: `v_drive_dashboard` performs a `LEFT JOIN favorites` returning `is_favorite` (1 or 0) tailored to the calling user.
- State Management: `DriveState` performs optimistic toggling and maintains a filtered getter `favoriteItems` rendered in `FavoritesScreen`.

### Emoji Reactions Subsystem

- Table: `public.drive_item_reactions` (`id`, `item_id`, `user_id`, `emoji_id`).
- Add Reaction Execution: `DriveRepository.addReaction(itemId, emojiChar)` ([drive_repository.dart:121-147](file:///f:/JustUS/Flutter/lib/features/drive/drive_repository.dart#L121-L147)).
  - Calls PostgreSQL RPC `get_or_create_emoji(p_emoji_char)` to resolve `emoji_id`.
  - Inserts row into `public.drive_item_reactions`.
  - Fires partner push notification `notifyPartnerOnce('reactionAdded')`.
- View Integration: `v_drive_dashboard` aggregates reactions into a JSONB array of emoji strings returned with each drive item payload.

---

## Profile Picture Upload Integration

Profile picture uploads share the underlying R2 storage pipeline with the Shared Drive:

- File: [media_service.dart:134-144](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L134-L144)
- Invokes `uploadMedia()` with `type = MediaType.image`, `customFolder = 'profile'`, and `skipRegistration = true`.
- Object Key: `profile/{userId}/{timestamp}-{uuid}-{basename}.jpg`.
- Backend Completion: `registerCompletedUpload()` detects `kind === 'profile'`, skips `drive_items` table insertion, and updates `user_profiles.profile_pic_url = filename`.

---

## Discovered Bugs, Defects, and Storage Inconsistencies

During reverse-engineering analysis, the following technical findings were identified:

### 1. LIMITATION: Videos and legacy items still load full-size files in the grid

* **WHAT**: Image uploads now get a small thumbnail (todo 5.5), but video grid cells still fetch the full MP4 (poster-frame preview), and items uploaded before the thumbnail pipeline have no thumbnail and load the full-size image in the grid.
* **WHERE**: [drive_screen.dart:317-333](file:///f:/JustUS/Flutter/lib/features/drive/screens/drive_screen.dart#L317-L333), [drive_grid_item.dart:67-113](file:///f:/JustUS/Flutter/lib/features/drive/widgets/drive_grid_item.dart#L67-L113)
* **WHY**: No video poster-frame extraction and no backfill of thumbnails for pre-existing items.
* **WHEN**: Rendering the gallery grid on slow networks.
* **IMPACT**: Slower grid rendering and higher data consumption for video and legacy image tiles.
* **CONFIDENCE**: **HIGH**

### 2. INFORMATION: Audio and PDF uploads exposed; non-image tiles render a generic placeholder

* **WHAT**: The drive bottom sheet now exposes "Audio" and "Document (PDF)" pickers via `file_picker`, so audio/PDF files can be uploaded through the same R2 presigned flow. `MediaService` treats `MediaType.audio`/`MediaType.file` as already-compressed (no re-compression). In the grid, audio and PDF items still render the generic image placeholder until tapped; the actual payload is only loaded in `DriveItemScreen` (audio is playable with `audioplayers`, PDFs display as a file card).
* **WHERE**: [media_picker_service.dart:89-105](file:///f:/JustUS/Flutter/lib/shared/utils/ui/media_picker_service.dart#L89-L105), [drive_screen.dart:317-333](file:///f:/JustUS/Flutter/lib/features/drive/screens/drive_screen.dart#L317-L333)
* **WHY**: Grid cells use a single image surface (`CachedNetworkImage`); no per-type tile builder exists for audio/PDF.
* **WHEN**: Browsing the grid after uploading audio or a PDF.
* **IMPACT**: Audio/PDF items still consume a grid cell with a generic icon; acceptable for a media gallery, but a dedicated tile (e.g. waveform/PDF preview) would better signal the type.
* **CONFIDENCE**: **HIGH**

---

## Implementation Status Matrix

| Subsystem / Feature | Status | Notes |
|---|---|---|
| Camera / Gallery / Audio / PDF Bottom Sheet | **IMPLEMENTED** | `MediaPickerService`: `image_picker` (camera/gallery) + `file_picker` (audio/PDF) |
| Image Upload & Compression | **IMPLEMENTED** | `FlutterImageCompress` (~80% quality JPEG) |
| Video Upload & Compression | **IMPLEMENTED** | `VideoCompress` (`MediumQuality`) |
| Audio & Document Upload API | **IMPLEMENTED** | Supported in `MediaService` & Backend API; now reachable from the bottom sheet via `file_picker` |
| Cloudflare R2 Presigned PUT URLs | **IMPLEMENTED** | S3 `PutObjectCommand` (300s lifetime) |
| Cloudflare R2 Presigned GET Redirect | **IMPLEMENTED** | `GET /api/v1/media/download-signed` (300s lifetime) |
| Local Media Disk Cache | **IMPLEMENTED** | `MediaCacheManager` (30-day stale period) |
| Incremental Sync & Checkpoints | **IMPLEMENTED** | `v_drive_dashboard` query on `updated_at > checkpoint` |
| Favorites Subsystem | **IMPLEMENTED** | `public.favorites` + `v_drive_dashboard` join |
| Emoji Reactions Subsystem | **IMPLEMENTED** | `public.drive_item_reactions` + `get_or_create_emoji` |
| Profile Picture Upload | **IMPLEMENTED** | Custom R2 folder `profile/` + `user_profiles` update |
| R2 Storage Deletion Cleanup | **IMPLEMENTED** | `POST /api/v1/media/delete` deletes row first + best-effort R2 object; orphan safety net via `retentionJob.sweepStaleOrphanObjects` (24 h); wipe purges all user-prefix objects |
| Failed Upload-Completion Orphan Cleanup | **IMPLEMENTED** | PUT-to-R2-then-`/complete-upload` interruption (`media_service.dart`) leaves an object for ≤24 h; `retentionJob.sweepStaleOrphanObjects` (6-hour cadence, `ORPHAN_MAX_AGE_MS` 24 h, `uploads/` + `profile/` prefixes vs `drive_items.filename` / `user_profiles.profile_pic_url`) reclaims it — no permanent orphan accumulation (todo 5.3) |
| 15 MB Upload Size Cap | **IMPLEMENTED** | Deliberate 15 MB hard cap on source files: client fast-fail pre-compression (`CompressionService.isWithinSizeLimit`, media_service.dart:46) + backend presign validation on the post-compression `size` (`env.maxUploadBytes`) — intended behavior (todo 5.4), not a defect |
| Media Thumbnail Generation | **IMPLEMENTED** | Client-side ≤320 px JPEG (`CompressionService.createThumbnail`, `FlutterImageCompress`) generated at upload for image drive items, stored as a `*_thumb.jpg` object in R2 (2nd presigned URL, best-effort) with its key in `drive_items.metadata.thumbnail` (JSONB); grid + favorites render `DriveItem.contentThumb` (tiny file), tap loads the full file. Videos and pre-feature items fall back to full size (todo 5.5) |
| Audio / PDF Picker Button in UI | **NOT IMPLEMENTED** | Picker sheet lacks document/audio options |
