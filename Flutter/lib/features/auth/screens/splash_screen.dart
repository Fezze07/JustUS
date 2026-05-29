import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_checkAuth());
  }

  Future<void> _checkAuth() async {
    final authState = context.read<AuthState>();
    await authState.init();

    if (!mounted) return;

    if (authState.isLoggedIn) {
      // Check if user has a partner
      final partnerState = context.read<PartnerState>();
      await partnerState.fetchPartnership();

      if (!mounted) return;

      if (partnerState.partner != null) {
        // Has partner, go to homepage
        unawaited(Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomepageScreen()),
        ));
      } else {
        // No partner, go to partner screen
        unawaited(Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PartnerScreen()),
        ));
      }
    } else {
      // Not logged in, go to login
      unawaited(Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '💖',
              style: TextStyle(fontSize: 80),
            ),
            const SizedBox(height: 24),
            Text(
              'JustUs',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
