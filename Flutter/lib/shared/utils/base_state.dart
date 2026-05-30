// =============================================================================
// BaseState - Common state management logic for JustUS
// =============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:justus/all_imports.dart';

abstract class BaseState extends ChangeNotifier {
  bool _isLoading = false;
  String? _message;

  bool get isLoading => _isLoading;
  String? get message => _message;

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void setMessage(String? value) {
    _message = value;
    notifyListeners();
  }

  void clearMessage() {
    _message = null;
    notifyListeners();
  }

  /// Centralized handling of Result patterns to reduce duplication across states.
  Future<void> handleResult<T>(ResultWrapper<T> result,
      {FutureOr<void> Function(T value)? onSuccess,
      bool notifyOnSuccess = false}) async {
    switch (result) {
      case Success<T>(:final value):
        if (onSuccess != null) await onSuccess(value);
        if (notifyOnSuccess) notifyListeners();
      case GenericError<T>():
        ErrorHandler.handle(result);
        notifyListeners();
      case NetworkError<T>():
        ErrorHandler.handle(AppError.network());
        notifyListeners();
    }
  }

  /// Runs an async action safely with automatic loading state and error handling.
  Future<bool> runSafe(Future<void> Function() action,
      {bool showLoading = true}) async {
    if (showLoading) setLoading(true);
    _message = null;
    try {
      await action();

      return true;
    } catch (e, st) {
      ErrorHandler.handle(e, stackTrace: st);

      return false;
    } finally {
      if (showLoading) {
        setLoading(false);
      } else {
        notifyListeners();
      }
    }
  }
}
