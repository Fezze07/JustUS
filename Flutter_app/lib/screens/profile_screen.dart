// =============================================================================
// ProfileScreen - Violet-Punk Style
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../state/profile_state.dart';
import '../state/auth_state.dart';
import '../constants/app_colors.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Fix: Call loadProfile after the first frame to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProfileState>().loadProfile();
    });
  }

  String? _resolveUrl(String? url) {
    if (url == null) return null;
    if (url.startsWith('http')) return url;
    return '${ApiService.baseUrl}$url';
  }

  Future<void> _pickProfilePhoto() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
    );

    if (image != null) {
      final bytes = await image.readAsBytes();
      if (!mounted) return;

      context.read<ProfileState>().uploadProfilePhoto(
            bytes,
            image.name,
            image.mimeType ?? 'image/jpeg',
          );
    }
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: Text('Disconnect Session', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
        content: Text('End your current session?', style: GoogleFonts.plusJakartaSans(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.neonPink),
            onPressed: () async {
              await context.read<AuthState>().logout();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
             child: Text('Disconnect', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepViolet,
      body: Consumer<ProfileState>(
        builder: (context, state, _) {
          final user = state.userProfile;
          final partner = state.partnerProfile;
          final userPicUrl = _resolveUrl(user?.profilePicUrl);
          final partnerPicUrl = partner != null ? _resolveUrl(partner.profilePicUrl) : null;

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.neonBlue),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        'PROFILE & SETTINGS',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 40), // Balance
                    ],
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Connected Avatars
                  SizedBox(
                    height: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Gradient Line
                        Container(
                          width: 180,
                          height: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.neonPink.withOpacity(0.5), AppColors.neonPurple.withOpacity(0.5)],
                            ),
                          ),
                        ),
                        // Heart Icon
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(colors: [AppColors.neonPink, AppColors.neonPurple]),
                            boxShadow: [
                              BoxShadow(color: AppColors.neonPurple.withOpacity(0.6), blurRadius: 20),
                            ],
                          ),
                          child: const Icon(Icons.favorite, color: Colors.white, size: 28),
                        ),
                        // User Avatar (Left)
                        Positioned(
                          left: 0,
                          child: GestureDetector(
                            onTap: _pickProfilePhoto,
                            child: Stack(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.neonPink, width: 2),
                                    boxShadow: [
                                      BoxShadow(color: AppColors.neonPink.withOpacity(0.3), blurRadius: 20),
                                    ],
                                  ),
                                  child: CircleAvatar(
                                    radius: 40,
                                    backgroundColor: AppColors.punkPurple,
                                    backgroundImage: userPicUrl != null ? NetworkImage(userPicUrl) : null,
                                    child: userPicUrl == null ? const Icon(Icons.person, size: 40, color: Colors.white54) : null,
                                  ),
                                ),
                                if (state.isUploading)
                                  Positioned.fill(child: CircularProgressIndicator(color: AppColors.neonPink)),
                              ],
                            ),
                          ),
                        ),
                        // Partner Avatar (Right)
                        Positioned(
                          right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.neonPurple, width: 2),
                              boxShadow: [
                                BoxShadow(color: AppColors.neonPurple.withOpacity(0.3), blurRadius: 20),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 40,
                              backgroundColor: AppColors.punkPurple,
                              backgroundImage: partnerPicUrl != null ? NetworkImage(partnerPicUrl) : null,
                              child: partnerPicUrl == null ? const Icon(Icons.person, size: 40, color: Colors.white54) : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Names
                  Text(
                    '${user?.username ?? 'You'} & ${partner?.username ?? 'Partner'}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: Colors.white,
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Since Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.punkPurple,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.neonPurple.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt, color: AppColors.neonBlue, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'CONNECTED',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: AppColors.neonBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                   Text(
                    user?.bio ?? '"Building our forever, one day at a time."',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: Colors.white54,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  
                  const SizedBox(height: 48),
                  
                  // Settings Sections
                  _buildSectionHeader('SYSTEM OVERRIDE', AppColors.neonPink),
                  _buildSettingsGroup([
                     _buildSettingsItem(
                       icon: Icons.notifications_active,
                       title: 'Notifications',
                       subtitle: 'Activity & neural reminders',
                       trailing: Switch(value: true, onChanged: (v) {}, activeColor: AppColors.neonBlue),
                       color: AppColors.neonBlue,
                     ),
                     _buildDivider(),
                     _buildSettingsItem(
                       icon: Icons.visibility,
                       title: 'Dark Mode',
                       subtitle: 'Violet-punk optimized',
                       trailing: Switch(value: true, onChanged: (v) {}, activeColor: AppColors.neonBlue),
                       color: AppColors.neonBlue,
                     ),
                  ]),
                  
                  const SizedBox(height: 24),
                  
                  _buildSectionHeader('CORE CONNECTION', AppColors.neonPurple),
                  _buildSettingsGroup([
                     _buildSettingsItem(
                       icon: Icons.event_note,
                       title: 'Anniversary',
                       subtitle: 'June 14, 2023',
                       trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                       color: AppColors.neonPink,
                     ),
                     _buildDivider(),
                     _buildSettingsItem(
                       icon: Icons.lock,
                       title: 'Change Password', // Modified from design to fit functionality
                       subtitle: 'Secure your shared space',
                       trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                       color: AppColors.neonPurple,
                       onTap: () => Navigator.pushNamed(context, '/change-password'), // Assuming route, or push directly
                     ),
                  ]),
                  
                  const SizedBox(height: 32),
                  
                  // Logout Button
                  InkWell(
                    onTap: _logout,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.deepViolet,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.red.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.power_settings_new, color: Colors.red),
                          const SizedBox(width: 12),
                          Text(
                            'DISCONNECT SESSION',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                   Text(
                    'JustUS OS v2.4.0-REV',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10, 
                      fontWeight: FontWeight.bold, 
                      color: Colors.white30,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: GoogleFonts.plusJakartaSans(
             fontSize: 10,
             fontWeight: FontWeight.w900,
             letterSpacing: 2,
             color: color,
          ),
        ),
      ),
    );
  }
  
  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.punkPurple.withOpacity(0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.punkPurple.withOpacity(0.6)),
      ),
      child: Column(children: children),
    );
  }
  
  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48, 
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.deepViolet,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 11, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
  
  Widget _buildDivider() {
    return Divider(height: 1, color: AppColors.deepViolet.withOpacity(0.5), indent: 16, endIndent: 16);
  }
}
