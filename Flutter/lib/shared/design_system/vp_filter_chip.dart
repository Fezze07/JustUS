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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.neonPurple : const Color(0xFF1E0B36),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: AppColors.neonPurple.withValues(alpha: 0.3),
          ),
          boxShadow: isActive ? [
            const BoxShadow(
              color: AppColors.neonPurple,
              blurRadius: 8,
            )
          ] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 4),
            ],
            Text(
              label.toUpperCase(),
              style: GoogleFonts.plusJakartaSans(
                color: isActive ? Colors.white : Colors.grey[300],
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
