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
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.palette.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.palette.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isReceived ? Icons.person_add_outlined : Icons.mail_outline,
              color: context.palette.primary,
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
                    color: context.palette.contentPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  isReceived
                      ? context.loc.partner_wantsToConnect
                      : context.loc.partner_waitingResponse,
                  style: GoogleFonts.plusJakartaSans(
                    color: context.palette.contentTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (isReceived) ...[
            IconButton(
              onPressed: onAccept,
              icon: Icon(Icons.check_circle, color: context.palette.accentGreen),
              tooltip: context.loc.partner_acceptTooltip,
            ),
            IconButton(
              onPressed: onReject,
              icon: Icon(Icons.cancel, color: context.palette.accentPink),
              tooltip: context.loc.partner_declineTooltip,
            ),
          ] else
            IconButton(
              onPressed: onReject,
              icon: Icon(Icons.delete_outline,
                  color: context.palette.contentTertiary),
              tooltip: context.loc.partner_cancelRequestTooltip,
            ),
        ],
      ),
    );
  }
}
