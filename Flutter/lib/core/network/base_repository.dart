import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'package:justus/all_imports.dart';

abstract class BaseRepository {
  final SupabaseClient? _sbClientOverride;

  BaseRepository({SupabaseClient? sbClient}) : _sbClientOverride = sbClient;

  SupabaseClient get sbClient => _sbClientOverride ?? SupabaseService().client;

  Future<int?> getUserId() async => await StorageService.getUserId();

  static final Map<String, Future<String?>> _pendingTimestampFetches = {};

  static String _timestampCacheKey({
    required String table,
    required String field,
    String? filterColumn,
    List<Object> filterValues = const [],
  }) {
    return '$table|$field|$filterColumn|${filterValues.join(",")}';
  }

  Future<String?> fetchMaxTimestamp({
    required String table,
    required String field,
    String? filterColumn,
    List<Object> filterValues = const [],
  }) async {
    final key = _timestampCacheKey(
      table: table,
      field: field,
      filterColumn: filterColumn,
      filterValues: filterValues,
    );

    if (_pendingTimestampFetches.containsKey(key)) {
      return _pendingTimestampFetches[key];
    }

    final future = _doFetchMaxTimestamp(
      table: table,
      field: field,
      filterColumn: filterColumn,
      filterValues: filterValues,
    );
    _pendingTimestampFetches[key] = future;

    try {
      return await future;
    } finally {
      unawaited(_pendingTimestampFetches.remove(key));
    }
  }

  Future<String?> _doFetchMaxTimestamp({
    required String table,
    required String field,
    String? filterColumn,
    List<Object> filterValues = const [],
  }) async {
    dynamic query = sbClient.from(table).select(field);

    if (filterColumn != null && filterValues.isNotEmpty) {
      query = query.inFilter(filterColumn, filterValues);
    }

    final data = await query
        .order(field, ascending: false)
        .limit(1)
        .maybeSingle();

    return data?[field]?.toString();
  }

  Future<bool> hasChanges({
    required String table,
    required String field,
    String? filterColumn,
    List<Object> filterValues = const [],
    required String cacheKey,
  }) async {
    final checkpoint = await CacheService.getCheckpoint(cacheKey);
    if (checkpoint == null) return true;

    final serverMax = await fetchMaxTimestamp(
      table: table,
      field: field,
      filterColumn: filterColumn,
      filterValues: filterValues,
    );
    if (serverMax == null) {
      // No rows on server — if the checkpoint says we had data before, it was deleted
      return checkpoint != CacheService.kCheckpointEmpty;
    }

    final serverDate = DateTime.tryParse(serverMax);
    final checkpointDate = checkpoint == CacheService.kCheckpointEmpty
        ? null
        : DateTime.tryParse(checkpoint);

    if (serverDate == null || checkpointDate == null) return true;

    return serverDate.isAfter(checkpointDate);
  }

  Future<ResultWrapper<T>> tryCall<T>(Future<T> Function() fn) async {
    try {
      return Success(await fn());
    } catch (e) {
      return GenericError(message: e.toString());
    }
  }

  static void clearPartnershipCache() {
    PartnershipRepository.clearPartnershipCache();
  }

  Future<Map<String, dynamic>?> getActivePartnership() async {
    return await PartnershipRepository(sbClient: sbClient)
        .getActivePartnership();
  }

  Future<ResultWrapper<T>> withUser<T>(
    Future<T> Function(int uid) action,
  ) async {
    final uid = await getUserId();
    if (uid == null) return const GenericError(message: 'User not logged in');

    return tryCall(() => action(uid));
  }

  Future<ResultWrapper<T>> withPartnership<T>(
    Future<T> Function(int partnershipId) action,
  ) async {
    return tryCall(() async {
      final partnershipData = await getActivePartnership();
      final partnershipId = partnershipData?['partnership_id'] as int?;
      if (partnershipId == null) throw Exception('No active partnership');

      return await action(partnershipId);
    });
  }

  Future<ResultWrapper<T>> withCouple<T>(
    Future<T> Function(int uid, int? partnerId) action,
  ) async {
    return withUser((uid) async {
      final partnershipData = await getActivePartnership();
      final partnerId = partnershipData?['partner_id'] as int?;

      return await action(uid, partnerId);
    });
  }

  /// Fire-and-forget notification to partner via backend FCM.
  /// Sends [notificationKey] and [params] so the receiver's device localizes
  /// the notification into its own language.
  /// Creates a transient [ApiService] — safe for infrequent calls.
  Future<void> notifyPartnerOnce({
    required String notificationKey,
    Map<String, String> params = const {},
  }) async {
    final api = ApiService();
    try {
      await api.notifyPartner(notificationKey: notificationKey, params: params);
    } catch (_) {}
  }
}
