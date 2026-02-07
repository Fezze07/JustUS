// =============================================================================
// LoginScreen - Login form with username+code, password
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_state.dart';
import '../state/login_state.dart';
import '../state/partner_state.dart';
import '../services/notification_service.dart';
import 'register_screen.dart';
import 'homepage_screen.dart';
import 'partner_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _notificationService.init();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleEvent(LoginEvent event) {
    switch (event) {
      case SuccessLogin(:final username):
        _navigateAfterLogin();
      case ShowMessage(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      case SingleCodeFound(:final code):
        _codeController.text = code;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Codice trovato: $code')),
        );
      case MultipleCodesFound(:final codes):
        _showCodeSelectionDialog(codes);
    }
    context.read<LoginState>().clearEvent();
  }

  Future<void> _navigateAfterLogin() async {
    // Check if user has a partner
    final partnerState = context.read<PartnerState>();
    await partnerState.fetchPartnership();

    if (!mounted) return;

    if (partnerState.partner != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomepageScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PartnerScreen()),
      );
    }
  }

  void _showCodeSelectionDialog(List<String> codes) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleziona codice'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: codes.map((code) {
            return ListTile(
              title: Text(code),
              onTap: () {
                _codeController.text = code;
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _login() async {
    final deviceToken = await context.read<AuthState>().getDeviceToken();
    final usernameWithCode =
        '${_usernameController.text}#${_codeController.text}';
    if (!mounted) return;
    context
        .read<LoginState>()
        .login(usernameWithCode, _passwordController.text, deviceToken);
  }

  void _requestCodes() {
    context.read<LoginState>().requestCodes(
          _usernameController.text,
          _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Consumer<LoginState>(
            builder: (context, state, _) {
              // Handle events
              if (state.lastEvent != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _handleEvent(state.lastEvent!);
                });
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),
                  const Text(
                    '💖',
                    style: TextStyle(fontSize: 64),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Bentornato!',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Username field
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),

                  // Code field
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          decoration: const InputDecoration(
                            labelText: 'Codice',
                            prefixIcon: Icon(Icons.tag),
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: state.status == LoginStatus.loading
                            ? null
                            : _requestCodes,
                        icon: const Icon(Icons.search),
                        tooltip: 'Trova codice',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Password field
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 32),

                  // Login button
                  FilledButton(
                    onPressed:
                        state.status == LoginStatus.loading ? null : _login,
                    child: state.status == LoginStatus.loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Accedi'),
                  ),
                  const SizedBox(height: 16),

                  // Register link
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RegisterScreen()),
                      );
                    },
                    child: const Text('Non hai un account? Registrati'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
