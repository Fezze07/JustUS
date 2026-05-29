import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:justus/all_imports.dart';

class InvitationTile extends StatelessWidget {
  final PartnershipInvitation invite;
  final bool isReceived;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const InvitationTile({
    super.key,
    required this.invite,
    required this.isReceived,
    this.onAccept,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isReceived ? Icons.person_add_outlined : Icons.mail_outline,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.username,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  isReceived ? 'Wants to connect' : 'Waiting for response',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (isReceived) ...[
            IconButton(
              onPressed: onAccept,
              icon: const Icon(Icons.check_circle, color: AppColors.neonGreen),
              tooltip: 'Accept',
            ),
            IconButton(
              onPressed: onReject,
              icon: const Icon(Icons.cancel, color: AppColors.neonPink),
              tooltip: 'Decline',
            ),
          ] else
            IconButton(
              onPressed: onReject,
              icon: const Icon(Icons.delete_outline, color: Colors.white54),
              tooltip: 'Cancel Request',
            ),
        ],
      ),
    );
  }
}
