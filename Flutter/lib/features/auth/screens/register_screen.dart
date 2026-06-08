// =============================================================================
// RegisterScreen - Violet-Punk Style
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return VPAuthLayout(
      title: context.loc.auth_registerTitle,
      subtitle: context.loc.auth_registerSubtitle,
      footer: VPAuthLink(
        text: context.loc.auth_alreadyAccount,
        actionText: context.loc.auth_logIn,
        onTap: () {
          Navigator.pop(context); // Go back to Login
        },
      ),
      children: [
        VPTextField(
          controller: _nameController,
          label: context.loc.auth_nameLabel,
          hint: context.loc.auth_nameHint,
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 16),
        VPTextField(
          controller: _emailController,
          label: context.loc.auth_emailLabel,
          hint: context.loc.auth_registerEmailHint,
          icon: Icons.email_outlined,
          inputType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        VPTextField(
          controller: _passwordController,
          label: context.loc.auth_passwordLabel,
          hint: '••••••••••',
          icon: Icons.lock_outline,
          isPassword: true,
          obscureText: _obscurePassword,
          onTogglePassword: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),

        const SizedBox(height: 40),

        // Action Button
        Consumer<AuthState>(
          builder: (context, state, _) {
            return VPButton(
              label: context.loc.auth_createAccount,
              isLoading: state.isLoading,
              onPressed: () async {
                final email = _emailController.text.trim();
                final password = _passwordController.text;
                final name = _nameController.text.trim();

                final nameError = Validators.validateRequired(
                  context,
                  name,
                  context.loc.auth_nameFieldName,
                );
                final emailError = Validators.validateEmail(context, email);
                final passwordError =
                    Validators.validatePassword(context, password);

                if (nameError != null ||
                    emailError != null ||
                    passwordError != null) {
                  final errorMessage =
                      nameError ?? emailError ?? passwordError!;
                  UIUtils.showSnackBar(context, errorMessage, isError: true);

                  return;
                }

                final authState = context.read<AuthState>();
                final success = await authState.register(
                  email,
                  password,
                  name,
                );

                if (!context.mounted) return;

                if (success) {
                  if (authState.isLoggedIn) {
                    unawaited(Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const PartnerScreen()),
                      (route) => false,
                    ));
                  } else {
                    unawaited(showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => VPDialog(
                        title: context.loc.auth_confirmEmailTitle,
                        content: Text(
                          context.loc.auth_confirmEmailMessage(email),
                          style: VpWidgets.googleFont(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              Navigator.of(context).pop(); // Torna al login
                            },
                            child: Text(
                              context.loc.auth_goToLogin,
                              style: VpWidgets.googleFont(
                                  color: AppColors.primary),
                            ),
                          ),
                        ],
                      ),
                    ));
                  }
                }
              },
            );
          },
        ),
      ],
    );
  }
}
