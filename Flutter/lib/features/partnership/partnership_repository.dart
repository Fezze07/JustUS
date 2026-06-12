import 'package:justus/all_imports.dart';

class PartnershipRepository extends BaseRepository {
  final ApiService _api;

  // Cache for the active partnership to avoid duplicate parallel DB calls
  static Future<Map<String, dynamic>?>? _activePartnershipFuture;
  static int? _activePartnershipUserId;

  static void clearPartnershipCache() {
    _activePartnershipFuture = null;
    _activePartnershipUserId = null;
  }

  @override
  Future<Map<String, dynamic>?> getActivePartnership() async {
    if (_activePartnershipFuture != null) {
      return _activePartnershipFuture;
    }

    final future = () async {
      try {
        final currentUid = await getUserId();
        // If the user changed (both non-null and different), invalidate and fetch again
        if (_activePartnershipUserId != null &&
            currentUid != null &&
            _activePartnershipUserId != currentUid) {
          clearPartnershipCache();
          _activePartnershipUserId = currentUid;
          return await getActivePartnership();
        }
        _activePartnershipUserId = currentUid;

        return await sbClient
            .from('v_active_partnership')
            .select()
            .maybeSingle();
      } catch (e) {
        _activePartnershipFuture = null;
        rethrow;
      }
    }();

    _activePartnershipFuture = future;
    return future;
  }

  PartnershipRepository({super.sbClient, ApiService? api})
      : _api = api ?? ApiService();


  Future<ResultWrapper<Map<String, dynamic>>> inviteUser(
      String email, String partnershipCode) async {
    return _api.inviteUser({
      'email': email,
      'partnershipCode': partnershipCode,
    });
  }

  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    return tryCall(() async {
      final data = await getActivePartnership();

      if (data == null) {
        return PartnershipResponse(success: true);
      }

      return PartnershipResponse.fromJson(data);
    });
  }

  Future<ResultWrapper<User>> fetchPartnerProfile() async {
    final result = await getPartnership();
    if (result is! Success<PartnershipResponse>) {
      return const GenericError(message: 'Nessun partner');
    }
    final partner = result.value.partner;
    if (partner == null) return const GenericError(message: 'Nessun partner');

    return Success(partner);
  }

  Future<ResultWrapper<void>> sendPartnerRequest(
      String email, String partnershipCode) async {
    BaseRepository.clearPartnershipCache();
    return tryCall(() async {
      await sbClient.rpc('request_partnership', params: {
        'partner_email': email.trim(),
        'partner_code': partnershipCode.trim(),
      });
    });
  }

  Future<ResultWrapper<void>> acceptPartnerRequest(int partnershipId) async {
    BaseRepository.clearPartnershipCache();
    return tryCall(() async {
      await sbClient.rpc('accept_partnership', params: {
        'p_partnership_id': partnershipId,
      });
    });
  }

  Future<ResultWrapper<void>> rejectPartnerRequest(int partnershipId) async {
    BaseRepository.clearPartnershipCache();
    return tryCall(() async {
      await sbClient
          .from('partnerships')
          .delete()
          .eq('id', partnershipId)
          .eq('status', 'pending');
    });
  }

  Future<ResultWrapper<void>> updateAnniversaryDate(DateTime date) async {
    BaseRepository.clearPartnershipCache();
    final partnershipResult = await getPartnership();
    if (partnershipResult is! Success<PartnershipResponse>) {
      return const GenericError(message: 'No active partnership');
    }
    final partnershipId = partnershipResult.value.partnershipId;
    if (partnershipId == null) {
      return const GenericError(message: 'Partnership ID not found');
    }

    return tryCall(() async {
      final dateStr = AppDateUtils.formatToYMD(date);
      await sbClient
          .from('partnerships')
          .update({'anniversary_date': dateStr}).eq('id', partnershipId);
    });
  }

  Future<ResultWrapper<List<User>>> searchPartner(String? query) async {
    return tryCall(() async {
      var q = sbClient
          .from('users')
          .select('id, email, user_profiles(display_name, profile_pic_url)');
      if (query != null && query.isNotEmpty) {
        q = q.or('email.ilike.%$query%');
      }
      final List<dynamic> data = await q.limit(20);

      return data.map((u) => User.fromJson(u as Map<String, dynamic>)).toList();
    });
  }

  Future<ResultWrapper<List<PartnershipInvitation>>>
      getPendingInvitations() async {
    return withUser((uid) async {
      final List<dynamic> data = await sbClient
          .from('partnerships')
          .select(
              '*, user_id_1(id, email, user_profiles(display_name, profile_pic_url)), user_id_2(id, email, user_profiles(display_name, profile_pic_url))')
          .eq('status', 'pending')
          .or('user_id_1.eq.$uid,user_id_2.eq.$uid');

      return data.map((row) {
        final isReceived = row['user_id_2']['id'] == uid;
        final partnerData = isReceived ? row['user_id_1'] : row['user_id_2'];
        final profile = partnerData['user_profiles'] as Map<String, dynamic>?;

        return PartnershipInvitation(
          id: row['id'] as int,
          status: row['status'] as String? ?? 'pending',
          createdAt: AppDateUtils.tryParse(row['created_at'] as String?) ??
              DateTime.now(),
          partnerId: partnerData['id'] as int?,
          partnerDisplayName: profile?['display_name'] as String? ??
              (partnerData['email'] as String?)?.split('@').first,
          partnerEmail: partnerData['email'] as String?,
          isReceived: isReceived,
        );
      }).toList();
    });
  }
}
