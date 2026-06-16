import 'dart:async';
import 'dart:io' as dart_io;

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

  Future<bool> hasNewDriveItems() {
    return hasChanges(
      table: 'v_drive_dashboard',
      field: 'updated_at',
      cacheKey: CacheService.kDriveItems,
    );
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
    return tryCall(() async {
      await sbClient.from('drive_items').delete().eq('id', id);
    });
  }

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
