import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:justus/all_imports.dart';

class VPFilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;

  const VPFilterChip({
    super.key,
    required this.label,
    this.isActive = false,
    this.icon,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: isActive ? AppColors.neonPurple : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: AppColors.neonPurple.withValues(alpha: 0.3),
            ),
            boxShadow: isActive
                ? const [
                    BoxShadow(
                      color: AppColors.neonPurple,
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: iconColor),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                label.toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                  color: isActive
                      ? AppColors.contentPrimary
                      : AppColors.neutralMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
