import 'dart:async';
import 'package:flutter/material.dart';
import 'package:justus/all_imports.dart';

class HomeBottomNav extends StatelessWidget {
  const HomeBottomNav({super.key});

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
            _buildNavItem(context, Icons.home_filled, 'Home', true, () {}),
            _buildNavItem(context, Icons.sports_esports, 'Games', false, () {
              unawaited(Navigator.push(context, MaterialPageRoute(builder: (_) => const GameScreen())));
            }),
            _buildCenterItem(context),
            _buildNavItem(context, Icons.photo_library, 'Photos', false, () {
              unawaited(Navigator.push(context, MaterialPageRoute(builder: (_) => const DriveScreen())));
            }),
            _buildNavItem(context, Icons.person, 'Profile', false, () {
              unawaited(Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())));
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, String label, bool isActive, VoidCallback onTap) {
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
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.neonPurple, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.neonPurple.withValues(alpha: 0.4),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: IconButton(
        icon: const Icon(Icons.favorite, color: Colors.white, size: 28),
        onPressed: () {
          // Action for the center button (e.g. quick nudge or love)
        },
      ),
    );
  }
}
