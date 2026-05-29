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
      title: 'Invita Partner',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Inserisci l\'email e il codice del tuo partner per inviare una richiesta.',
            style: VpWidgets.googleFont(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          VPTextField(
            controller: emailController,
            label: 'EMAIL PARTNER',
            hint: 'partner@example.com',
            inputType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          VPTextField(
            controller: codeController,
            label: 'CODICE PARTNER',
            hint: 'ABC123',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Annulla',
            style: VpWidgets.googleFont(color: Colors.white60),
          ),
        ),
        Consumer<AuthState>(
          builder: (context, authState, _) {
            return VPButton(
              label: 'Invia',
              isLoading: authState.isLoading,
              width: 100,
              onPressed: () async {
                final email = emailController.text.trim();
                final code = codeController.text.trim();
                if (email.isEmpty || code.isEmpty) {
                  UIUtils.showSnackBar(context, 'Compila tutti i campi',
                      isError: true);

                  return;
                }

                final success = await authState.invitePartner(email, code);
                if (!context.mounted) return;

                if (success) {
                  Navigator.pop(context);
                  UIUtils.showSnackBar(context, 'Invito inviato con successo!');
                }
              },
            );
          },
        ),
      ],
    );
  }
}
