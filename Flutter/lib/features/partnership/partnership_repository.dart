import 'dart:async';

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
    final result = await _api.requestPartnership({
      'email': email.trim(),
      'partnershipCode': partnershipCode.trim(),
    });
    return result.map((_) {});
  }

  Future<ResultWrapper<void>> acceptPartnerRequest(int partnershipId) async {
    BaseRepository.clearPartnershipCache();
    return tryCall(() async {
      await sbClient.rpc('accept_partnership', params: {
        'p_partnership_id': partnershipId,
      });

      unawaited(notifyPartnerOnce(
        notificationKey: 'requestAccepted',
        params: {'partnerName': await StorageService.getUsername() ?? ''},
      ));
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

  Future<ResultWrapper<List<PartnershipInvitation>>>
      getPendingInvitations() async {
    return tryCall(() async {
      final data = await sbClient.rpc('get_pending_invitations');
      final rows = (data as List<dynamic>).cast<Map<String, dynamic>>();

      return rows.map(PartnershipInvitation.fromJson).toList();
    });
  }
}
