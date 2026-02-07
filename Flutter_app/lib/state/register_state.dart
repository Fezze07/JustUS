// =============================================================================
// RegisterState - Registration screen state management
// Dart equivalent of RegisterViewModel.kt
// =============================================================================

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../repositories/api_repository.dart';
import '../services/result_wrapper.dart';


enum RegisterStatus { idle, loading, success, error }

class RegisterState extends ChangeNotifier {
  final ApiRepository _repo = ApiRepository();

  RegisterStatus _status = RegisterStatus.idle;
  String? _message;
  User? _registeredUser;

  RegisterStatus get status => _status;
  String? get message => _message;
  User? get registeredUser => _registeredUser;

  void clearMessage() {
    _message = null;
  }

  Future<void> register(String username, String password, String? email) async {
    if (username.trim().isEmpty || password.trim().isEmpty) {
      _setError('Compila tutti i campi obbligatori');
      return;
    }

    if (password.length < 6) {
      _setError('La password deve avere almeno 6 caratteri');
      return;
    }

    _status = RegisterStatus.loading;
    _message = null;
    notifyListeners();

    // Device token is empty since we're skipping notifications
    final result = await _repo.registerUser(
      username,
      password,
      email?.isNotEmpty == true ? email : null,
      '',
    );

    switch (result) {
      case Success(:final value):
        if (value.success && value.user != null) {
          _registeredUser = value.user;
          _status = RegisterStatus.success;
          _message = value.message ?? 'Registrazione completata!';
        } else {
          _setError(value.error ?? value.message ?? 'Errore registrazione');
        }
      case GenericError(:final code, :final message):
        _setError(message ?? 'Errore server ($code)');
      case NetworkError():
        _setError('Connessione assente');
    }
    notifyListeners();
  }

  void _setError(String msg) {
    _status = RegisterStatus.error;
    _message = msg;
  }

  void reset() {
    _status = RegisterStatus.idle;
    _message = null;
    _registeredUser = null;
    notifyListeners();
  }
}
