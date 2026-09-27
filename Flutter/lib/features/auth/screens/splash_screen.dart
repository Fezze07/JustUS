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
    try {
      final authState = context.read<AuthState>();
      await authState.init().timeout(const Duration(seconds: 8));

      if (!mounted) return;

      final destination =
          await AuthNavigationUtils.determinePostAuthDestination(context);

      if (!mounted) return;

      unawaited(Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => destination),
      ));
    } catch (e, st) {
      AnsiLogger.error('Error during _checkAuth: $e\n$st', tag: 'SplashScreen');
      if (!mounted) return;
      unawaited(Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.surfaceSunken,
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
              context.loc.appTitle,
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
