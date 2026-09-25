// =============================================================================
// ResetPasswordScreen - Violet-Punk Styling (Post-Email Recovery Flow)
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            VPHeader(title: context.loc.auth_resetPasswordTitle),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.loc.auth_resetPasswordSubtitle,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: AppColors.contentTertiary,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // New Password
                      VPTextField(
                        controller: _newController,
                        label: context.loc.auth_newPasswordLabel,
                        isPassword: true,
                        obscureText: _obscureNew,
                        onTogglePassword: () =>
                            setState(() => _obscureNew = !_obscureNew),
                        hint: context.loc.auth_newPasswordHint,
                      ),

                      const SizedBox(height: 24),

                      // Confirm Password
                      VPTextField(
                        controller: _confirmController,
                        label: context.loc.auth_confirmPasswordLabel,
                        isPassword: true,
                        obscureText: _obscureConfirm,
                        onTogglePassword: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                        hint: context.loc.auth_confirmPasswordHint,
                      ),

                      const SizedBox(height: 48),

                      // Submit Button
                      Consumer<AuthState>(
                        builder: (context, authState, _) {
                          return VPButton(
                            label: context.loc.auth_updatePassword,
                            isLoading: authState.isLoading,
                            onPressed: () async {
                              final newPassword = _newController.text;
                              final confirmPassword = _confirmController.text;

                              final newError = Validators.validatePassword(
                                context,
                                newPassword,
                              );
                              final confirmError = confirmPassword !=
                                      newPassword
                                  ? context.loc.auth_validationPasswordMismatch
                                  : null;

                              final firstError = newError ?? confirmError;
                              if (firstError != null) {
                                UIUtils.showSnackBar(
                                  context,
                                  firstError,
                                  isError: true,
                                );
                                return;
                              }

                              final success = await authState
                                  .updatePasswordNew(newPassword);

                              if (!context.mounted) return;

                              if (success) {
                                final messenger = ScaffoldMessenger.of(context);
                                final message =
                                    context.loc.auth_passwordUpdated;
                                final closeLabel = context.loc.common_close;

                                final hasPartner = authState.hasPartner;
                                unawaited(Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => hasPartner
                                        ? MainShell(key: MainShell.shellKey)
                                        : const PartnerScreen(),
                                  ),
                                ));

                                UIUtils.showSnackBarOn(
                                  messenger,
                                  message,
                                  closeLabel: closeLabel,
                                );
                              }
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
