import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:justus/all_imports.dart';

/// Invites a partner who has no JustUs account yet: the backend calls
/// `admin.inviteUserByEmail` and GoTrue sends the "Invite user" email. No
/// partnership row is created here — the pairing request still needs the
/// partner's 6-character code once they register.
class PartnerInviteEmailDialog extends StatefulWidget {
  const PartnerInviteEmailDialog({super.key});

  @override
  State<PartnerInviteEmailDialog> createState() =>
      _PartnerInviteEmailDialogState();

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const PartnerInviteEmailDialog(),
    );
  }
}

class _PartnerInviteEmailDialogState extends State<PartnerInviteEmailDialog> {
  late final TextEditingController emailController;

  @override
  void initState() {
    super.initState();
    emailController = TextEditingController();
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VPDialog(
      title: context.loc.partner_inviteEmailTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.loc.partner_inviteEmailDescription,
            style: VpWidgets.googleFont(
                color: context.palette.contentSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          VPTextField(
            controller: emailController,
            label: context.loc.partner_emailLabel,
            hint: context.loc.partner_emailHint,
            inputType: TextInputType.emailAddress,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            context.loc.common_cancel,
            style: VpWidgets.googleFont(color: context.palette.contentFaint),
          ),
        ),
        Consumer<AuthState>(
          builder: (context, authState, _) {
            return VPButton(
              label: context.loc.partner_send,
              isLoading: authState.isLoading,
              width: 100,
              onPressed: () async {
                final email = emailController.text.trim();
                if (email.isEmpty) {
                  ErrorHandler.showSnackBar(
                      context, context.loc.partner_fillAllFields,
                      isError: true);

                  return;
                }

                final success =
                    await authState.inviteUnregisteredPartner(email);
                if (!context.mounted) return;

                if (success) {
                  Navigator.pop(context);
                  ErrorHandler.showSnackBar(
                      context, context.loc.partner_inviteEmailSuccess);
                }
              },
            );
          },
        ),
      ],
    );
  }
}
