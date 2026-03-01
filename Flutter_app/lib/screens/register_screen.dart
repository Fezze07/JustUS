// =============================================================================
// RegisterScreen - Violet-Punk Style
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/auth_state.dart';
import '../constants/app_colors.dart';
import 'homepage_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _partnerEmailController = TextEditingController();
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Create Account',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Header
            Text(
              'Join JustUS',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start your journey to a deeper connection.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 32),

            // Personal Info Card
            _buildSectionCard(
              title: 'Personal Info',
              icon: Icons.person,
              children: [
                _buildTextField(
                  controller: _nameController,
                  label: 'Your Name',
                  hint: 'John Doe',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _emailController,
                  label: 'Email',
                  hint: 'john@example.com',
                  inputType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _passwordController,
                  label: 'Password',
                  hint: '••••••••',
                  isPassword: true,
                  obscureText: _obscurePassword,
                  onTogglePassword: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Partner Link Card
            _buildSectionCard(
              title: 'Partner Link',
              icon: Icons.favorite,
              children: [
                _buildTextField(
                  controller: _partnerEmailController,
                  label: "Partner's Email",
                  hint: 'jane@example.com',
                  inputType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.neonBlue, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "We'll send them an invite to link your accounts.",
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.neonBlue,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 40),

            // Action Button
            Consumer<AuthState>(
              builder: (context, state, _) {
                 if (state.isLoading) {
                   return const Center(child: CircularProgressIndicator(color: AppColors.neonBlue));
                 }
                return ElevatedButton(
                  onPressed: () async {
                    // Implement registration logic
                    // For now, simulate success or navigate freely
                     final success = await state.register(
                        _emailController.text,
                        _passwordController.text,
                        _nameController.text,
                      );
                      
                      if (success && mounted) {
                        // Handle partner invite logic here if needed
                         Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const HomepageScreen()),
                          (route) => false,
                        );
                      } else if (mounted) {
                         ScaffoldMessenger.of(context).showSnackBar(
                           SnackBar(content: Text(state.error ?? 'Registration failed')),
                         );
                      }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 8,
                    shadowColor: AppColors.primary.withOpacity(0.5),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: Text(
                    'Create Account & Invite Partner',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
            
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Already have an account?',
                  style: GoogleFonts.plusJakartaSans(color: Colors.white54),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // Go back to Login
                  },
                  child: Text(
                    'Log in',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.neonPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType inputType = TextInputType.text,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onTogglePassword,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundDark,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            keyboardType: inputType,
            obscureText: obscureText,
            style: GoogleFonts.plusJakartaSans(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: Colors.white38,
                        size: 20,
                      ),
                      onPressed: onTogglePassword,
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
