// =============================================================================
// ProfileScreen - Violet-Punk Style
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    // Fix: Call loadProfile after the first frame to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<ProfileState>().loadProfile());
      unawaited(_loadAppVersion());
    });
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = 'v${info.version}';
      });
    }
  }

  Future<void> _pickProfilePhoto() async {
    final XFile? image = await MediaPickerService.showPickerSheet(
      context,
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

  Future<String?> _showTextEditDialog({
    required String title,
    required String initialValue,
    required String fieldHint,
    required int maxLines,
    required bool allowEmpty,
    required String emptyMessage,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextEditDialog(
        title: title,
        initialValue: initialValue,
        fieldHint: fieldHint,
        maxLength: maxLines > 1 ? 280 : 60,
        maxLines: maxLines,
        allowEmpty: allowEmpty,
        emptyMessage: emptyMessage,
      ),
    );

    return result?.trim();
  }

  Future<void> _editDisplayName(User user) async {
    final value = await _showTextEditDialog(
      title: context.loc.profile_displayNameTitle,
      fieldHint: context.loc.profile_displayNameTitle,
      initialValue: user.username,
      maxLines: 1,
      allowEmpty: false,
      emptyMessage: context.loc.profile_displayNameEmpty,
    );
    if (!mounted || value == null || value == user.username) return;

    final saved = await context.read<ProfileState>().updateDisplayName(value);
    if (saved && mounted) {
      ErrorHandler.showSnackBar(context, context.loc.profile_saved);
    }
  }

  Future<void> _showWipeConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => VPDialog(
        title: context.loc.profile_wipeConfirmTitle,
        content: Text(context.loc.profile_wipeConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.loc.profile_wipeCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.danger,
              disabledBackgroundColor:
                  AppButtonStyle.disabledBackground(context.palette.danger),
            ),
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
        context.read<ProfileState>().clear();

        ErrorHandler.showSnackBar(context, context.loc.profile_dataWiped);
        unawaited(context.read<ProfileState>().loadProfile(force: true));
        unawaited(rt.refreshChannel());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return VPScaffold(
      backgroundColor: context.palette.surfaceSunken,
      showAppBar: false,
      body: Selector<ProfileState, (User?, User?, bool, DateTime?)>(
        selector: (_, s) =>
            (s.userProfile, s.partnerProfile, s.isUploading, s.anniversaryDate),
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
                                context.palette.accentPink.withValues(alpha: 0.5),
                                context.palette.accentPurple.withValues(alpha: 0.5)
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
                            gradient: LinearGradient(colors: [
                              context.palette.accentPink,
                              context.palette.accentPurple
                            ]),
                            boxShadow: [
                              VpWidgets.boxShadow(
                                context,
                                color:
                                    context.palette.accentPurple.withValues(alpha: 0.6),
                              ),
                            ],
                          ),
                          child: Icon(Icons.favorite,
                              color: context.palette.contentPrimary, size: 28),
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
                            borderColor: context.palette.accentPurple,
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
                      color: context.palette.contentPrimary,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Since Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.palette.surfaceGroup,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                          color: context.palette.accentPurple.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt,
                            color: context.palette.accentBlue, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          context.loc.profile_connected,
                          style: VpWidgets.googleFont(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: context.palette.accentBlue,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Settings Sections
                  VPSectionHeader(
                      title: context.loc.settings_appearanceSection),
                  VPSettingGroup(children: [
                    VPSettingTile(
                      icon: Icons.palette_outlined,
                      title: context.loc.settings_themeTitle,
                      subtitle: context.loc.settings_themeSubtitle,
                      trailing: VPSegmentedControl<bool>(
                        value: !context.watch<ThemeProvider>().isDark,
                        onChanged: (isLight) => unawaited(context
                            .read<ThemeProvider>()
                            .setThemeMode(isLight ? ThemeMode.light : ThemeMode.dark)),
                        options: [
                          VPSegmentedControlOption(
                            value: true,
                            label: context.loc.settings_themeLight,
                            icon: Icons.light_mode,
                          ),
                          VPSegmentedControlOption(
                            value: false,
                            label: context.loc.settings_themeDark,
                            icon: Icons.dark_mode,
                          ),
                        ],
                      ),
                      color: context.palette.accentPurple,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  VPSectionHeader(
                      title: context.loc.systemOverrideSectionTitle),
                  VPSettingGroup(children: [
                    VPSettingTile(
                      icon: Icons.settings,
                      title: context.loc.languageSettingTitle,
                      subtitle: context.loc.languageSettingSubtitle,
                      trailing: Icon(Icons.chevron_right,
                          color: context.palette.contentTertiary),
                      color: context.palette.accentPurple,
                      onTap: () =>
                          Navigator.pushNamed(context, '/localization'),
                    ),
                    const VPDivider(),
                    VPSettingTile(
                      icon: Icons.notifications_active,
                      title: context.loc.settings_notificationsTitle,
                      subtitle: context.loc.settings_notificationsSubtitle,
                      trailing: Switch(
                          value: true,
                          onChanged: (v) {},
                          activeThumbColor: context.palette.accentBlue),
                      color: context.palette.accentBlue,
                    ),
                    const VPDivider(),
                    VPSettingTile(
                      icon: Icons.system_update,
                      title: context.loc.update_checkTitle,
                      subtitle: context.loc.update_checkSubtitle,
                      trailing: Icon(Icons.chevron_right,
                          color: context.palette.contentTertiary),
                      color: context.palette.accentBlue,
                      onTap: () => UpdateService()
                          .checkVersion(context, showNoUpdateToast: true),
                    ),
                  ]),

                  const SizedBox(height: 24),

                  VPSectionHeader(
                      title: context.loc.profile_coreConnectionSection),
                  VPSettingGroup(children: [
                    if (user?.partnershipCode != null) ...[
                      VPSettingTile(
                        icon: Icons.key,
                        title: context.loc.profile_yourPartnerCodeTitle,
                        subtitle: context.loc
                            .profile_shareToConnect(user!.partnershipCode!),
                        trailing: Icon(Icons.copy,
                            color: context.palette.contentTertiary),
                        color: context.palette.accentPink,
                        onTap: () {
                          unawaited(Clipboard.setData(
                              ClipboardData(text: user.partnershipCode!)));
                          ErrorHandler.showSnackBar(
                              context,
                              context.loc
                                  .profile_copiedCode(user.partnershipCode!),
                              backgroundColor: context.palette.accentPink);
                        },
                      ),
                      const VPDivider(),
                    ],
                    VPSettingTile(
                      icon: Icons.lock,
                      title: context.loc.auth_changePasswordTitle,
                      subtitle: context.loc.profile_changePasswordSubtitle,
                      trailing: Icon(Icons.chevron_right,
                          color: context.palette.contentTertiary),
                      color: context.palette.accentPurple,
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
                      trailing: Icon(Icons.edit,
                          color: context.palette.contentTertiary),
                      color: context.palette.accentPurple,
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
                                colorScheme: Theme.of(context).colorScheme
                                    .copyWith(
                                  primary: context.palette.accentPurple,
                                  onPrimary: context.palette.onPrimary,
                                  surface: context.palette.surfaceSunken,
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

                  const SizedBox(height: 24),

                  VPSectionHeader(title: context.loc.profile_identitySection),
                  VPSettingGroup(children: [
                    VPSettingTile(
                      icon: Icons.badge_outlined,
                      title: context.loc.profile_displayNameTitle,
                      subtitle: user?.username ?? context.loc.common_youTitle,
                      trailing: Icon(Icons.edit,
                          color: context.palette.contentTertiary),
                      color: context.palette.accentGreen,
                      onTap: () {
                        if (user != null) unawaited(_editDisplayName(user));
                      },
                    ),
                  ]),

                  if (kDebugMode) ...[
                    const SizedBox(height: 48),
                    VPSectionHeader(
                        title: context.loc.profile_debugUtilitiesSection),
                    VPSettingGroup(children: [
                      VPSettingTile(
                        icon: Icons.delete_forever,
                        title: context.loc.profile_wipeDataTitle,
                        subtitle: context.loc.profile_wipeDataSubtitle,
                        trailing: Icon(Icons.warning_amber_rounded,
                            color: context.palette.warning),
                        color: context.palette.warning,
                        onTap: _showWipeConfirmation,
                      ),
                    ]),
                  ],

                  const SizedBox(height: 32),

                  // Logout Button
                  InkWell(
                    onTap: _logout,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: context.palette.surfaceSunken,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                            color: context.palette.danger.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.power_settings_new,
                              color: context.palette.danger),
                          const SizedBox(width: 12),
                          Text(
                            context.loc.profile_disconnectSession,
                            style: VpWidgets.googleFont(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: context.palette.danger,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  GestureDetector(
                    onTap: () => UpdateService()
                        .checkVersion(context, showNoUpdateToast: true),
                    child: Text(
                      context.loc.profile_appVersion(_appVersion),
                      style: VpWidgets.googleFont(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: context.palette.contentPlaceholder,
                        letterSpacing: 1.5,
                      ),
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

class _TextEditDialog extends StatefulWidget {
  const _TextEditDialog({
    required this.title,
    required this.initialValue,
    required this.fieldHint,
    required this.maxLength,
    required this.maxLines,
    required this.allowEmpty,
    required this.emptyMessage,
  });

  final String title;
  final String initialValue;
  final String fieldHint;
  final int maxLength;
  final int maxLines;
  final bool allowEmpty;
  final String emptyMessage;

  @override
  State<_TextEditDialog> createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<_TextEditDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VPDialog(
      title: widget.title,
      content: TextField(
        key: const ValueKey('edit-text-field'),
        controller: _controller,
        autofocus: true,
        maxLines: widget.maxLines,
        minLines: widget.maxLines > 1 ? 2 : 1,
        maxLength: widget.maxLength,
        style: TextStyle(color: context.palette.contentPrimary),
        decoration: InputDecoration(
          hintText: widget.fieldHint,
          hintStyle: TextStyle(color: context.palette.contentDisabled),
          errorText: _errorText,
          counterStyle: TextStyle(color: context.palette.contentDisabled),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide:
                BorderSide(color: context.palette.accentPurple.withValues(alpha: 0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: context.palette.accentPurple),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.loc.common_cancel),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            if (!widget.allowEmpty && value.isEmpty) {
              setState(() => _errorText = widget.emptyMessage);
              return;
            }
            Navigator.pop(context, value);
          },
          child: Text(context.loc.common_save),
        ),
      ],
    );
  }
}
