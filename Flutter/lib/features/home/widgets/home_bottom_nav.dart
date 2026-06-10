import 'package:flutter/material.dart';

import 'package:justus/all_imports.dart';

class HomeBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;

  const HomeBottomNav({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(context, Icons.sports_esports, 'Games',
                currentIndex == 1, () => onIndexChanged(1)),
            _buildNavItem(context, Icons.emoji_emotions, 'Mood',
                currentIndex == 2, () => onIndexChanged(2)),
            _buildNavItem(context, Icons.checklist, 'List', currentIndex == 3,
                () => onIndexChanged(3)),
            _buildCenterItem(context),
            _buildNavItem(context, Icons.photo, 'Drive', currentIndex == 4,
                () => onIndexChanged(4)),
            _buildNavItem(context, Icons.favorite, 'Favorites',
                currentIndex == 5, () => onIndexChanged(5)),
            _buildNavItem(context, Icons.person, 'Profile', currentIndex == 6,
                () => onIndexChanged(6)),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, String label,
      bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isActive ? AppColors.neonPurple : Colors.white54,
            size: 26,
          ),
          const SizedBox(height: 4),
          if (isActive)
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: AppColors.neonPurple,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCenterItem(BuildContext context) {
    final isHome = currentIndex == 0;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: isHome
            ? const LinearGradient(
                colors: [AppColors.neonPurple, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isHome ? null : Colors.white.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        boxShadow: isHome
            ? [
                BoxShadow(
                  color: AppColors.neonPurple.withValues(alpha: 0.4),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: IconButton(
        icon: const Icon(Icons.home_filled, color: Colors.white, size: 28),
        onPressed: () => onIndexChanged(0),
      ),
    );
  }
}
