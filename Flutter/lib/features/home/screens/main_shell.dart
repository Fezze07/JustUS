import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:justus/all_imports.dart';

class MainShellScope extends InheritedWidget {
  final MainShellState shellState;

  const MainShellScope({
    super.key,
    required this.shellState,
    required super.child,
  });

  static MainShellState? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MainShellScope>()?.shellState;
  }

  @override
  bool updateShouldNotify(MainShellScope oldWidget) => false;
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  static MainShellState? of(BuildContext context) => MainShellScope.of(context);

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final TabIndexNotifier _tabNotifier = TabIndexNotifier();
  final Set<int> _builtPages = {0};
  StreamSubscription<String?>? _notifSub;

  @override
  void initState() {
    super.initState();
    _notifSub = NotificationService().onNotificationTap.listen(_handleNotificationPayload);
    final pending = NotificationService().consumePendingPayload();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleNotificationPayload(pending));
    }
  }

  @override
  void dispose() {
    unawaited(_notifSub?.cancel());
    super.dispose();
  }

  void _handleNotificationPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      Map<String, dynamic> data = {};
      if (payload.startsWith('{')) {
        data = jsonDecode(payload) as Map<String, dynamic>;
      } else {
        data = {'notificationKey': payload};
      }

      final key = data['notificationKey'] as String? ??
          data['target'] as String? ??
          data['route'] as String?;
      final tabIndexRaw = data['tabIndex'];
      if (tabIndexRaw != null) {
        final idx = int.tryParse(tabIndexRaw.toString());
        if (idx != null && idx >= 0 && idx <= 6) {
          switchToTab(idx);
          return;
        }
      }

      if (key == null) return;
      switch (key) {
        case 'moodUpdated':
        case '/mood':
          switchToTab(2);
          break;
        case 'answerSubmitted':
        case 'newQuestion':
        case '/game':
          switchToTab(1);
          break;
        case 'bucketItemAdded':
        case '/bucket':
          switchToTab(3);
          break;
        case 'driveItemAdded':
        case 'reactionAdded':
        case '/drive':
          switchToTab(4);
          break;
        case 'missyou':
        case 'requestAccepted':
        case '/homepage':
          switchToTab(0);
          break;
      }
    } catch (e) {
      AnsiLogger.error('Error handling notification tap payload: $e', tag: 'MainShell');
    }
  }

  void switchToTab(int index) {
    _builtPages.add(index);
    _tabNotifier.index = index;
    setState(() => _currentIndex = index);
  }

  Widget _pageWidget(int index) {
    switch (index) {
      case 0: return HomepageScreen(tabIndex: 0, tabNotifier: _tabNotifier);
      case 1: return GameScreen(tabIndex: 1, tabNotifier: _tabNotifier);
      case 2: return MoodScreen(tabIndex: 2, tabNotifier: _tabNotifier);
      case 3: return BucketListScreen(tabIndex: 3, tabNotifier: _tabNotifier);
      case 4: return DriveScreen(tabIndex: 4, tabNotifier: _tabNotifier);
      case 5: return FavoritesScreen(tabIndex: 5, tabNotifier: _tabNotifier);
      case 6: return const ProfileScreen();
      default: return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPartner = context.select<AuthState, bool>((a) => a.hasPartner);
    if (!hasPartner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const PartnerScreen()),
          ));
        }
      });
    }

    return MainShellScope(
      shellState: this,
      child: Material(
        color: context.palette.canvas,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 110),
              child: IndexedStack(
                index: _currentIndex,
                children: List.generate(7, (i) =>
                  _builtPages.contains(i) ? _pageWidget(i) : const SizedBox.shrink()),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: HomeBottomNav(
                currentIndex: _currentIndex,
                onIndexChanged: (index) {
                  _builtPages.add(index);
                  _tabNotifier.index = index;
                  setState(() => _currentIndex = index);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
