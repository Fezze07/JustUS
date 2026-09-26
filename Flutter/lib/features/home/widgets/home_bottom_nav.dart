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
      height: AppDims.navBar,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: context.palette.canvas.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        border: Border.all(color: context.palette.overlay),
        boxShadow: [
          BoxShadow(
            color: context.palette.shadowStrong,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(context, Icons.sports_esports, context.loc.nav_games,
                currentIndex == 1, () => onIndexChanged(1)),
            _buildNavItem(context, Icons.emoji_emotions, context.loc.nav_mood,
                currentIndex == 2, () => onIndexChanged(2)),
            _buildNavItem(context, Icons.checklist, context.loc.nav_list,
                currentIndex == 3, () => onIndexChanged(3)),
            _buildCenterItem(context),
            _buildNavItem(context, Icons.photo, context.loc.nav_drive,
                currentIndex == 4, () => onIndexChanged(4)),
            _buildNavItem(context, Icons.favorite, context.loc.nav_favorites,
                currentIndex == 5, () => onIndexChanged(5)),
            _buildNavItem(context, Icons.person, context.loc.nav_profile,
                currentIndex == 6, () => onIndexChanged(6)),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, String label,
      bool isActive, VoidCallback onTap) {
    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color:
                    isActive ? context.palette.accentPurple : context.palette.contentTertiary,
                size: 26,
              ),
              const SizedBox(height: AppSpacing.xs),
              if (isActive)
                Container(
                  width: AppDims.dot,
                  height: AppDims.dot,
                  decoration: BoxDecoration(
                    color: context.palette.accentPurple,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterItem(BuildContext context) {
    final isHome = currentIndex == 0;
    return Semantics(
      button: true,
      selected: isHome,
      label: context.loc.nav_home,
      child: Container(
        width: AppDims.navCenter,
        height: AppDims.navCenter,
        decoration: BoxDecoration(
          gradient: isHome
              ? LinearGradient(
                  colors: [context.palette.accentPurple, context.palette.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isHome ? null : context.palette.overlay,
          shape: BoxShape.circle,
          boxShadow: isHome
              ? [
                  BoxShadow(
                    color: context.palette.accentPurple.withValues(alpha: 0.4),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Tooltip(
          message: context.loc.nav_home,
          child: IconButton(
            icon: Icon(Icons.home_filled,
                color: isHome
                    ? context.palette.onPrimary
                    : context.palette.contentSecondary,
                size: 28),
            onPressed: () => onIndexChanged(0),
          ),
        ),
      ),
    );
  }
}
