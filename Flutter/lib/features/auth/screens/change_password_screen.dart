// =============================================================================
// ChangePasswordScreen - Violet-Punk Styling
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:justus/all_imports.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _oldController.dispose();
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
            VPHeader(title: context.loc.auth_changePasswordTitle),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.loc.auth_changePasswordSubtitle,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: Colors.white54,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Old Password
                      VPTextField(
                        controller: _oldController,
                        label: context.loc.auth_currentPasswordLabel,
                        isPassword: true,
                        obscureText: _obscureOld,
                        onTogglePassword: () =>
                            setState(() => _obscureOld = !_obscureOld),
                        hint: context.loc.auth_currentPasswordHint,
                      ),

                      const SizedBox(height: 24),

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

                      // Update Button
                      Consumer<AuthState>(
                        builder: (context, authState, _) {
                          return VPButton(
                            label: context.loc.auth_updatePassword,
                            isLoading: authState.isLoading,
                            onPressed: () async {
                              final oldPassword = _oldController.text;
                              final newPassword = _newController.text;
                              final confirmPassword = _confirmController.text;

                              final oldError = Validators.validateRequired(
                                context,
                                oldPassword,
                                context.loc.auth_currentPasswordLabel,
                              );
                              final newError = Validators.validatePassword(
                                context,
                                newPassword,
                              );
                              final confirmError = confirmPassword != newPassword
                                  ? context.loc.auth_validationPasswordMismatch
                                  : null;

                              final firstError =
                                  oldError ?? newError ?? confirmError;
                              if (firstError != null) {
                                UIUtils.showSnackBar(
                                  context,
                                  firstError,
                                  isError: true,
                                );
                                return;
                              }

                              final success = await authState.changePassword(
                                currentPassword: oldPassword,
                                newPassword: newPassword,
                              );

                              if (!context.mounted) return;

                              if (success) {
                                UIUtils.showSnackBar(
                                  context,
                                  context.loc.auth_passwordUpdated,
                                );
                                Navigator.pop(context);
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
