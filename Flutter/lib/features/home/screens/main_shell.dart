import 'package:flutter/material.dart';
import 'package:justus/all_imports.dart';

class MainShell extends StatefulWidget {
  static final GlobalKey<MainShellState> shellKey = GlobalKey<MainShellState>();

  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final Set<int> _builtPages = {0};

  void switchToTab(int index) {
    _builtPages.add(index);
    setState(() => _currentIndex = index);
  }

  Widget _pageWidget(int index) {
    switch (index) {
      case 0: return const HomepageScreen();
      case 1: return GameScreen(isActive: _currentIndex == 1);
      case 2: return MoodScreen(isActive: _currentIndex == 2);
      case 3: return BucketListScreen(isActive: _currentIndex == 3);
      case 4: return DriveScreen(isActive: _currentIndex == 4);
      case 5: return FavoritesScreen(isActive: _currentIndex == 5);
      case 6: return const ProfileScreen();
      default: return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.backgroundDark,
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
                setState(() => _currentIndex = index);
              },
            ),
          ),
        ],
      ),
    );
  }
}
