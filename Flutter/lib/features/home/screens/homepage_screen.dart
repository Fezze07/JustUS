// =============================================================================
// HomepageScreen - Redesigned with Stitch JustUS "Midnight Glass" Design
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
class _C {
  static const surface = Color(0xFF151219);
  static const surfaceContainer = Color(0xFF211E26);
  static const primary = Color(0xFFD4BBFF); // light lavender
  static const primaryContainer = Color(0xFFB388FF); // neon purple
  static const secondary = Color(0xFFFFB3AE); // soft red/pink
  static const onSurface = Color(0xFFE7E0EA);
  static const onSurfaceVariant = Color(0xFFCCC3D4);
  static const outline = Color(0xFF958E9D);
  static const outlineVariant = Color(0xFF4A4452);
}

class HomepageScreen extends StatefulWidget {
  const HomepageScreen({super.key});

  @override
  State<HomepageScreen> createState() => _HomepageScreenState();
}

class _HomepageScreenState extends State<HomepageScreen>
    with SingleTickerProviderStateMixin {
  final _updateService = UpdateService();
  bool _updateChecked = false;
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  late final Animation<double> _pulseAnim =
      Tween<double>(begin: 1.0, end: 1.1).animate(
    CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
  );

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

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool force = false}) async {
    if (force) {
      await CacheService.clearCheckpoints([
        CacheService.kMoods,
        CacheService.kMissYou,
        CacheService.kBucketItems,
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
      context.read<BucketState>().init(),
    ]);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return VPScaffold(
      showAppBar: false,
      body: Stack(
        children: [
          // Atmospheric blobs (from Stitch HTML fixed bg elements)
          Positioned(
            top: -80,
            right: -80,
            child: _AtmosphericBlob(
              color: _C.primaryContainer.withValues(alpha: 0.05),
              size: MediaQuery.of(context).size.width * 0.7,
            ),
          ),
          Positioned(
            bottom: 60,
            left: -120,
            child: _AtmosphericBlob(
              color: const Color(0xFF46128D).withValues(alpha: 0.05),
              size: MediaQuery.of(context).size.width * 0.85,
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _loadData(force: true),
                    color: _C.primaryContainer,
                    backgroundColor: _C.surfaceContainer,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildProfileSection(),
                          const SizedBox(height: 24),
                          _buildMoodCard(context),
                          const SizedBox(height: 24),
                          _buildPendingBucketList(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── App Bar ────────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return ClipRect(
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: _C.surface.withValues(alpha: 0.8),
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
        ),
        child: Row(
          children: [
            // Menu button
            _NavIconButton(
              icon: Icons.menu_rounded,
              color: _C.primary,
              onTap: () {
                unawaited(Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ));
              },
            ),
            const Spacer(),
            // Title
            Text(
              context.loc.appTitle,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _C.primary,
                letterSpacing: -0.5,
              ),
            ),
            const Spacer(),
            // Animated heart button
            ScaleTransition(
              scale: _pulseAnim,
              child: _NavIconButton(
                icon: Icons.favorite_rounded,
                color: _C.secondary,
                  onTap: () {
                    MainShell.shellKey.currentState?.switchToTab(5);
                  },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Profile Section ────────────────────────────────────────────────────────
  Widget _buildProfileSection() {
    return Selector<ProfileState, (String?, String?, DateTime?)>(
      selector: (_, p) => (
        p.userProfile?.profilePicUrl,
        p.partnerProfile?.profilePicUrl,
        p.anniversaryDate,
      ),
      builder: (context, profileData, _) {
        final auth = context.read<AuthState>();
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 240,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(120),
                      gradient: RadialGradient(
                        colors: [
                          _C.primaryContainer.withValues(alpha: 0.15),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: Container(
                            height: 2,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  _C.primaryContainer,
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _AvatarColumn(
                              label: context.loc.common_you,
                              imageUrl: profileData.$1,
                            ),
                            _GlassLinkNode(),
                            _AvatarColumn(
                              label: auth.partnerDisplayName ??
                                  context.loc.common_partnerUpper,
                              imageUrl: profileData.$2,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (profileData.$3 != null) ...[
                const SizedBox(height: 20),
                _buildDaysTogether(profileData.$3!),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildDaysTogether(DateTime anniversary) {
    final difference = AppDateUtils.daysSince(anniversary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(
          color: _C.primaryContainer.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: _C.primaryContainer.withValues(alpha: 0.1),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$difference',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _C.primary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            context.loc.home_daysTogether.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _C.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Mood Card ──────────────────────────────────────────────────────────────
  Widget _buildMoodCard(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.loc.home_currentMoodTitle.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _C.onSurfaceVariant,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 32,
                      height: 2,
                      decoration: BoxDecoration(
                        color: _C.primaryContainer,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _GlassIconButton(
                  icon: Icons.explore_rounded,
                  color: _C.primaryContainer,
                  onTap: () {
                    MainShell.shellKey.currentState?.switchToTab(2);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Selector<MoodState, (String, String)>(
            selector: (_, m) => (
              m.userMood.isNotEmpty ? m.userMood : '😐',
              m.partnerMood.isNotEmpty ? m.partnerMood : '😐',
            ),
            builder: (context, moods, _) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _EmojiDisplay(
                      emoji: moods.$1,
                      glowColor: _C.primaryContainer,
                    ),
                    Container(
                      height: 48,
                      width: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.2),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    _EmojiDisplay(
                      emoji: moods.$2,
                      glowColor: _C.secondary,
                    ),
                  ],
                ),
              );
            },
          ),
          Selector<HomepageState, int>(
            selector: (_, h) => h.totalMissYou,
            builder: (context, totalMissYou, _) {
              final hpState = context.read<HomepageState>();
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      unawaited(hpState.sendMissYou());
                      UIUtils.showSnackBar(
                          context, context.loc.home_missYouSent);
                    },
                    child: _MissYouButton(
                      count: totalMissYou,
                      pulseAnim: _pulseAnim,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Bucket List ────────────────────────────────────────────────────────────
  Widget _buildPendingBucketList() {
    return Selector<BucketState, (List<BucketItem>, bool)>(
      selector: (_, s) => (s.items, s.isLoading),
      builder: (context, bucketData, _) {
        final all = bucketData.$1.where((item) => !item.done).toList();
        final pendingItems = all.take(4).toList();
        final totalPending = all.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.loc.home_bucketListTitle,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: _C.onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      MainShell.shellKey.currentState?.switchToTab(3);
                    },
                    child: Text(
                      context.loc.home_bucketListSubtitleDynamic(totalPending),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _C.primary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (bucketData.$2 && pendingItems.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _C.primaryContainer,
                    ),
                  ),
                ),
              )
            else if (pendingItems.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 8),
                child: Text(
                  context.loc.bucket_emptyCategory,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: _C.outlineVariant,
                  ),
                ),
              )
            else
              ...pendingItems.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildBucketTile(item),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBucketTile(BucketItem item) {
    return GestureDetector(
      onTap: () {
        MainShell.shellKey.currentState?.switchToTab(3);
      },
      child: _GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            // Category chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: BucketCategory.colorFor(item.category)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(
                  color: BucketCategory.colorFor(item.category)
                      .withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                BucketCategory.localizedLabel(item.category, context.loc).toUpperCase(),
            style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: BucketCategory.colorFor(item.category),
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                item.text,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _C.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: _C.outline,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// ── Private reusable sub-widgets ─────────────────────────────────────────────
// =============================================================================

/// Glassmorphic card container — matches `.glass-card` in Stitch HTML.
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  const _GlassCard({
    required this.child,
    this.padding,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0x661E1E1E), // rgba(30,30,30,0.4)
        borderRadius: borderRadius ?? BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
        // Simulate backdrop-filter via gradient sheen
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.04),
            Colors.transparent,
          ],
        ),
      ),
      child: child,
    );
  }
}

/// Circular icon button used in the app bar.
class _NavIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _NavIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: color, size: 26),
    );
  }
}

/// Avatar + label column for the profile section.
class _AvatarColumn extends StatelessWidget {
  final String label;
  final String? imageUrl;

  const _AvatarColumn({required this.label, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _C.primaryContainer.withValues(alpha: 0.3),
              width: 2,
            ),
            color: _C.surfaceContainer,
          ),
          child: ClipOval(
            child: imageUrl != null && imageUrl!.isNotEmpty
                ? Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _defaultAvatar(),
                  )
                : _defaultAvatar(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _C.onSurfaceVariant,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _defaultAvatar() => Container(
        color: _C.surfaceContainer,
        child: const Icon(Icons.person_rounded, color: _C.onSurfaceVariant),
      );
}

/// The glassmorphic link node between the two avatars.
class _GlassLinkNode extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(
          color: _C.primaryContainer.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: _C.primaryContainer.withValues(alpha: 0.3),
            blurRadius: 14,
          ),
        ],
      ),
      child: const Icon(
        Icons.link_rounded,
        color: _C.primary,
        size: 20,
      ),
    );
  }
}

/// Large emoji with a radial glow — matches the mood emoji display in Stitch.
class _EmojiDisplay extends StatelessWidget {
  final String emoji;
  final Color glowColor;

  const _EmojiDisplay({required this.emoji, required this.glowColor});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                glowColor.withValues(alpha: 0.2),
                Colors.transparent,
              ],
            ),
          ),
        ),
        Text(emoji, style: const TextStyle(fontSize: 52)),
      ],
    );
  }
}

/// The "Miss You" pill button with gradient + animated heart.
class _MissYouButton extends StatelessWidget {
  final int count;
  final Animation<double> pulseAnim;

  const _MissYouButton({required this.count, required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9999),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        gradient: LinearGradient(
          colors: [
            _C.primaryContainer.withValues(alpha: 0.2),
            _C.secondary.withValues(alpha: 0.2),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _C.primaryContainer.withValues(alpha: 0.15),
            blurRadius: 20,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: pulseAnim,
            child: const Icon(
              Icons.favorite_rounded,
              color: _C.secondary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            context.loc.home_nudgeTitle.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _C.onSurface,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9999),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _C.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Glassmorphic icon button (explore icon in mood card header).
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _GlassIconButton({
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

/// Atmospheric blurred blob for the background ambience.
class _AtmosphericBlob extends StatelessWidget {
  final Color color;
  final double size;

  const _AtmosphericBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size * 0.75,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
