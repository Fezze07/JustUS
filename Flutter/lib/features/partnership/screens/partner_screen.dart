// =============================================================================
// PartnerScreen - Partner Selection (Violet-Punk)
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

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
      unawaited(context.read<ProfileState>().loadProfile());
      unawaited(context.read<AuthState>().fetchSentInvitations());
      unawaited(context.read<AuthState>().fetchReceivedInvitations());
    });
  }

  @override
  Widget build(BuildContext context) {
    return VPScaffold(
      showAppBar: false,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.only(top: 40, bottom: 20),
              child: Column(
                children: [
                  Text(
                    context.loc.appTitle,
                    style: VpWidgets.googleFont(
                      color: AppColors.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    context.loc.partner_title,
                    textAlign: TextAlign.center,
                    style: VpWidgets.googleFont(
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
              child: Consumer2<ProfileState, AuthState>(
                builder: (context, profileState, authState, _) {
                  final partner = profileState.partnerProfile;
                  final sentInvitations = authState.sentInvitations;
                  final receivedInvitations = authState.receivedInvitations;
                  if (kDebugMode) {
                    print(
                        '[PartnerScreen] Building with ${sentInvitations.length} sent, ${receivedInvitations.length} received');
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      await authState.fetchSentInvitations();
                      await authState.fetchReceivedInvitations();
                    },
                    color: AppColors.primary,
                    backgroundColor: AppColors.cardDark,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Your Personal Code Card
                          if (profileState.userProfile?.partnershipCode != null)
                            _buildYourCodeCard(
                                profileState.userProfile!.partnershipCode!),

                          const SizedBox(height: 16),

                          Center(
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 32,
                              runSpacing: 32,
                              children: [
                                // Existing Partner
                                if (partner != null)
                                  SizedBox(
                                    width: 160,
                                    height: 160,
                                    child: _buildPartnerCard(
                                      name: partner.username,
                                      imageUrl:
                                          ApiService.resolveProtectedMediaUrl(
                                              partner.profilePicUrl),
                                      isConnected: true,
                                      onTap: () {
                                        unawaited(Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  MainShell(key: MainShell.shellKey)),
                                        ));
                                      },
                                    ),
                                  ),

                                // New Connection (only if no partner and no sent invitation)
                                if (partner == null && sentInvitations.isEmpty)
                                  SizedBox(
                                    width: 160,
                                    height: 160,
                                    child: _buildAddPartnerCard(onTap: () {
                                      DialogUtils.showPartnerInvite(context);
                                    }),
                                  ),
                              ],
                            ),
                          ),

                          if (receivedInvitations.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildInvitationsList(
                                context.loc.partner_receivedRequests, receivedInvitations,
                                isReceived: true),
                          ],

                          if (sentInvitations.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildInvitationsList(
                                context.loc.partner_sentRequests, sentInvitations,
                                isReceived: false),
                          ] else if (sentInvitations.isEmpty &&
                              receivedInvitations.isEmpty &&
                              kDebugMode) ...[
                            const SizedBox(height: 32),
                            Text(context.loc.partner_noPendingInvites,
                                style: const TextStyle(color: Colors.white24)),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: TextButton.icon(
                onPressed: () {
                  LogoutUtils.showLogoutDialog(
                      context, () => LogoutUtils.performLogout(context));
                },
                icon: const Icon(Icons.logout, color: Colors.white),
                label: Text(
                  context.loc.partner_logout,
                  style: VpWidgets.googleFont(
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
                DecoratedBox(
                  decoration: VpWidgets.cardDecoration(
                    borderRadius: 50, // Circle
                    borderColor: AppColors.primary,
                    boxShadow: [
                      VpWidgets.boxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 10),
                    ],
                  ),
                  child: VPAvatar(
                    imageUrl: imageUrl,
                    size: 100,
                    borderColor: AppColors.primary,
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
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 4)
                        ],
                      ),
                      child: const Icon(Icons.favorite,
                          size: 16, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: VpWidgets.googleFont(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            context.loc.partner_connected,
            style: VpWidgets.googleFont(
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
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    width: 2,
                    style: BorderStyle.none), // Dotted border effect simulation
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
              child: Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.primary
                            .withValues(alpha: 0.5)), // Dashed substitute
                  ),
                  child:
                      const Icon(Icons.add, color: AppColors.primary, size: 40),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.loc.partner_newConnection,
            style: VpWidgets.googleFont(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            context.loc.partner_addPartner,
            style: VpWidgets.googleFont(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.primary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvitationsList(
      String title, List<PartnershipInvitation> invitations,
      {required bool isReceived}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            title,
            style: VpWidgets.googleFont(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 32),
          itemCount: invitations.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, index) {
            final invite = invitations[index];

            return InvitationTile(
              invite: invite,
              isReceived: isReceived,
              onAccept: () async {
                debugPrint(
                    '[PartnerScreen] Accepting invitation ${invite.id}...');
                final success =
                    await context.read<AuthState>().acceptInvitation(invite.id);
                debugPrint('[PartnerScreen] Acceptance success: $success');

                if (success && mounted) {
                  if (mounted) {
                    await context.read<PartnerState>().fetchPartnership();
                  }
                  if (mounted) {
                    await context.read<ProfileState>().loadProfile(force: true);
                  }
                  if (mounted) {
                    unawaited(Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) => MainShell(key: MainShell.shellKey)),
                    ));
                  }
                } else if (!success && mounted) {
                  UIUtils.showSnackBar(
                      context, context.loc.partner_acceptError,
                      isError: true);
                }
              },
              onReject: () =>
                  context.read<AuthState>().rejectInvitation(invite.id),
            );
          },
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildYourCodeCard(String code) {
    return VPCard(
      margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      padding: const EdgeInsets.all(20),
      borderColor: AppColors.primary.withValues(alpha: 0.3),
      shadowColor: AppColors.primary.withValues(alpha: 0.1),
      child: Column(
        children: [
          Text(
            context.loc.partner_personalCodeTitle,
            style: VpWidgets.googleFont(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                code,
                style: VpWidgets.googleFont(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: code)));
                  UIUtils.showSnackBar(
                      context, context.loc.partner_codeCopied);
                },
                icon: const Icon(Icons.copy_rounded,
                    color: AppColors.primary, size: 24),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.loc.partner_personalCodeSubtitle,
            textAlign: TextAlign.center,
            style: VpWidgets.googleFont(
              color: Colors.white38,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
