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
   - [media_service.dart](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart): Orchestrates MIME validation, pre-compression size checks, media compression, presigned URL acquisition, direct HTTP PUT to Cloudflare R2, and backend upload completion.
   - [compression_service.dart](file:///f:/JustUS/Flutter/lib/core/media/compression_service.dart): Performs image compression (~80% quality JPEG) and video compression (MediumQuality).
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
      │ ── 6. POST /complete-upload ──>                        │                      │                    │
      │                             │ ── Insert drive_items ─────────────────────────>│                    │
      │ <─ Returns DB DriveItem ────│                          │                      │                    │
      │                             │                          │                      │                    │
      │ ── 7. Push & Realtime ────────────────────────────────────────────────────────────────────────────>│
      │    (notifyPartnerOnce + Supabase Realtime INSERT broadcast)                                        │ ── Refresh Drive
```

### Detailed Component Steps

1. **File Selection & Picker Bottom Sheet**
   - File: [media_picker_service.dart:14-49](file:///f:/JustUS/Flutter/lib/shared/utils/ui/media_picker_service.dart#L14-L49)
   - User taps the FAB (`+` icon) on `DriveScreen`.
   - `MediaPickerService.showPickerSheet(context)` opens a modal bottom sheet offering "Take Photo" (`ImageSource.camera`) and "From Gallery" (`ImageSource.gallery`).
   - Uses `image_picker` package to acquire `XFile`.

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

5. **Backend Database Registration**
   - File: [media_service.dart:97-125](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L97-L125) & [mediaWorkflow.service.js:43-100](file:///f:/JustUS/Backend/features/media/mediaWorkflow.service.js#L43-L100)
   - Flutter sends `POST /api/v1/media/complete-upload` containing `{ kind, type, filename, originalName, mimeType, size, metadata }`.
   - Backend `registerCompletedUpload()`:
     - Verifies storage key contains expected user segment `/${user.profileId}/` to prevent key hijacking.
     - **Profile Picture Flow** (`kind === 'profile'`): Updates `user_profiles.profile_pic_url = filename` for `user_id = user.profileId`.
     - **Drive Item Flow** (`kind === 'drive'`): Fetches partner ID via `getPartnerId()`. Inserts record into `public.drive_items` returning created `item` object.

6. **Realtime Sync & Partner Notification**
   - File: [drive_repository.dart:73-78](file:///f:/JustUS/Flutter/lib/features/drive/drive_repository.dart#L73-L78) & [realtime_sync_service.dart:496-507](file:///f:/JustUS/Flutter/lib/core/realtime/realtime_sync_service.dart#L496-L507)
   - Flutter triggers push notification `notifyPartnerOnce(notificationKey: 'driveItemAdded')`.
   - Supabase Realtime emits `INSERT` event on `public.drive_items`.
   - Partner's `RealtimeSyncService._handleDrivePayload` catches event, debounces for 150ms (`_driveRefreshTimer`), and calls `DriveState.refreshFromRealtime()`.

7. **Gallery UI Update**
   - File: [drive_state.dart:185-190](file:///f:/JustUS/Flutter/lib/features/drive/drive_state.dart#L185-L190)
   - `DriveState` prepends newly created `DriveItem` to `_driveItems`, updates `_favoriteItems`, persists updated list to `StorageService.saveDriveItems()`, and notifies UI listeners.

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
[1] MIME Validation  ──>  [2] Size Guard (<=15MB)  ──>  [3] Compression  ──>  [4] Upload
```

1. **MIME Validation**: Executed first in `MediaService.uploadMedia()` ([media_service.dart:39-43](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L39-L43)). Infers MIME from extension and checks against allowed MIME map.
2. **Size Guard**: Executed second in `MediaService.uploadMedia()` ([media_service.dart:46-48](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L46-L48)). Calls `CompressionService.isWithinSizeLimit(file)`.
3. **Compression**: Executed third in `MediaService.uploadMedia()` ([media_service.dart:52-59](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L52-L59)). Compresses images/videos.
4. **Upload**: Executed fourth after acquiring backend presigned PUT URL.

### 15 MB Limit Analysis

> [!IMPORTANT]
> **Finding**: The 15 MB size limit (`15 * 1024 * 1024` bytes) is evaluated **BEFORE compression** on the client application ([media_service.dart:46](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L46)).
>
> - **Behavior**: If an uncompressed high-resolution image or raw video file is 16 MB on disk, `CompressionService.isWithinSizeLimit(file)` returns `false` and aborts upload immediately, even though client compression would have reduced its final size to ~2 MB.
> - **Backend Check**: The backend API (`r2.service.js:59`) also validates file size against `env.maxUploadBytes` (15 MB), but receives `finalSize` (the post-compression size).

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
- RLS Policy: Users can only manage their own favorites.
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

### 1. DEFECT: Orphaned R2 Storage Objects on Item Deletion

* **WHAT**: Deleting a drive item from the app leaves the binary media file stored permanently in Cloudflare R2.
* **WHERE**: [drive_repository.dart:82-86](file:///f:/JustUS/Flutter/lib/features/drive/drive_repository.dart#L82-L86)
* **WHY**: `deleteDriveItem(id)` executes a direct SQL `DELETE FROM drive_items WHERE id = ?`. **No S3 DeleteObjectCommand or backend cleanup service is invoked**.
* **WHEN**: User deletes a photo, video, or file from the drive.
* **IMPACT**: Storage leak. Deleted files accumulate in Cloudflare R2 bucket indefinitely.
* **CONFIDENCE**: **HIGH**

### 2. DEFECT: Orphaned R2 Storage Objects on Failed Upload Completion

* **WHAT**: If direct HTTP PUT upload to R2 succeeds, but `completeMediaUpload` fails (due to network drop or app crash), the R2 object is orphaned.
* **WHERE**: [media_service.dart:85-116](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L85-L116)
* **WHY**: Upload to R2 and metadata registration in Supabase DB are two separate un-transactional HTTP calls.
* **WHEN**: Network drops right after S3 PUT completes before sending `/complete-upload`.
* **IMPACT**: Storage leak in R2 bucket with no corresponding database record.
* **CONFIDENCE**: **HIGH**

### 3. INCONSISTENCY: Pre-Compression Fast-Fail Rejects Valid Files

* **WHAT**: Files larger than 15 MB on disk are rejected before compression is attempted.
* **WHERE**: [media_service.dart:46](file:///f:/JustUS/Flutter/lib/core/media/media_service.dart#L46)
* **WHY**: `CompressionService.isWithinSizeLimit(file)` checks `file.lengthSync() <= 15 MB` prior to calling `compressImage` / `compressVideo`.
* **WHEN**: User selects a 16 MB high-resolution camera photo or video.
* **IMPACT**: User receives a "File exceeds 15 MB limit" error, even though compression would have reduced file size well below 15 MB.
* **CONFIDENCE**: **HIGH**

### 4. LIMITATION: Missing Thumbnail Generation

* **WHAT**: Full-sized compressed media files are loaded directly into 3-column gallery grid views.
* **WHERE**: [drive_screen.dart:317-333](file:///f:/JustUS/Flutter/lib/features/drive/screens/drive_screen.dart#L317-L333)
* **WHY**: No backend worker, AWS Lambda, or Cloudflare Worker generates low-resolution thumbnails or video poster frames.
* **WHEN**: Loading gallery grid on slow networks.
* **IMPACT**: Increased data consumption and slower grid rendering on mobile networks.
* **CONFIDENCE**: **HIGH**

### 5. LIMITATION: Unexposed UI Picker for Audio and PDF Files

* **WHAT**: `MediaService` and Backend API support uploading audio and PDF files, but `MediaPickerService` in `DriveScreen` only presents Camera and Gallery options.
* **WHERE**: [media_picker_service.dart:27-42](file:///f:/JustUS/Flutter/lib/shared/utils/ui/media_picker_service.dart#L27-L42)
* **WHY**: Bottom sheet presents only `ImageSource.camera` and `ImageSource.gallery`. No document or audio file picker button exists in UI.
* **WHEN**: User attempts to upload a PDF document or audio file to the drive.
* **IMPACT**: Audio and document upload capabilities are unreachable via the primary UI picker.
* **CONFIDENCE**: **HIGH**

---

## Implementation Status Matrix

| Subsystem / Feature | Status | Notes |
|---|---|---|
| Camera / Gallery Bottom Sheet | **IMPLEMENTED** | `MediaPickerService` using `image_picker` |
| Image Upload & Compression | **IMPLEMENTED** | `FlutterImageCompress` (~80% quality JPEG) |
| Video Upload & Compression | **IMPLEMENTED** | `VideoCompress` (`MediumQuality`) |
| Audio & Document Upload API | **IMPLEMENTED** | Supported in `MediaService` & Backend API |
| Cloudflare R2 Presigned PUT URLs | **IMPLEMENTED** | S3 `PutObjectCommand` (300s lifetime) |
| Cloudflare R2 Presigned GET Redirect | **IMPLEMENTED** | `GET /api/v1/media/download-signed` (300s lifetime) |
| Local Media Disk Cache | **IMPLEMENTED** | `MediaCacheManager` (30-day stale period) |
| Incremental Sync & Checkpoints | **IMPLEMENTED** | `v_drive_dashboard` query on `updated_at > checkpoint` |
| Favorites Subsystem | **IMPLEMENTED** | `public.favorites` + `v_drive_dashboard` join |
| Emoji Reactions Subsystem | **IMPLEMENTED** | `public.drive_item_reactions` + `get_or_create_emoji` |
| Profile Picture Upload | **IMPLEMENTED** | Custom R2 folder `profile/` + `user_profiles` update |
| R2 Storage Deletion Cleanup | **NOT IMPLEMENTED** | DB deletion leaves orphaned objects in R2 |
| Post-Compression Size Check | **NOT IMPLEMENTED** | 15 MB size check runs before compression |
| Media Thumbnail Generation | **NOT IMPLEMENTED** | Full-sized media loaded in grid view |
| Audio / PDF Picker Button in UI | **NOT IMPLEMENTED** | Picker sheet lacks document/audio options |
