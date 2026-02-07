// =============================================================================
// LoginState - Login screen state management
// Dart equivalent of LoginViewModel.kt
// =============================================================================

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../repositories/api_repository.dart';
import '../services/result_wrapper.dart';
import '../services/storage_service.dart';

enum LoginStatus { idle, loading, success, error }

sealed class LoginEvent {}

class SuccessLogin extends LoginEvent {
  final String username;
  SuccessLogin(this.username);
}

class ShowMessage extends LoginEvent {
  final String message;
  ShowMessage(this.message);
}

class SingleCodeFound extends LoginEvent {
  final String code;
  SingleCodeFound(this.code);
}

class MultipleCodesFound extends LoginEvent {
  final List<String> codes;
  MultipleCodesFound(this.codes);
}

class LoginState extends ChangeNotifier {
  final ApiRepository _repo = ApiRepository();

  LoginStatus _status = LoginStatus.idle;
  LoginEvent? _lastEvent;

  LoginStatus get status => _status;
  LoginEvent? get lastEvent => _lastEvent;

  void clearEvent() {
    _lastEvent = null;
  }

  Future<void> login(
      String usernameWithCode, String password, String deviceToken) async {
    if (usernameWithCode.trim().isEmpty || password.trim().isEmpty) {
      _emitMessage('Compila tutti i campi');
      return;
    }
    _status = LoginStatus.loading;
    notifyListeners();
    final result =
        await _repo.loginUser(usernameWithCode, password, deviceToken);
    switch (result) {
      case Success(:final value):
        await _handleLoginSuccess(value);
      case GenericError(:final code, :final message):
        final msg = switch (code) {
          400 => 'Credenziali mancanti o formato errato',
          401 => 'Password errata o utente non trovato',
          403 => 'Account temporaneamente bloccato',
          _ => 'Errore server ($code)',
        };
        _emitMessage(msg);
      case NetworkError():
        _emitMessage('Connessione assente');
    }
  }

  Future<void> requestCodes(String username, String password) async {
    if (username.trim().isEmpty || password.trim().isEmpty) {
      _emitMessage('Compila tutti i campi');
      return;
    }

    _status = LoginStatus.loading;
    notifyListeners();

    final result = await _repo.requestUserCodes(username, password);

    switch (result) {
      case Success(:final value):
        _handleCodesSuccess(value.codes ?? []);
      case GenericError(:final code):
        final msg = switch (code) {
          400 => 'Compila tutti i campi',
          404 => 'Utente non trovato',
          401 => 'Password errata',
          _ => 'Errore server ($code)',
        };
        _emitMessage(msg);
      case NetworkError():
        _emitMessage('Connessione assente');
    }
  }

  Future<void> _handleLoginSuccess(LoginResponse body) async {
    if (body.token != null) {
      await StorageService.saveToken(body.token!);
    }
    if (body.user != null) {
      await StorageService.saveUsername(body.user!.username);
      await StorageService.saveUserCode(body.user!.code);
    }

    if (body.token != null && body.user?.code.isNotEmpty == true) {
      _status = LoginStatus.success;
      _lastEvent = SuccessLogin(body.user!.username);
      notifyListeners();
    } else {
      _emitMessage(body.error ?? 'Errore login');
    }
  }

  void _handleCodesSuccess(List<String> codes) {
    _status = LoginStatus.idle;
    if (codes.isEmpty) {
      _lastEvent = ShowMessage('Codice utente non trovato');
    } else if (codes.length == 1) {
      _lastEvent = SingleCodeFound(codes.first);
    } else {
      _lastEvent = MultipleCodesFound(codes);
    }
    notifyListeners();
  }

  void _emitMessage(String msg) {
    _status = LoginStatus.error;
    _lastEvent = ShowMessage(msg);
    notifyListeners();
  }
}
