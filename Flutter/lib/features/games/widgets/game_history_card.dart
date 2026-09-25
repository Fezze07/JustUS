import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:justus/all_imports.dart';

class GameHistoryCard extends StatelessWidget {
  final String question;
  final String status;
  final Color badgeColor;
  final IconData icon;
  final String? userImageUrl;
  final String? partnerImageUrl;

  const GameHistoryCard({
    super.key,
    required this.question,
    required this.status,
    required this.badgeColor,
    required this.icon,
    this.userImageUrl,
    this.partnerImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return VPCard(
      padding: const EdgeInsets.all(16),
      borderColor: AppColors.borderDark,
      shadowColor: badgeColor.withValues(alpha: 0.05),
      blurRadius: 10,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: badgeColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.contentPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  status.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // Mini avatars
          SizedBox(
            width: 50,
            child: Stack(
              children: [
                VPAvatar(
                    imageUrl: userImageUrl,
                    size: 24,
                    borderColor: AppColors.backgroundDark),
                Positioned(
                  left: 16,
                  child: VPAvatar(
                      imageUrl: partnerImageUrl,
                      size: 24,
                      borderColor: AppColors.backgroundDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
