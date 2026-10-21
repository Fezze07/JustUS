// =============================================================================
// LoginScreen - Violet-Punk Style
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return VPAuthLayout(
      title: context.loc.auth_loginTitle,
      subtitle: context.loc.auth_loginSubtitle,
      footer: VPAuthLink(
        text: context.loc.auth_loginNoAccount,
        actionText: context.loc.auth_signUp,
        onTap: () {
          unawaited(Navigator.pushNamed(context, AppRoutes.register));
        },
      ),
      children: [
        // Email
        VPTextField(
          controller: _emailController,
          label: context.loc.auth_emailTitle,
          icon: Icons.email,
          hint: context.loc.auth_emailHint,
        ),

        const SizedBox(height: 20),

        // Password
        VPTextField(
          controller: _passwordController,
          label: context.loc.auth_passwordTitle,
          icon: Icons.lock_outline,
          hint: '••••••••••',
          isPassword: true,
          obscureText: _obscurePassword,
          onTogglePassword: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),

        const SizedBox(height: 12),

        // Forgot Password
        Consumer<AuthState>(
          builder: (context, state, _) {
            return Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: state.isLoading
                    ? null
                    : () async {
                        final email = _emailController.text;
                        final emailError =
                            Validators.validateEmail(context, email);
                        if (emailError != null) {
                          ErrorHandler.showSnackBar(context, emailError,
                              isError: true);
                          return;
                        }

                        // Il messaggio di esito è mostrato dal listener globale
                        // di AuthState (main.dart).
                        await state.resetPassword(email);
                      },
                child: Text(
                  context.loc.auth_forgotPassword,
                  style: VpWidgets.googleFont(
                    color: context.palette.accentBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 20),

        // Login Button
        Consumer<AuthState>(
          builder: (context, state, _) {
            return VPButton(
              label: context.loc.auth_loginButton,
              isLoading: state.isLoading,
              onPressed: () async {
                final email = _emailController.text;
                final password = _passwordController.text;

                final emailError = Validators.validateEmail(context, email);
                final passwordError =
                    Validators.validatePassword(context, password);

                if (emailError != null || passwordError != null) {
                  final errorMessage = emailError ?? passwordError!;
                  ErrorHandler.showSnackBar(context, errorMessage,
                      isError: true);

                  return;
                }

                final success = await state.login(email, password);
                if (!context.mounted) return;
                if (success) {
                  if (!context.mounted) return;
                  final routeName =
                      await AuthNavigationUtils.determinePostAuthRouteName(
                          context);
                  if (!context.mounted) return;
                  unawaited(Navigator.pushReplacementNamed(context, routeName));
                }
              },
            );
          },
        ),
      ],
    );
  }
}
