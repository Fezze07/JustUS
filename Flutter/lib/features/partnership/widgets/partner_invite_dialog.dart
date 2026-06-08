import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:justus/all_imports.dart';

class PartnerInviteDialog extends StatefulWidget {
  const PartnerInviteDialog({super.key});

  @override
  State<PartnerInviteDialog> createState() => _PartnerInviteDialogState();

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const PartnerInviteDialog(),
    );
  }
}

class _PartnerInviteDialogState extends State<PartnerInviteDialog> {
  late final TextEditingController emailController;
  late final TextEditingController codeController;

  @override
  void initState() {
    super.initState();
    emailController = TextEditingController();
    codeController = TextEditingController();
  }

  @override
  void dispose() {
    emailController.dispose();
    codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VPDialog(
      title: context.loc.partner_inviteTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.loc.partner_inviteDescription,
            style: VpWidgets.googleFont(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          VPTextField(
            controller: emailController,
            label: context.loc.partner_emailLabel,
            hint: context.loc.partner_emailHint,
            inputType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          VPTextField(
            controller: codeController,
            label: context.loc.partner_codeLabel,
            hint: context.loc.partner_codeHint,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            context.loc.common_cancel,
            style: VpWidgets.googleFont(color: Colors.white60),
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
                final code = codeController.text.trim();
                if (email.isEmpty || code.isEmpty) {
                  UIUtils.showSnackBar(context, context.loc.partner_fillAllFields,
                      isError: true);

                  return;
                }

                final success = await authState.invitePartner(email, code);
                if (!context.mounted) return;

                if (success) {
                  Navigator.pop(context);
                  UIUtils.showSnackBar(context, context.loc.partner_inviteSuccess);
                }
              },
            );
          },
        ),
      ],
    );
  }
}
