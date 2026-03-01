// =============================================================================
// PartnerScreen - Partner Selection (Violet-Punk)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/auth_state.dart';
import '../state/profile_state.dart';
import '../constants/app_colors.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'homepage_screen.dart';

class PartnerScreen extends StatefulWidget {
  const PartnerScreen({super.key});

  @override
  State<PartnerScreen> createState() => _PartnerScreenState();
}

class _PartnerScreenState extends State<PartnerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProfileState>().loadProfile();
    });
  }

  String? _resolveUrl(String? url) {
     if (url == null) return null;
     if (url.startsWith('http')) return url;
     return '${ApiService.baseUrl}$url';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
             // Header
             Padding(
               padding: const EdgeInsets.only(top: 40, bottom: 20),
               child: Column(
                 children: [
                   Text(
                     'JustUS',
                     style: GoogleFonts.plusJakartaSans(
                       color: AppColors.primary,
                       fontSize: 20,
                       fontWeight: FontWeight.bold,
                       letterSpacing: 1,
                     ),
                   ),
                   const SizedBox(height: 48),
                   Text(
                     'Who are you connecting\nwith today?',
                     textAlign: TextAlign.center,
                     style: GoogleFonts.plusJakartaSans(
                       color: Colors.white,
                       fontSize: 28,
                       fontWeight: FontWeight.bold,
                       height: 1.2,
                     ),
                   ),
                 ],
               ),
             ),
             
             Expanded(
               child: Consumer<ProfileState>(
                 builder: (context, state, _) {
                   final partner = state.partnerProfile;
                   
                   return Center(
                     child: GridView.count(
                       shrinkWrap: true,
                       crossAxisCount: 2,
                       mainAxisSpacing: 32,
                       crossAxisSpacing: 32,
                       padding: const EdgeInsets.all(32),
                       children: [
                         // Existing Partner
                         if (partner != null)
                           _buildPartnerCard(
                             name: partner.username,
                             imageUrl: _resolveUrl(partner.profilePicUrl),
                             isConnected: true,
                             onTap: () {
                               Navigator.pushReplacement(
                                 context, 
                                 MaterialPageRoute(builder: (_) => const HomepageScreen()),
                               );
                             },
                           ),
                           
                         // New Connection
                         _buildAddPartnerCard(onTap: () {
                           // Navigate to add partner flow
                         }),
                       ],
                     ),
                   );
                 },
               ),
             ),
             
             // Footer
             Padding(
               padding: const EdgeInsets.only(bottom: 40),
               child: TextButton.icon(
                 onPressed: () async {
                   await context.read<AuthState>().logout();
                   if (!mounted) return;
                   Navigator.pushAndRemoveUntil(
                     context,
                     MaterialPageRoute(builder: (_) => const LoginScreen()),
                     (route) => false,
                   );
                 },
                 icon: const Icon(Icons.logout, color: Colors.white),
                 label: Text(
                   'Logout',
                   style: GoogleFonts.plusJakartaSans(
                     fontWeight: FontWeight.bold,
                     color: Colors.white,
                   ),
                 ),
               ),
             ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPartnerCard({
    required String name,
    String? imageUrl,
    required bool isConnected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 4),
                    boxShadow: [
                      BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10, spreadRadius: 2),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: AppColors.cardDark,
                    backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
                    child: imageUrl == null ? const Icon(Icons.person, size: 40, color: Colors.white) : null,
                  ),
                ),
                if (isConnected)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: const Icon(Icons.favorite, size: 16, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            'CONNECTED',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAddPartnerCard({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 2, style: BorderStyle.none), // Dotted border effect simulation
                color: AppColors.primary.withOpacity(0.1),
              ),
              child: Center(
                child: Container(
                   width: 100,
                   height: 100,
                   decoration: BoxDecoration(
                     shape: BoxShape.circle,
                     border: Border.all(color: AppColors.primary.withOpacity(0.5), style: BorderStyle.solid), // Dashed substitute
                   ),
                   child: const Icon(Icons.add, color: AppColors.primary, size: 40),
                ),
              ),
            ),
          ),
           const SizedBox(height: 12),
          Text(
            'New Connection',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            'Add a partner',
             style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.primary.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}
