import 'dart:collection';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Shared identity, dedup, and row-decoding context for the Realtime layer.
///
/// Owns the user/partner/partnership ids (mutated by
/// [RealtimeSyncService.configure]) and the 80-entry FIFO LRU that absorbs
/// Supabase event replays after a resubscribe. Feature handlers read these
/// ids and reuse the static row helpers instead of re-implementing payload
/// decoding.
class RealtimeSyncSession {
  int? userId;
  int? partnerId;
  int? partnershipId;
  bool suppressProcessing = false;

  final Queue<String> _recentEventKeys = Queue<String>();
  final Set<String> _recentEventKeySet = <String>{};

  /// Returns `true` if [payload] is new, recording its dedup key. Replayed
  /// events (same table + event type + row id + commit timestamp) are dropped.
  bool markSeen(sb.PostgresChangePayload payload) {
    final row = currentRecord(payload);
    final id = row['id'] ?? row['partnership_id'] ?? row['user_id'] ?? '';
    final key = [
      payload.table,
      payload.eventType.name,
      id,
      payload.commitTimestamp.toUtc().toIso8601String(),
    ].join(':');

    if (_recentEventKeySet.contains(key)) {
      AnsiLogger.realtime('_markSeen - DUPLICATE key=$key');
      return false;
    }

    AnsiLogger.realtime('_markSeen - NEW event key=$key');
    _recentEventKeys.addLast(key);
    _recentEventKeySet.add(key);
    const maxTrackedEvents = 80;
    while (_recentEventKeys.length > maxTrackedEvents) {
      _recentEventKeySet.remove(_recentEventKeys.removeFirst());
    }

    return true;
  }

  /// The post-write row if present, else the pre-write row.
  Map<String, dynamic> currentRecord(sb.PostgresChangePayload payload) {
    if (payload.newRecord.isNotEmpty) return payload.newRecord;

    return payload.oldRecord;
  }

  int? rowUserId(Map<String, dynamic> row, String key) {
    return rowInt(row, key);
  }

  int? rowInt(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);

    return null;
  }

  bool isRelevantUserProfile(sb.PostgresChangePayload payload) {
    final profileUserId = rowInt(currentRecord(payload), 'user_id');
    if (profileUserId == null) return false;

    return profileUserId == userId || profileUserId == partnerId;
  }

  bool isRelevantMood(sb.PostgresChangePayload payload) {
    final changedUserId = rowUserId(currentRecord(payload), 'user_id');
    if (changedUserId == null) return false;

    return changedUserId == userId || changedUserId == partnerId;
  }

  bool isRelevantPartnership(sb.PostgresChangePayload payload) {
    final row = currentRecord(payload);
    final ids = <int?>[
      rowInt(row, 'user_id_1'),
      rowInt(row, 'user_id_2'),
      rowInt(row, 'user_id_a'),
      rowInt(row, 'user_id_b'),
    ];

    return ids.any((id) => id != null && id == userId);
  }

  bool isRelevantMissYou(sb.PostgresChangePayload payload) {
    return isPartnershipRecord(payload);
  }

  bool isPartnershipRecord(sb.PostgresChangePayload payload) {
    final partnershipId = this.partnershipId;
    if (partnershipId == null) return true;

    final eventPartnershipId = rowInt(currentRecord(payload), 'partnership_id');

    return eventPartnershipId == null || eventPartnershipId == partnershipId;
  }

  bool isRelevantGame(sb.PostgresChangePayload payload) {
    final row = currentRecord(payload);
    if (payload.table == 'game_questions') {
      return isPartnershipRecord(payload);
    }

    final rowUserId = rowInt(row, 'user_id');
    if (rowUserId == null) return partnershipId != null;

    return rowUserId == userId || rowUserId == partnerId;
  }

  bool isRelevantDrive(sb.PostgresChangePayload payload,
      {required List<DriveItem> driveItems}) {
    if (payload.table == 'drive_items') {
      return isPartnershipRecord(payload);
    }

    final itemId = rowInt(currentRecord(payload), 'item_id');
    if (itemId == null) return partnershipId != null;

    return driveItems.any((item) => item.id == itemId);
  }
}
