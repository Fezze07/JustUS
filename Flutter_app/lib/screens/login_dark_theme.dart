import 'package:flutter/material.dart';

class LoginDarkTheme extends StatelessWidget {
  const LoginDarkTheme({super.key});

  @override
  Widget build(BuildContext context) {
    // Cyberpunk Theme Colors
    const primaryNeonCyan = Color(0xFF00F7FF);
    const secondaryNeonPurple = Color(0xFFD100FF);
    const bgDeepPurple = Color(0xFF120024);
    const bgDarkerPurple = Color(0xFF0A0016);

    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: primaryNeonCyan,
          secondary: secondaryNeonPurple,
          surface: bgDeepPurple,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            letterSpacing: 2,
            color: Colors.white,
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: bgDeepPurple,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bgDeepPurple, bgDarkerPurple],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 60),
                  // Heart Logo Widget
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: bgDarkerPurple,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: secondaryNeonPurple.withOpacity(0.5), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: secondaryNeonPurple.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.favorite,
                        color: secondaryNeonPurple,
                        size: 60,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // App Title
                  Column(
                    children: [
                      Text(
                        'JUSTUS',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontSize: 42,
                              color: Colors.white,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 80,
                        height: 4,
                        decoration: BoxDecoration(
                          color: primaryNeonCyan,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 60),
                  
                  // Terminal ID Field
                  _buildFuturisticLabel('TERMINAL.ID'),
                  const SizedBox(height: 8),
                  _buildTerminalTextField(
                    icon: Icons.alternate_email,
                    hint: 'user@interface.sys',
                    color: primaryNeonCyan,
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Access Code Field
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildFuturisticLabel('ACCESS.CODE'),
                      GestureDetector(
                        onTap: () {},
                        child: Text(
                          'RESET_KEY',
                          style: TextStyle(
                            color: secondaryNeonPurple,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildTerminalTextField(
                    icon: Icons.lock_outline,
                    hint: '********',
                    color: primaryNeonCyan,
                    isPassword: true,
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Main Login Button
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryNeonCyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 10,
                      shadowColor: primaryNeonCyan.withOpacity(0.5),
                    ),
                    child: const Text(
                      'INITIALIZE LOGIN',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // External Auth Section
                  Center(
                    child: Text(
                      'EXTERNAL AUTH',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSocialButton('GOOGLE', primaryNeonCyan),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildSocialButton('iOS', Colors.white),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 60),
                  
                  // Register Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'NEED A NEW CIRCUIT? ',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 11,
                          letterSpacing: 1,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {},
                        child: const Text(
                          'REGISTER INTERFACE',
                          style: TextStyle(
                            color: primaryNeonCyan,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFuturisticLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF00F7FF),
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildTerminalTextField({
    required IconData icon,
    required String hint,
    required Color color,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: TextField(
        obscureText: isPassword,
        style: const TextStyle(color: Colors.white, letterSpacing: 1),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
          prefixIcon: Icon(icon, color: color, size: 20),
          suffixIcon: isPassword ? Icon(Icons.visibility_outlined, color: color.withOpacity(0.5), size: 18) : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildSocialButton(String label, Color color) {
    return OutlinedButton(
      onPressed: () {},
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withOpacity(0.3)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
