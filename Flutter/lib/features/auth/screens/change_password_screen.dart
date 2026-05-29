// =============================================================================
// ChangePasswordScreen - Violet-Punk Styling
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:justus/all_imports.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            const VPHeader(title: 'Change Password'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
              Text(
                'Create a new password that is unique and secure.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(height: 32),
              
              // Old Password
              VPTextField(
                controller: _oldController,
                label: 'Current Password',
                isPassword: true,
                obscureText: _obscureOld,
                onTogglePassword: () => setState(() => _obscureOld = !_obscureOld),
                hint: 'Enter current password',
              ),
              
              const SizedBox(height: 24),
              
              // New Password
              VPTextField(
                controller: _newController,
                label: 'New Password',
                isPassword: true,
                obscureText: _obscureNew,
                onTogglePassword: () => setState(() => _obscureNew = !_obscureNew),
                hint: 'Enter new password',
              ),
              
              const SizedBox(height: 24),
              
              // Confirm Password
              VPTextField(
                controller: _confirmController,
                label: 'Confirm Password',
                isPassword: true,
                obscureText: _obscureConfirm,
                onTogglePassword: () => setState(() => _obscureConfirm = !_obscureConfirm),
                hint: 'Re-enter new password',
              ),
              
              const SizedBox(height: 48),
              
              // Update Button
              VPButton(
                label: 'Update Password',
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    // Logic to update password
                    UIUtils.showSnackBar(context, 'Password updated successfully!');
                    Navigator.pop(context);
                  }
                },
              ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
