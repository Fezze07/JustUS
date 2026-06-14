import 'dart:async';

import 'package:flutter/widgets.dart';

/// Notifies tab screens when the active tab index changes.
class TabIndexNotifier extends ChangeNotifier {
  int _index = 0;
  int get index => _index;
  set index(int value) {
    if (_index != value) {
      _index = value;
      notifyListeners();
    }
  }
}

/// Base widget for tab screens that need to react to activation.
abstract class TabScreen extends StatefulWidget {
  final int tabIndex;
  final TabIndexNotifier tabNotifier;
  const TabScreen({
    super.key,
    required this.tabIndex,
    required this.tabNotifier,
  });
}

/// Mixin that handles activation-based data loading for tab screens.
///
/// Loads data on first visit and on every subsequent switch-back to this tab.
/// Override [loadData] to perform the actual data fetch.
/// Use [loadData(force: true)] from pull-to-refresh to bypass change detection.
mixin TabScreenMixin<T extends TabScreen> on State<T> {
  bool _dataLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    widget.tabNotifier.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoadData());
  }

  @override
  void dispose() {
    widget.tabNotifier.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.tabNotifier.index == widget.tabIndex) {
      _dataLoadedOnce = false;
      _tryLoadData();
    }
  }

  void _tryLoadData() {
    if (widget.tabNotifier.index == widget.tabIndex && !_dataLoadedOnce) {
      _dataLoadedOnce = true;
      unawaited(loadData());
    }
  }

  /// Override to load data when this screen becomes active.
  ///
  /// Use [force] to bypass change detection (e.g., pull-to-refresh).
  Future<void> loadData({bool force = false});
}
