import 'package:flutter/material.dart';
import 'package:justus/all_imports.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const List<Widget> _pages = [
    HomepageScreen(),   // 0 - Home (centro)
    GameScreen(),       // 1 - Games
    MoodScreen(),       // 2 - Mood
    BucketListScreen(), // 3 - List
    DriveScreen(),      // 4 - Drive
    FavoritesScreen(),  // 5 - Favorites
    ProfileScreen(),    // 6 - Profile
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
