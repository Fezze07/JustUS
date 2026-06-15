// =============================================================================
// ProfileScreen - Violet-Punk Style
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

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
      unawaited(context.read<ProfileState>().loadProfile());
    });
  }

  Future<void> _pickProfilePhoto() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
    );

    if (image != null) {
      if (!mounted) return;
      unawaited(context.read<ProfileState>().uploadProfilePhoto(image.path));
    }
  }

  void _logout() {
    LogoutUtils.showLogoutDialog(
        context, () => LogoutUtils.performLogout(context));
  }

  Future<void> _showWipeConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.deepViolet,
        title: Text(
          context.loc.profile_wipeConfirmTitle,
          style:
              const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: Text(
          context.loc.profile_wipeConfirmContent,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.loc.profile_wipeCancel,
                style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.loc.profile_wipeConfirm),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && mounted) {
      final rt = context.read<RealtimeSyncService>();
      rt.suppress();

      final success = await context.read<ProfileState>().wipeAppData();
      if (success && mounted) {
        context.read<GameState>().clear();
        context.read<BucketState>().clear();
        context.read<DriveState>().clear();
        context.read<MoodState>().clear();
        context.read<HomepageState>().clear();

        UIUtils.showSnackBar(context, context.loc.profile_dataWiped);
        unawaited(context.read<ProfileState>().loadProfile(force: true));
        unawaited(rt.refreshChannel());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return VPScaffold(
      backgroundColor: AppColors.deepViolet,
      showAppBar: false,
      body: Selector<ProfileState, (User?, User?, bool, DateTime?)>(
        selector: (_, s) => (s.userProfile, s.partnerProfile, s.isUploading, s.anniversaryDate),
        builder: (context, profileData, _) {
          final user = profileData.$1;
          final partner = profileData.$2;
          final isUploading = profileData.$3;
          final userPicPath = user?.profilePicUrl;
          final partnerPicPath = partner?.profilePicUrl;

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  // Header
                  VPHeader(
                    title: context.loc.profileSettingsTitle.toUpperCase(),
                    onBack: () => Navigator.pop(context),
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
                              colors: [
                                AppColors.neonPink.withValues(alpha: 0.5),
                                AppColors.neonPurple.withValues(alpha: 0.5)
                              ],
                            ),
                          ),
                        ),
                        // Heart Icon
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(colors: [
                              AppColors.neonPink,
                              AppColors.neonPurple
                            ]),
                            boxShadow: [
                              VpWidgets.boxShadow(
                                color:
                                    AppColors.neonPurple.withValues(alpha: 0.6),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.favorite,
                              color: Colors.white, size: 28),
                        ),
                        // User Avatar (Left)
                        Positioned(
                          left: 0,
                          child: GestureDetector(
                            onTap: _pickProfilePhoto,
                            child: VPAvatar(
                              imageUrl: userPicPath,
                              isUploading: isUploading,
                            ),
                          ),
                        ),
                        // Partner Avatar (Right)
                        Positioned(
                          right: 0,
                          child: VPAvatar(
                            imageUrl: partnerPicPath,
                            borderColor: AppColors.neonPurple,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Names
                  Text(
                    '${user?.username ?? context.loc.common_youTitle} & ${partner?.username ?? context.loc.common_partner}',
                    style: VpWidgets.googleFont(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Since Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.punkPurple,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.neonPurple.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt,
                            color: AppColors.neonBlue, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          context.loc.profile_connected,
                          style: VpWidgets.googleFont(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: AppColors.neonBlue,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (user?.bio != null && user!.bio!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      user.bio!,
                      textAlign: TextAlign.center,
                      style: VpWidgets.googleFont(
                        fontSize: 14,
                        color: Colors.white54,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],

                  const SizedBox(height: 48),

                  // Settings Sections
                  VPSectionHeader(title: context.loc.systemOverrideSectionTitle),
                  VPSettingGroup(children: [
                    VPSettingTile(
                      icon: Icons.settings,
                      title: context.loc.languageSettingTitle,
                      subtitle: context.loc.languageSettingSubtitle,
                      trailing: const Icon(Icons.chevron_right,
                          color: Colors.white54),
                      color: AppColors.neonPurple,
                      onTap: () => Navigator.pushNamed(context, '/localization'),
                    ),
                    const VPDivider(),
                    VPSettingTile(
                      icon: Icons.notifications_active,
                      title: context.loc.settings_notificationsTitle,
                      subtitle: context.loc.settings_notificationsSubtitle,
                      trailing: Switch(
                          value: true,
                          onChanged: (v) {},
                          activeThumbColor: AppColors.neonBlue),
                      color: AppColors.neonBlue,
                    ),
                    const VPDivider(),
                    VPSettingTile(
                      icon: Icons.visibility,
                      title: context.loc.settings_darkModeTitle,
                      subtitle: context.loc.settings_darkModeSubtitle,
                      trailing: Switch(
                          value: true,
                          onChanged: (v) {},
                          activeThumbColor: AppColors.neonBlue),
                      color: AppColors.neonBlue,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  VPSectionHeader(title: context.loc.profile_coreConnectionSection),
                  VPSettingGroup(children: [
                    if (user?.partnershipCode != null) ...[
                      VPSettingTile(
                        icon: Icons.key,
                        title: context.loc.profile_yourPartnerCodeTitle,
                        subtitle: context.loc
                            .profile_shareToConnect(user!.partnershipCode!),
                        trailing: const Icon(Icons.copy, color: Colors.white54),
                        color: AppColors.neonPink,
                        onTap: () {
                          unawaited(Clipboard.setData(
                              ClipboardData(text: user.partnershipCode!)));
                          UIUtils.showSnackBar(
                              context,
                              context.loc.profile_copiedCode(user.partnershipCode!),
                              backgroundColor: AppColors.neonPink);
                        },
                      ),
                      const VPDivider(),
                    ],
                    VPSettingTile(
                      icon: Icons.lock,
                      title: context.loc.auth_changePasswordTitle,
                      subtitle: context.loc.profile_changePasswordSubtitle,
                      trailing: const Icon(Icons.chevron_right,
                          color: Colors.white54),
                      color: AppColors.neonPurple,
                      onTap: () =>
                          Navigator.pushNamed(context, '/change-password'),
                    ),
                    const VPDivider(),
                    VPSettingTile(
                      icon: Icons.calendar_today,
                      title: context.loc.profile_anniversaryTitle,
                      subtitle: profileData.$4 != null
                          ? "${profileData.$4!.day}/${profileData.$4!.month}/${profileData.$4!.year}"
                          : context.loc.profile_anniversaryEmpty,
                      trailing: const Icon(Icons.edit, color: Colors.white54),
                      color: AppColors.neonPurple,
                      onTap: () async {
                        final profileState = context.read<ProfileState>();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: profileData.$4 ?? DateTime.now(),
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: AppColors.neonPurple,
                                  onPrimary: Colors.white,
                                  surface: AppColors.deepViolet,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          unawaited(profileState.updateAnniversaryDate(picked));
                        }
                      },
                    ),
                  ]),

                  if (kDebugMode) ...[
                    const SizedBox(height: 48),
                    VPSectionHeader(title: context.loc.profile_debugUtilitiesSection),
                    VPSettingGroup(children: [
                      VPSettingTile(
                        icon: Icons.delete_forever,
                        title: context.loc.profile_wipeDataTitle,
                        subtitle: context.loc.profile_wipeDataSubtitle,
                        trailing: const Icon(Icons.warning_amber_rounded,
                            color: Colors.orange),
                        color: Colors.orange,
                        onTap: _showWipeConfirmation,
                      ),
                    ]),
                  ],

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
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.power_settings_new,
                              color: Colors.red),
                          const SizedBox(width: 12),
                          Text(
                            context.loc.profile_disconnectSession,
                            style: VpWidgets.googleFont(
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
                    context.loc.profile_appVersion('v2.4.0-REV'),
                    style: VpWidgets.googleFont(
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
}
