// =============================================================================
// BaseState - Common state management logic for JustUS
// =============================================================================

import 'dart:async';
import 'package:justus/all_imports.dart';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

abstract class BaseState extends ChangeNotifier {
  bool _isLoading = false;
  String? _message;
  bool _pendingNotify = false;

  bool get isLoading => _isLoading;
  String? get message => _message;

  /// Safe notifyListeners — defers to the next frame if the framework is
  /// currently building / animating (locked widget tree).
  @override
  void notifyListeners() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    final locked = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;

    if (locked) {
      if (!_pendingNotify) {
        _pendingNotify = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pendingNotify = false;
          if (hasListeners) super.notifyListeners();
        });
      }
    } else {
      super.notifyListeners();
    }
  }


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
