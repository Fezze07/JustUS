import 'dart:async';
import 'dart:io' as dart_io;

import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'package:justus/all_imports.dart';

class DriveRepository extends BaseRepository {
  final MediaService _mediaService;

  DriveRepository({super.sbClient, MediaService? mediaService})
      : _mediaService = mediaService ?? MediaService();

  Future<ResultWrapper<List<DriveItem>>> fetchDriveItems() async {
    return tryCall(() async {
      final data = await sbClient
          .from('v_drive_dashboard')
          .select()
          .order('created_at', ascending: false)
          .toList();

      return data.map((d) => DriveItem.fromJson(d)).toList();
    });
  }

  Future<ResultWrapper<List<DriveItem>>> fetchDriveItemsIncremental() async {
    return tryCall(() async {
      final lastSyncTimestamp =
          await CacheService.getCheckpoint(CacheService.kDriveItems);
      var query = sbClient.from('v_drive_dashboard').select();

      if (lastSyncTimestamp != null &&
          lastSyncTimestamp.isNotEmpty &&
          lastSyncTimestamp != CacheService.kCheckpointEmpty) {
        query = query.gt('updated_at', lastSyncTimestamp);
      }

      final data = await query.order('created_at', ascending: false).toList();

      return data.map((d) => DriveItem.fromJson(d)).toList();
    });
  }

  /// One round trip for the whole revalidation gate: newest `updated_at` +
  /// server row count (see `public.drive_change_probe()` and [DriveChangeProbe]).
  ///
  /// Falls back to the historical two-request probe (`select(updated_at) … limit
  /// 1` + `count()` on the view) when the function is missing on the server, so
  /// a not-yet-migrated database degrades to "two requests" instead of "the
  /// drive list never revalidates". The fallback self-disables once the function
  /// exists and can be deleted after the migration is deployed everywhere.
  Future<ResultWrapper<DriveChangeProbe>> fetchChangeProbe() {
    return tryCall(() async {
      try {
        final data = await sbClient.rpc('drive_change_probe');
        final row = (data as List<dynamic>).first as Map<String, dynamic>;

        return DriveChangeProbe(
          maxUpdatedAt: row['max_updated_at']?.toString(),
          itemCount: (row['item_count'] as num?)?.toInt(),
        );
      } on PostgrestException catch (e) {
        if (!_isMissingProbeFunction(e)) rethrow;

        AnsiLogger.error(
          'drive_change_probe unavailable, falling back to the view probe',
          tag: 'DriveRepository',
        );

        final maxUpdatedAt = await fetchMaxTimestamp(
          table: 'v_drive_dashboard',
          field: 'updated_at',
        );
        final itemCount = await sbClient.from('v_drive_dashboard').count();

        return DriveChangeProbe(
            maxUpdatedAt: maxUpdatedAt, itemCount: itemCount);
      }
    });
  }

  /// PostgREST answers a call to an unknown RPC with `PGRST202`
  /// ("Could not find the function …"); anything else is a real failure.
  static bool _isMissingProbeFunction(PostgrestException e) {
    final haystack = [e.code, e.message, e.details]
        .whereType<Object>()
        .map((part) => part.toString())
        .join(' ')
        .toLowerCase();

    return haystack.contains('pgrst202') ||
        haystack.contains('could not find the function') ||
        haystack.contains('drive_change_probe');
  }

  Future<ResultWrapper<String?>> getMediaDownloadUrl(String filename) async {
    return tryCall(() async {
      return _mediaService.getDownloadUrl(filename);
    });
  }

  Future<ResultWrapper<DriveItem>> uploadDriveItemToR2({
    required String filePath,
    required MediaType type,
    String? mimeType,
  }) async {
    return withCouple((uid, partnerId) async {
      final file = dart_io.File(filePath);
      final result = await _mediaService.uploadMedia(
        file: file,
        type: type,
        userId: uid,
        partnerId: partnerId,
        mimeType: mimeType,
      );

      if (result == null) throw Exception('Upload failed');

      unawaited(notifyPartnerOnce(
        notificationKey: 'driveItemAdded',
        params: {'partnerName': await StorageService.getUsername() ?? ''},
      ));

      return DriveItem.fromJson(result);
    });
  }

  Future<ResultWrapper<void>> deleteDriveItem(int id) async {
    final api = ApiService();
    final result = await api.deleteMediaItem(id);

    return switch (result) {
      Success() => const Success(null),
      GenericError(:final message, :final code, :final details) =>
        _isAlreadyDeleted(details)
            ? const Success(null)
            : GenericError(message: message, code: code, details: details),
      NetworkError(:final message) => NetworkError(message: message),
    };
  }

  bool _isAlreadyDeleted(dynamic details) =>
      details is AppError && details.code == ErrorCodes.dbNotFound001;

  Future<ResultWrapper<void>> toggleFavorite(
      int driveItemId, bool isFavorite) async {
    return withUser((uid) async {
      if (isFavorite) {
        await sbClient.from('favorites').insert({
          'user_id': uid,
          'item_id': driveItemId,
        });
      } else {
        await sbClient
            .from('favorites')
            .delete()
            .match({'user_id': uid, 'item_id': driveItemId});
      }
    });
  }

  Future<ResultWrapper<DriveItemReactionsListResponse>> fetchReactions(
      int driveItemId) async {
    return tryCall(() async {
      final data = await sbClient
          .from('drive_item_reactions')
          .select('id, created_at, emojis(emoji_char)')
          .eq('item_id', driveItemId)
          .toList();

      final reactions = data.map((r) => DriveItemReaction.fromJson(r)).toList();

      return DriveItemReactionsListResponse(
          success: true, reactions: reactions);
    });
  }

  Future<ResultWrapper<void>> addReaction(
      int driveItemId, String emojiChar) async {
    final uid = await getUserId();
    if (uid == null) {
      return const GenericError(message: 'User not logged in');
    }

    return tryCall(() async {
      final emojiId = await sbClient.rpc('get_or_create_emoji', params: {
        'p_emoji_char': emojiChar,
      });

      await sbClient.from('drive_item_reactions').insert({
        'item_id': driveItemId,
        'user_id': uid,
        'emoji_id': emojiId,
      });

      unawaited(notifyPartnerOnce(
        notificationKey: 'reactionAdded',
        params: {
          'partnerName': await StorageService.getUsername() ?? '',
          'emojiChar': emojiChar,
        },
      ));
    });
  }

}
