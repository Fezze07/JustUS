// =============================================================================
// HomepageScreen - Main screen with Stitch Design
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadData());
      if (!_updateChecked) {
        unawaited(_updateService.checkVersion(context));
        _updateChecked = true;
      }
    });
  }

  Future<void> _loadData({bool force = false}) async {
    if (force) {
      await CacheService.clearCheckpoints([
        CacheService.kMoods,
        CacheService.kMissYou,
      ]);
    }

    if (!mounted) return;

    final homepageState = context.read<HomepageState>();
    final moodState = context.read<MoodState>();
    final profileState = context.read<ProfileState>();
    await Future.wait([
      homepageState.init(),
      moodState.initHome(),
      profileState.loadProfile(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return VPScaffold(
      showAppBar: false,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _loadData(force: true),
          color: AppColors.primary,
          backgroundColor: AppColors.backgroundDark,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                24, 16, 24, 100), // Bottom padding for nav bar
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                VPHeader(
                  title: context.loc.appTitle,
                  showBackButton: false,
                  leading: VPCircleButton(
                    icon: Icons.menu,
                    color: AppColors.primary,
                    onTap: () {
                      unawaited(Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ProfileScreen()),
                      ));
                    },
                    hasShadow: false,
                  ),
                  trailing: [
                    VPCircleButton(
                      icon: Icons.favorite,
                      color: Colors.redAccent,
                      isFill: true,
                      onTap: () {
                        unawaited(Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const FavoritesScreen()),
                        ));
                      },
                      hasShadow: false,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Profile Section
                _buildProfileSection(),
                const SizedBox(height: 24),

                // Mood Card
                _buildMoodCard(context),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    return Consumer2<AuthState, ProfileState>(
      builder: (context, auth, profile, _) {
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // User Avatar
                VPUserAvatar(
                  name: context.loc.common_you,
                  imageUrl: profile.userProfile?.profilePicUrl,
                  indicator: VPUserAvatar.onlineIndicator,
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
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A1B3D),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.1),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
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
                VPUserAvatar(
                  name: auth.partnerDisplayName ??
                      context.loc.common_partnerUpper,
                  imageUrl: profile.partnerProfile?.profilePicUrl,
                  indicator: VPUserAvatar.onlineIndicator,
                ),
              ],
            ),
            if (profile.anniversaryDate != null) ...[
              const SizedBox(height: 16),
              _buildDaysTogether(profile.anniversaryDate!),
            ],
          ],
        );
      },
    );
  }

  Widget _buildDaysTogether(DateTime anniversary) {
    final difference = AppDateUtils.daysSince(anniversary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Text(
            '$difference',
            style: VpWidgets.googleFont(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
            ),
          ),
          Text(
            context.loc.home_daysTogether,
            style: VpWidgets.googleFont(
              color: AppColors.primary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodCard(BuildContext context) {
    return Consumer2<MoodState, HomepageState>(
      builder: (context, moodState, hpState, _) {
        return VPCard(
          padding: const EdgeInsets.all(24),
          borderColor: Colors.white.withValues(alpha: 0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.loc.home_currentMoodTitle,
                    style: VpWidgets.googleFont(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
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
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    moodState.userMood.isNotEmpty ? moodState.userMood : '😐',
                    style: const TextStyle(fontSize: 48),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: 2,
                      height: 40,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  Text(
                    moodState.partnerMood.isNotEmpty
                        ? moodState.partnerMood
                        : '😐',
                    style: const TextStyle(fontSize: 48),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: GestureDetector(
                  onTap: () {
                    unawaited(hpState.sendMissYou());
                    UIUtils.showSnackBar(context, context.loc.home_missYouSent);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.2),
                          Colors.redAccent.withValues(alpha: 0.2),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite,
                            color: Colors.redAccent, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          '${hpState.totalMissYou}',
                          style: VpWidgets.googleFont(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
