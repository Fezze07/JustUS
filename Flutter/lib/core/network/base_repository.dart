import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'package:justus/all_imports.dart';

abstract class BaseRepository {
  final SupabaseClient? _sbClientOverride;

  BaseRepository({SupabaseClient? sbClient}) : _sbClientOverride = sbClient;

  SupabaseClient get sbClient => _sbClientOverride ?? SupabaseService().client;

  Future<int?> getUserId() async => await StorageService.getUserId();

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
}
