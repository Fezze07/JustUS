// =============================================================================
// BaseState - Common state management logic for JustUS
// =============================================================================

import 'dart:async';
import 'package:justus/all_imports.dart';

import 'package:flutter/widgets.dart';

abstract class BaseState extends ChangeNotifier {
  bool _isLoading = false;
  String? _message;
  bool _pendingNotify = false;

  bool get isLoading => _isLoading;
  String? get message => _message;

  /// Coalesces this state's notifications into one delivery at the end of the
  /// next frame, and requests that frame so an idle UI still receives it.
  @override
  void notifyListeners() {
    if (_pendingNotify) return;
    _pendingNotify = true;
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingNotify = false;
      if (hasListeners) super.notifyListeners();
    });
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

  Future<void> loadWithChangeDetection({
    required Future<void> Function() loadFromCache,
    required Future<bool> Function() hasChanges,
    required Future<void> Function() fetchFromNetwork,
  }) async {
    await loadFromCache();
    bool changed = true;
    try {
      changed = await hasChanges();
    } catch (e, st) {
      ErrorHandler.handle(e, stackTrace: st);
      changed = true;
    }

    if (changed) {
      unawaited(fetchFromNetwork().catchError((Object e, StackTrace st) {
        ErrorHandler.handle(e, stackTrace: st);
      }));
    }
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
        _message = null;
        ErrorHandler.handle(result);
        notifyListeners();
      case NetworkError<T>():
        _message = null;
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

/// Shows a [BaseState.message] as a snackbar and clears it — the behaviour
/// `GameScreen` applies to `GameState`, shared by every screen that owns a
/// state with messages.
///
/// The state is resolved once, after the first frame, and cached: calling
/// `context.read` from `dispose()` throws because the element is deactivated.
///
/// Usage: `with StateMessageListener<ProfileState, ProfileScreen>` and override
/// [messageSource] with the provider read, e.g. `context.read<ProfileState>()`.
mixin StateMessageListener<T extends BaseState, W extends StatefulWidget>
    on State<W> {
  T get messageSource;

  T? _messageSource;

  void _handleStateMessage() {
    final state = _messageSource;
    if (state == null) return;
    final msg = state.message;
    if (msg != null && msg.isNotEmpty && mounted) {
      ErrorHandler.showSnackBar(context, msg);
      state.clearMessage();
    }
  }

  /// Shows and clears the message currently held by [messageSource].
  ///
  /// `setMessage` delivers on the next frame, so a screen that pops right after
  /// an action (e.g. after a delete) must call this before the pop — otherwise
  /// the listener is disposed first and the message is lost.
  void showPendingMessage() => _handleStateMessage();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messageSource = messageSource;
      _messageSource!.addListener(_handleStateMessage);
    });
  }

  @override
  void dispose() {
    _messageSource?.removeListener(_handleStateMessage);
    super.dispose();
  }
}
