import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:justus/all_imports.dart';

class AuthNavigationUtils {
  /// Centralized post-authentication destination decision (F-N10).
  /// Single source of truth for determining whether a user lands on
  /// [LoginScreen], [MainShell], or [PartnerScreen].
  static Future<Widget> determinePostAuthDestination(BuildContext context) async {
    final authState = context.read<AuthState>();
    if (!authState.isLoggedIn) {
      return const LoginScreen();
    }

    final partnerState = context.read<PartnerState>();
    try {
      await partnerState.fetchPartnership().timeout(const Duration(seconds: 5));
    } catch (_) {}

    if (authState.hasPartner || partnerState.partner != null) {
      return const MainShell();
    } else {
      return const PartnerScreen();
    }
  }
}
