// =============================================================================
// PartnerState - Partner management screen state
// =============================================================================

import 'package:justus/all_imports.dart';

class PartnerState extends BaseState {
  PartnerState({PartnershipRepository? repository})
      : _repo = repository ?? PartnershipRepository();

  final PartnershipRepository _repo;

  PartnershipResponse? _partnershipInfo;
  PartnershipCancellation? _cancellation;
  int _generation = 0;

  PartnershipResponse? get partnershipInfo => _partnershipInfo;
  PartnershipCancellation? get cancellation => _cancellation;

  User? get partner => _partnershipInfo?.partner;

  void clear() {
    _generation++;
    _partnershipInfo = null;
    _cancellation = null;
    notifyListeners();
  }

  Future<void> fetchPartnership() async {
    if (!await hasActiveSession()) return;
    final generation = _generation;
    await runSafe(() async {
      final hadCancellation = _cancellation != null;
      final result = await _repo.getPartnership();
      if (generation != _generation || !await hasActiveSession()) return;
      await handleResult(result, onSuccess: _applyPartnership);
      if (result is! Success<PartnershipResponse>) return;
      await fetchCancellation();
      if (generation != _generation || !await hasActiveSession()) return;
      _teleportIfEnded(hadCancellation);
    });
  }

  Future<void> refreshFromRealtime() async {
    if (!await hasActiveSession()) return;
    final generation = _generation;
    await runSafe(() async {
      final hadCancellation = _cancellation != null;
      final result = await _repo.getPartnership();
      if (generation != _generation || !await hasActiveSession()) return;
      await handleResult(result, onSuccess: _applyPartnership);
      if (result is! Success<PartnershipResponse>) return;
      await fetchCancellation(showLoading: false);
      if (generation != _generation || !await hasActiveSession()) return;
      _teleportIfEnded(hadCancellation);
    }, showLoading: false);
  }

  Future<void> fetchCancellation({bool showLoading = true}) async {
    if (!await hasActiveSession()) return;
    final generation = _generation;
    await runSafe(() async {
      final result = await _repo.getCancellation();
      if (generation != _generation || !await hasActiveSession()) return;
      await handleResult(result, onSuccess: (value) async {
        _cancellation = value;
      });
    }, showLoading: showLoading);
  }

  Future<ResultWrapper<void>> requestCancellation(int partnershipId) async {
    PartnershipRepository.clearPartnershipCache();
    final result = await _repo.requestCancellation(partnershipId);
    if (result is Success<void>) {
      await fetchPartnership();
    }
    return result;
  }

  Future<ResultWrapper<void>> revertCancellation(int partnershipId) async {
    PartnershipRepository.clearPartnershipCache();
    final result = await _repo.revertCancellation(partnershipId);
    if (result is Success<void>) {
      await fetchPartnership();
    }
    return result;
  }

  Future<ResultWrapper<Map<String, dynamic>>> acceptCancellation(
      int partnershipId) async {
    PartnershipRepository.clearPartnershipCache();
    final result = await _repo.acceptCancellation(partnershipId);
    if (result is Success<Map<String, dynamic>>) {
      await fetchPartnership();
      return result;
    }
    // Lost response reconciliation: the request is gone only when the
    // partnership row is gone too (an expired request reverts to accepted).
    await fetchCancellation(showLoading: false);
    await fetchPartnership();
    if (_cancellation == null && _partnershipInfo?.partner == null) {
      return const Success<Map<String, dynamic>>(<String, dynamic>{'ended': true});
    }
    return result;
  }

  Future<void> _applyPartnership(PartnershipResponse value) async {
    _partnershipInfo = value;
    if (value.partner != null) {
      await StorageService.savePartner(
        value.partner!.id,
        value.partner!.username,
      );
    } else {
      await StorageService.clearPartner();
    }
    if (value.partnershipId != null) {
      await StorageService.savePartnershipId(value.partnershipId!);
    }
  }

  /// A cancellation that was known and is now gone with no accepted partner
  /// means the partner accepted: leave any pushed route for PartnerScreen.
  void _teleportIfEnded(bool hadCancellation) {
    if (!hadCancellation ||
        _cancellation != null ||
        _partnershipInfo?.partner != null) {
      return;
    }
    final nav = ErrorHandler.navigatorKey.currentState;
    if (nav != null && nav.mounted) {
      nav.pushNamedAndRemoveUntil(AppRoutes.partner, (route) => false);
    }
  }
}
