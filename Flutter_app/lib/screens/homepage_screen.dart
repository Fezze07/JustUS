// =============================================================================
// HomepageScreen - Main screen with Stitch Design
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../constants/app_colors.dart';
import '../state/auth_state.dart';
import '../state/homepage_state.dart';
import '../state/mood_state.dart';
import '../state/profile_state.dart';

import 'mood_screen.dart';
import 'bucket_list_screen.dart';
import 'game_screen.dart';
import 'drive_screen.dart';
import 'profile_screen.dart';
import 'favorites_screen.dart';
import '../services/update_service.dart';

class HomepageScreen extends StatefulWidget {
  const HomepageScreen({super.key});

  @override
  State<HomepageScreen> createState() => _HomepageScreenState();
}

class _HomepageScreenState extends State<HomepageScreen> {
  final _updateService = UpdateService();
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_updateChecked) {
        _updateService.checkVersion(context);
        _updateChecked = true;
      }
    });
  }

  Future<void> _loadData() async {
    final homepageState = context.read<HomepageState>();
    final moodState = context.read<MoodState>();
    final profileState = context.read<ProfileState>();

    await Future.wait([
      homepageState.init(),
      moodState.loadPartnerMoodFromCache(),
      moodState.fetchPartnerMood(),
      profileState.loadProfile(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthState>();
    final profileState = context.watch<ProfileState>();
    
    // Mock relationship start date (should be in API)
    final daysTogether = DateTime.now().difference(DateTime(2024, 1, 1)).inDays;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          // Main Content
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: _loadData,
              color: AppColors.primary,
              backgroundColor: AppColors.backgroundDark,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 100), // Bottom padding for nav bar
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    _buildHeader(),
                    const SizedBox(height: 24),
                    
                    // Profile Section
                    _buildProfileSection(authState, profileState, daysTogether),
                    const SizedBox(height: 24),
                    
                    // Mood Card
                    _buildMoodCard(context),
                    const SizedBox(height: 24),
                    
                    // Quick Actions
                    _buildQuickActions(context),
                  ],
                ),
              ),
            ),
          ),
          
          // Bottom Navigation
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomNavBar(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildCircleButton(
          icon: Icons.menu,
          color: AppColors.primary,
          onTap: () {
            // TODO: Implement drawer or menu
          },
        ),
        Text(
          'JustUS',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
        _buildCircleButton(
          icon: Icons.favorite,
          color: Colors.redAccent,
          isFill: true,
          onTap: () {
             Navigator.push(
               context,
               MaterialPageRoute(builder: (_) => const FavoritesScreen()),
             );
          },
        ),
      ],
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isFill = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withOpacity(0.05),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          color: color,
          size: 20,
          fill: isFill ? 1.0 : 0.0,
        ),
      ),
    );
  }

  Widget _buildProfileSection(AuthState auth, ProfileState profile, int days) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // User Avatar
            _buildAvatar(
              name: 'YOU',
              url: profile.userProfile?.profilePicUrl,
              isActive: true,
            ),
            
            // Link Icon
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 2,
                    color: AppColors.primary.withOpacity(0.2),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A1B3D),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.1),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.link,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
            
            // Partner Avatar
            _buildAvatar(
              name: auth.partnerUsername ?? 'PARTNER',
              url: profile.partnerProfile?.profilePicUrl,
              isActive: true,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Together for $days days',
          style: GoogleFonts.plusJakartaSans(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Rome, Italy • 10:24 AM', // Mock location/time
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar({
    required String name,
    String? url,
    bool isActive = false,
  }) {
    return Column(
      children: [
        Stack(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: url != null && url.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _buildPlaceholderAvatar(),
                      )
                    : _buildPlaceholderAvatar(),
              ),
            ),
            if (isActive)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.backgroundDark,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          name.toUpperCase(),
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholderAvatar() {
    return Container(
      color: Colors.grey[800],
      child: const Icon(
        Icons.person,
        color: Colors.white54,
        size: 40,
      ),
    );
  }

  Widget _buildMoodCard(BuildContext context) {
    return Consumer<MoodState>(
      builder: (context, moodState, _) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.gradientStart,
                AppColors.gradientEnd,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OUR CURRENT MOOD',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Feeling Good!',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.explore,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '"Thinking about you and smiling."',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _buildMiniMood(moodState.userMood),
                      const SizedBox(width: 8),
                      _buildMiniMood(moodState.partnerMood),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MoodScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: const Text('Update Status'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniMood(String emoji) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        emoji,
        style: const TextStyle(fontSize: 18),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Quick Actions',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextButton(
              onPressed: () {},
              child: Text(
                'View All',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.1,
          children: [
            _buildActionCard(
              context,
              icon: Icons.sports_esports,
              title: 'Games',
              subtitle: 'Play a relationship quiz',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GameScreen()),
              ),
            ),
            _buildActionCard(
              context,
              icon: Icons.photo_library,
              title: 'Photos',
              subtitle: 'Our Shared Gallery',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DriveScreen()),
              ),
            ),
            _buildActionCard(
              context,
              icon: Icons.checklist,
              title: 'Bucket List',
              subtitle: '3 tasks pending',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BucketListScreen()),
              ),
            ),
            _buildActionCard(
              context,
              icon: Icons.chat_bubble,
              title: 'Nudge',
              subtitle: 'Send some love',
              onTap: () => _sendNudge(context),
            ),
          ],
        ),
      ],
    );
  }
  
  void _sendNudge(BuildContext context) {
    // Reusing the "Miss You" functionality as Nudge
    final homepageState = context.read<HomepageState>();
    homepageState.sendMissYou();
    
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nudge sent! ❤️'),
          backgroundColor: AppColors.primary,
          duration: Duration(seconds: 2),
        ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.05),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accentAqua.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: AppColors.accentAqua,
                  size: 24,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.grey[400],
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF191022).withOpacity(0.9),
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.05),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildNavItem(Icons.home, 'Home', isActive: true),
            _buildNavItem(Icons.forum, 'Chat'),
            
            // FAB
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(
                  color: AppColors.backgroundDark,
                  width: 4,
                ),
              ),
              child: IconButton(
                onPressed: () {
                   // Navigate to upload or create something
                   Navigator.push(
                     context,
                     MaterialPageRoute(builder: (_) => const DriveScreen()),
                   );
                },
                icon: const Icon(Icons.add, color: Colors.white),
              ),
            ),
            
            _buildNavItem(Icons.calendar_today, 'Events'),
            _buildNavItem(Icons.settings, 'Settings', onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, {bool isActive = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isActive ? AppColors.primary : Colors.grey[600],
            size: 24,
            fill: isActive ? 1.0 : 0.0,
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              color: isActive ? AppColors.primary : Colors.grey[600],
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
