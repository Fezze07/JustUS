// =============================================================================
// PartnerState - Partner management screen state
// Dart equivalent of PartnerViewModel.kt
// =============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../repositories/api_repository.dart';
import '../services/result_wrapper.dart';
import '../services/storage_service.dart';

class PartnerState extends ChangeNotifier {
  final ApiRepository _repo = ApiRepository();

  String _usernameQuery = '';
  String _codeQuery = '';
  List<User> _suggestedUsers = [];
  PartnershipResponse? _partnershipInfo;
  String? _message;
  bool _isLoading = false;

  Timer? _debounceTimer;

  String get usernameQuery => _usernameQuery;
  String get codeQuery => _codeQuery;
  List<User> get suggestedUsers => _suggestedUsers;
  PartnershipResponse? get partnershipInfo => _partnershipInfo;
  String? get message => _message;
  bool get isLoading => _isLoading;

  User? get partner => _partnershipInfo?.partner;
  List<User> get receivedRequests => 
      _partnershipInfo?.pendingRequests?.received ?? [];
  List<User> get sentRequests => 
      _partnershipInfo?.pendingRequests?.sent ?? [];

  void clearMessage() {
    _message = null;
  }

  void setUsernameQuery(String value) {
    _usernameQuery = value;
    _debouncedSearch();
  }

  void setCodeQuery(String value) {
    _codeQuery = value;
    _debouncedSearch();
  }

  void _debouncedSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _fetchSuggestions();
    });
  }

  Future<void> _fetchSuggestions() async {
    if (_usernameQuery.isEmpty && _codeQuery.isEmpty) {
      _suggestedUsers = [];
      notifyListeners();
      return;
    }

    final result = await _repo.searchPartner(
      _usernameQuery.isNotEmpty ? _usernameQuery : null,
      _codeQuery.isNotEmpty ? _codeQuery : null,
    );

    switch (result) {
      case Success(:final value):
        _suggestedUsers = value;
      case GenericError():
        _message = 'Errore server';
      case NetworkError():
        _message = 'Errore rete';
    }
    notifyListeners();
  }

  Future<void> fetchPartnership() async {
    _isLoading = true;
    notifyListeners();

    final result = await _repo.getPartnership();

    switch (result) {
      case Success(:final value):
        _partnershipInfo = value;
        if (value.partner != null) {
          await StorageService.savePartner(
            value.partner!.id,
            value.partner!.username,
          );
        }
      case GenericError():
        _message = 'Errore server';
      case NetworkError():
        _message = 'Errore rete';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> sendPartnerRequest(String username, String code) async {
    _isLoading = true;
    notifyListeners();

    final result = await _repo.sendPartnerRequest(username, code);

    switch (result) {
      case Success():
        _message = 'Richiesta inviata a $username';
        await fetchPartnership();
      case GenericError():
        _message = 'Errore server';
      case NetworkError():
        _message = 'Errore rete';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> acceptPartner(int requesterId) async {
    _isLoading = true;
    notifyListeners();

    final result = await _repo.acceptPartnerRequest(requesterId);

    switch (result) {
      case Success():
        _message = 'Richiesta accettata';
        
        // Find the requester and save as partner
        final requester = receivedRequests.firstWhere(
          (u) => u.id == requesterId,
          orElse: () => User(id: requesterId, username: '', code: ''),
        );
        await StorageService.savePartner(requesterId, requester.username);
        
        await fetchPartnership();
      case GenericError():
        _message = 'Errore server';
      case NetworkError():
        _message = 'Errore rete';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> rejectPartner(int requesterId) async {
    final result = await _repo.rejectPartnerRequest(requesterId);

    switch (result) {
      case Success():
        // Update local state
        if (_partnershipInfo != null) {
          _partnershipInfo = _partnershipInfo!.copyWith(
            pendingRequests: _partnershipInfo!.pendingRequests?.copyWith(
              received: receivedRequests
                  .where((u) => u.id != requesterId)
                  .toList(),
            ),
          );
        }
        _message = 'Richiesta rifiutata';
      case GenericError():
        _message = 'Errore server';
      case NetworkError():
        _message = 'Errore rete';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
