// =============================================================================
// PartnerState - Partner management screen state
// =============================================================================

import 'package:justus/all_imports.dart';

class PartnerState extends BaseState {
  PartnerState({PartnershipRepository? repository})
      : _repo = repository ?? PartnershipRepository();

  final PartnershipRepository _repo;

  PartnershipResponse? _partnershipInfo;

  PartnershipResponse? get partnershipInfo => _partnershipInfo;

  User? get partner => _partnershipInfo?.partner;
  List<User> get receivedRequests =>
      _partnershipInfo?.pendingRequests?.received ?? [];
  List<User> get sentRequests => _partnershipInfo?.pendingRequests?.sent ?? [];

  Future<void> fetchPartnership() async {
    await runSafe(() async {
      final result = await _repo.getPartnership();

      await handleResult(result, onSuccess: _applyPartnership);
    });
  }

  Future<void> refreshFromRealtime() async {
    await runSafe(() async {
      final result = await _repo.getPartnership();

      await handleResult(result, onSuccess: _applyPartnership);
    }, showLoading: false);
  }

  Future<void> _applyPartnership(PartnershipResponse value) async {
    _partnershipInfo = value;
    if (value.partner != null) {
      await StorageService.savePartner(
        value.partner!.id,
        value.partner!.username,
      );
    }
    if (value.partnershipId != null) {
      await StorageService.savePartnershipId(value.partnershipId!);
    }
  }

  /// Sends a partnership request via email and code (maps to request_partnership RPC).
  Future<void> sendPartnerRequest(String email, String partnershipCode) async {
    await runSafe(() async {
      final result = await _repo.sendPartnerRequest(email, partnershipCode);

      await handleResult(result, onSuccess: (_) async {
        await fetchPartnership();
        setMessage('Richiesta inviata a $email');
      });
    });
  }

  /// Accepts a pending partnership by its ID (maps to accept_partnership RPC).
  Future<void> acceptPartner(int partnershipId) async {
    await runSafe(() async {
      final result = await _repo.acceptPartnerRequest(partnershipId);

      await handleResult(result, onSuccess: (_) async {
        setMessage('Richiesta accettata');
        await fetchPartnership();
        // Update local partner cache
        if (_partnershipInfo?.partner != null) {
          await StorageService.savePartner(
            _partnershipInfo!.partner!.id,
            _partnershipInfo!.partner!.username,
          );
        }
      });
    });
  }

  /// Rejects a pending partnership by its ID (deletes the row).
  Future<void> rejectPartner(int partnershipId) async {
    await runSafe(() async {
      final result = await _repo.rejectPartnerRequest(partnershipId);

      await handleResult(result, onSuccess: (_) {
        // Remove from pending list optimistically
        if (_partnershipInfo != null) {
          _partnershipInfo = _partnershipInfo!.copyWith(
            pendingRequests: _partnershipInfo!.pendingRequests?.copyWith(
              received:
                  receivedRequests.where((u) => u.id != partnershipId).toList(),
            ),
          );
        }
        setMessage('Richiesta rifiutata');
      });
    });
  }
}
