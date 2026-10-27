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

class _PartnerScreenState extends State<PartnerScreen>
    with StateMessageListener<PartnerState, PartnerScreen> {
  @override
  PartnerState get messageSource => context.read<PartnerState>();

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
                      color: context.palette.primary,
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
                      color: context.palette.contentPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Consumer3<ProfileState, AuthState, PartnerState>(
                builder: (context, profileState, authState, partnerState, _) {
                  final partner = profileState.partnerProfile;
                  final sentInvitations = authState.sentInvitations;
                  final receivedInvitations = authState.receivedInvitations;
                  final cancellation = partnerState.cancellation;
                  AnsiLogger.auth(
                      'Building with ${sentInvitations.length} sent, ${receivedInvitations.length} received',
                      tag: 'PartnerScreen');

                  return RefreshIndicator(
                    onRefresh: () async {
                      await authState.fetchSentInvitations();
                      await authState.fetchReceivedInvitations();
                      await partnerState.fetchPartnership();
                    },
                    color: context.palette.primary,
                    backgroundColor: context.palette.surface,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (cancellation != null && cancellation.requestedByMe) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: VPCard(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Text(
                                      'Cancellation requested. Waiting for ${cancellation.partnerDisplayName ?? 'partner'} to approve before continuing.',
                                      textAlign: TextAlign.center,
                                      style: VpWidgets.googleFont(
                                        color: context.palette.contentPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton(
                                      onPressed: () async {
                                        final res = await partnerState
                                            .revertCancellation(
                                                cancellation.partnershipId);
                                        if (!context.mounted) return;
                                        if (res is Success<void>) {
                                          PartnershipRepository
                                              .clearPartnershipCache();
                                          await context
                                              .read<AuthState>()
                                              .refreshPartnershipFromRealtime();
                                          await partnerState.fetchPartnership();
                                          if (!context.mounted) return;
                                          Navigator.pushReplacementNamed(
                                              context, AppRoutes.mainShell);
                                        } else {
                                          ErrorHandler.handle(res, context: context);
                                        }
                                      },
                                      child: const Text('Restore partnership'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ] else if (cancellation != null &&
                              !cancellation.requestedByMe) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: InvitationTile(
                                invite: PartnershipInvitation(
                                  id: cancellation.partnershipId,
                                  status: 'pending',
                                  createdAt: DateTime.now(),
                                  partnerId: cancellation.partnerId,
                                  partnerDisplayName:
                                      cancellation.partnerDisplayName,
                                  isReceived: true,
                                ),
                                isReceived: true,
                                title: '${cancellation.partnerDisplayName ?? 'Partner'} asked to end the partnership',
                                showAccept: true,
                                showReject: true,
                                onAccept: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => VPDialog(
                                      title: 'End partnership',
                                      content: const Text(
                                          'This will delete all shared data. This action is final.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: Text(context.loc.common_cancel),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                context.palette.danger,
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Accept'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true || !context.mounted) return;
                                  final res = await partnerState
                                      .acceptCancellation(
                                          cancellation.partnershipId);
                                  if (!context.mounted) return;
                                  if (res is Success<Map<String, dynamic>>) {
                                    PartnershipRepository
                                        .clearPartnershipCache();
                                    await context
                                        .read<AuthState>()
                                        .refreshPartnershipFromRealtime();
                                    await partnerState.fetchPartnership();
                                    if (!context.mounted) return;
                                    ErrorHandler.showSnackBar(context,
                                        'Partnership ended. All shared data was deleted.');
                                  } else {
                                    await context
                                        .read<AuthState>()
                                        .refreshPartnershipFromRealtime();
                                    await partnerState.fetchPartnership();
                                    if (!context.mounted) return;
                                    if (partnerState.cancellation == null &&
                                        partnerState.partner == null) {
                                      ErrorHandler.showSnackBar(context,
                                          'Partnership ended. All shared data was deleted.');
                                    } else {
                                      ErrorHandler.handle(res, context: context);
                                    }
                                  }
                                },
                                onReject: () async {
                                  final res = await partnerState.revertCancellation(
                                      cancellation.partnershipId);
                                  if (!context.mounted) return;
                                  if (res is Success<void>) {
                                    PartnershipRepository.clearPartnershipCache();
                                    await context
                                        .read<AuthState>()
                                        .refreshPartnershipFromRealtime();
                                    await partnerState.fetchPartnership();
                                    if (!context.mounted) return;
                                    Navigator.pushReplacementNamed(
                                        context, AppRoutes.mainShell);
                                  } else {
                                    ErrorHandler.handle(res, context: context);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (cancellation == null) ...[
                            // Your Personal Code Card
                            if (profileState.userProfile?.partnershipCode != null)
                              _buildYourCodeCard(
                                  profileState.userProfile!.partnershipCode!),

                            // Invite a partner who has no JustUs account yet
                            if (partner == null) _buildInviteByEmailButton(),

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
                                          unawaited(Navigator.pushReplacementNamed(
                                            context,
                                            AppRoutes.mainShell,
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
                                  context.loc.partner_receivedRequests,
                                  receivedInvitations,
                                  isReceived: true),
                            ],

                            if (sentInvitations.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _buildInvitationsList(
                                  context.loc.partner_sentRequests,
                                  sentInvitations,
                                  isReceived: false),
                            ] else if (sentInvitations.isEmpty &&
                                receivedInvitations.isEmpty &&
                                kDebugMode) ...[
                              const SizedBox(height: 32),
                              Text(context.loc.partner_noPendingInvites,
                                  style: TextStyle(
                                      color: context.palette.contentHint)),
                            ],
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
                icon: Icon(Icons.logout, color: context.palette.contentPrimary),
                label: Text(
                  context.loc.partner_logout,
                  style: VpWidgets.googleFont(
                    fontWeight: FontWeight.bold,
                    color: context.palette.contentPrimary,
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
                    context,
                    borderRadius: 50, // Circle
                    borderColor: context.palette.primary,
                    boxShadow: [
                      VpWidgets.boxShadow(
                          context,
                          color: context.palette.primary.withValues(alpha: 0.3),
                          blurRadius: 10),
                    ],
                  ),
                  child: VPAvatar(
                    imageUrl: imageUrl,
                    size: 100,
                    borderColor: context.palette.primary,
                  ),
                ),
                if (isConnected)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: context.palette.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: context.palette.shadowSoft, blurRadius: 4)
                        ],
                      ),
                      child: Icon(Icons.favorite,
                          size: 16, color: context.palette.contentPrimary),
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
              color: context.palette.contentPrimary,
            ),
          ),
          Text(
            context.loc.partner_connected,
            style: VpWidgets.googleFont(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.palette.primary,
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
                    color: context.palette.primary.withValues(alpha: 0.4),
                    width: 2,
                    style: BorderStyle.none), // Dotted border effect simulation
                color: context.palette.primary.withValues(alpha: 0.1),
              ),
              child: Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: context.palette.primary
                            .withValues(alpha: 0.5)), // Dashed substitute
                  ),
                  child:
                      Icon(Icons.add, color: context.palette.primary, size: 40),
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
              color: context.palette.contentPrimary,
            ),
          ),
          Text(
            context.loc.partner_addPartner,
            style: VpWidgets.googleFont(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: context.palette.primary.withValues(alpha: 0.7),
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
              color: context.palette.contentTertiary,
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
                AnsiLogger.auth('Accepting invitation ${invite.id}...',
                    tag: 'PartnerScreen');
                final success =
                    await context.read<AuthState>().acceptInvitation(invite.id);
                AnsiLogger.auth('Acceptance success: $success',
                    tag: 'PartnerScreen');

                if (success && mounted) {
                  if (mounted) {
                    await context.read<PartnerState>().fetchPartnership();
                  }
                  if (mounted) {
                    await context.read<ProfileState>().loadProfile(force: true);
                  }
                  if (mounted) {
                    unawaited(Navigator.pushReplacementNamed(
                      context,
                      AppRoutes.mainShell,
                    ));
                  }
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

  Widget _buildInviteByEmailButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      child: Column(
        children: [
          Icon(Icons.person_add_alt_1_rounded,
              color: context.palette.primary, size: 22),
          TextButton(
            onPressed: () => DialogUtils.showPartnerInviteEmail(context),
            child: Text(
              context.loc.partner_inviteEmailPrompt,
              textAlign: TextAlign.center,
              style: VpWidgets.googleFont(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.palette.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYourCodeCard(String code) {
    return VPCard(
      margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      padding: const EdgeInsets.all(20),
      borderColor: context.palette.primary.withValues(alpha: 0.3),
      shadowColor: context.palette.primary.withValues(alpha: 0.1),
      child: Column(
        children: [
          Text(
            context.loc.partner_personalCodeTitle,
            style: VpWidgets.googleFont(
              color: context.palette.contentTertiary,
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
                  color: context.palette.contentPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: code)));
                  ErrorHandler.showSnackBar(
                      context, context.loc.partner_codeCopied);
                },
                icon: Icon(Icons.copy_rounded,
                    color: context.palette.primary, size: 24),
                style: IconButton.styleFrom(
                  backgroundColor: context.palette.primary.withValues(alpha: 0.1),
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
              color: context.palette.contentDisabled,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
