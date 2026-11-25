import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:justus/all_imports.dart';

class AuthNavigationUtils {
  static Future<String> _resolvePostAuthRoute(BuildContext context) async {
    final authState = context.read<AuthState>();
    if (!authState.isLoggedIn) {
      return AppRoutes.login;
    }

    final partnerState = context.read<PartnerState>();
    try {
      await partnerState
          .fetchPartnership()
          .timeout(const Duration(seconds: 5));
    } catch (_) {}

    await authState.syncPartnership(partnerState.partnershipInfo);

    return authState.hasPartner ? AppRoutes.mainShell : AppRoutes.partner;
  }

  /// Centralized post-authentication destination decision (F-N10).
  /// Single source of truth for determining whether a user lands on
  /// [LoginScreen], [MainShell], or [PartnerScreen].
  static Future<Widget> determinePostAuthDestination(BuildContext context) async {
    return switch (await _resolvePostAuthRoute(context)) {
      AppRoutes.login => const LoginScreen(),
      AppRoutes.mainShell => const MainShell(),
      _ => const PartnerScreen(),
    };
  }

  /// Returns the route name string corresponding to the post-authentication destination.
  static Future<String> determinePostAuthRouteName(BuildContext context) {
    return _resolvePostAuthRoute(context);
  }
}
