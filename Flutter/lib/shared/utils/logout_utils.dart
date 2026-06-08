import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class LogoutUtils {
  static void showLogoutDialog(BuildContext context, VoidCallback onConfirm) {
    unawaited(showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: Text(context.loc.logout_title,
            style: GoogleFonts.plusJakartaSans(color: Colors.white)),
        content: Text(context.loc.logout_message,
            style: GoogleFonts.plusJakartaSans(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.loc.logout_cancel,
                style: GoogleFonts.plusJakartaSans(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.neonPink),
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: Text(context.loc.logout_confirm,
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
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
