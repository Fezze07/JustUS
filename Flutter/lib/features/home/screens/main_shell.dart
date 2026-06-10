import 'package:flutter/material.dart';
import 'package:justus/all_imports.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  List<Widget> get _pages => [
    const HomepageScreen(),                       // 0 - Home (centro)
    GameScreen(isActive: _currentIndex == 1),     // 1 - Games
    MoodScreen(isActive: _currentIndex == 2),     // 2 - Mood
    BucketListScreen(isActive: _currentIndex == 3), // 3 - List
    DriveScreen(isActive: _currentIndex == 4),    // 4 - Drive
    FavoritesScreen(isActive: _currentIndex == 5),  // 5 - Favorites
    const ProfileScreen(),                        // 6 - Profile
  ];

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
              children: _pages,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: HomeBottomNav(
              currentIndex: _currentIndex,
              onIndexChanged: (index) {
                setState(() => _currentIndex = index);
              },
            ),
          ),
        ],
      ),
    );
  }
}
