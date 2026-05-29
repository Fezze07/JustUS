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
      title: 'Join JustUS',
      subtitle: 'Start your journey to a deeper connection.',
      footer: VPAuthLink(
        text: 'Already have an account?',
        actionText: 'Log in',
        onTap: () {
          Navigator.pop(context); // Go back to Login
        },
      ),
      children: [
        VPTextField(
          controller: _nameController,
          label: 'YOUR NAME',
          hint: 'John Doe',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 16),
        VPTextField(
          controller: _emailController,
          label: 'EMAIL',
          hint: 'john@example.com',
          icon: Icons.email_outlined,
          inputType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        VPTextField(
          controller: _passwordController,
          label: 'PASSWORD',
          hint: '••••••••',
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
              label: 'Create Account',
              isLoading: state.isLoading,
              onPressed: () async {
                final email = _emailController.text.trim();
                final password = _passwordController.text;
                final name = _nameController.text.trim();

                final nameError = Validators.validateRequired(name, 'Nome');
                final emailError = Validators.validateEmail(email);
                final passwordError = Validators.validatePassword(password);

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
                        title: 'Controlla la tua email',
                        content: Text(
                          'Abbiamo inviato un link di conferma a $email.\n\n'
                          'Clicca sul link per attivare il tuo account, poi torna qui per accedere.',
                          style: VpWidgets.googleFont(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              Navigator.of(context).pop(); // Torna al login
                            },
                            child: Text(
                              'Vai al login',
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
