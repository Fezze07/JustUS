import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class LogoutUtils {
  static void showLogoutDialog(BuildContext context, VoidCallback onConfirm) {
    unawaited(showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc.logout_title),
        content: Text(context.loc.logout_message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.loc.logout_cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.neonPink,
              disabledBackgroundColor:
                  AppButtonStyle.disabledBackground(AppColors.neonPink),
            ),
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: Text(context.loc.logout_confirm),
          ),
        ],
      ),
    ));
  }

  static Future<void> performLogout(BuildContext context) async {
    final authState = context.read<AuthState>();
    await authState.logout();
    if (!context.mounted) return;
    unawaited(Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    ));
  }
}
