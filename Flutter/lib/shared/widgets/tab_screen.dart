import 'dart:async';

import 'package:flutter/widgets.dart';

/// Base widget for tab screens that need to react to activation.
abstract class TabScreen extends StatefulWidget {
  final bool isActive;
  const TabScreen({super.key, this.isActive = false});
}

/// Mixin that handles activation-based data loading for tab screens.
///
/// Call [handleScreenActivation] at the top of [build].
/// Override [loadData] to perform the actual data fetch.
/// Use [loadData(force: true)] from pull-to-refresh to bypass change detection.
mixin TabScreenMixin {
  bool _dataLoadedOnce = false;
  bool _lastKnownIsActive = false;

  /// Must return `widget.isActive`.
  bool get activeForTab;

  @protected
  void handleScreenActivation() {
    final isActive = activeForTab;
    if (isActive && !_lastKnownIsActive) {
      _dataLoadedOnce = false;
    }
    _lastKnownIsActive = isActive;

    if (isActive && !_dataLoadedOnce) {
      _dataLoadedOnce = true;
      unawaited(loadData());
    }
  }

  /// Override to load data when this screen becomes active.
  ///
  /// Use [force] to bypass change detection (e.g., pull-to-refresh).
  Future<void> loadData({bool force = false});
}
