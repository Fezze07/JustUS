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
}
