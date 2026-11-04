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
  static const double _connectionAvatarSize = 112;

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
              padding: const EdgeInsets.only(
                top: AppSpacing.xl,
                bottom: AppSpacing.lg,
              ),
              child: Column(
                children: [
                  Text(
                    context.loc.appTitle,
                    style: VpWidgets.googleFont(
                      color: context.palette.primaryVariant,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
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
                          if (cancellation != null &&
                              cancellation.requestedByMe) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg),
                              child: VPCard(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                child: Column(
                                  children: [
                                    Text(
                                      context.loc.partner_cancellationWaiting(
                                          cancellation.partnerDisplayName ??
                                              context.loc.common_partner),
                                      textAlign: TextAlign.center,
                                      style: VpWidgets.googleFont(
                                        color: context.palette.contentSecondary,
                                        fontSize: 14,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    VPButton(
                                      label: context
                                          .loc.partner_restorePartnership,
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
                                          ErrorHandler.handle(res,
                                              context: context);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ] else if (cancellation != null &&
                              !cancellation.requestedByMe) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg),
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
                                title: context.loc
                                    .partner_cancellationRequested(
                                        cancellation.partnerDisplayName ??
                                            context.loc.common_partner),
                                subtitle:
                                    context.loc.partner_cancellationSubtitle,
                                showAccept: true,
                                showReject: true,
                                onAccept: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => VPDialog(
                                      title: context
                                          .loc.partner_cancellationEndTitle,
                                      content: Text(context
                                          .loc.partner_cancellationEndContent),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child:
                                              Text(context.loc.common_cancel),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                context.palette.danger,
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: Text(context
                                              .loc.partner_acceptTooltip),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true || !context.mounted) {
                                    return;
                                  }
                                  final res =
                                      await partnerState.acceptCancellation(
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
                                        context.loc.partner_cancellationEnded);
                                  } else {
                                    await context
                                        .read<AuthState>()
                                        .refreshPartnershipFromRealtime();
                                    await partnerState.fetchPartnership();
                                    if (!context.mounted) return;
                                    if (partnerState.cancellation == null &&
                                        partnerState.partner == null) {
                                      ErrorHandler.showSnackBar(
                                          context,
                                          context
                                              .loc.partner_cancellationEnded);
                                    } else {
                                      ErrorHandler.handle(res,
                                          context: context);
                                    }
                                  }
                                },
                                onReject: () async {
                                  final res =
                                      await partnerState.revertCancellation(
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
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          if (cancellation == null) ...[
                            // Your Personal Code Card
                            if (profileState.userProfile?.partnershipCode !=
                                null)
                              _buildYourCodeCard(
                                  profileState.userProfile!.partnershipCode!),

                            const SizedBox(height: AppSpacing.md),

                            // Existing partner, or the new-connection action.
                            if (partner != null)
                              _buildPartnerCard(
                                name: partner.username,
                                imageUrl: partner.profilePicUrl,
                                onTap: () {
                                  unawaited(Navigator.pushReplacementNamed(
                                    context,
                                    AppRoutes.mainShell,
                                  ));
                                },
                              )
                            else if (sentInvitations.isEmpty)
                              _buildAddPartnerCard(onTap: () {
                                DialogUtils.showPartnerInvite(context);
                              }),

                            if (receivedInvitations.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.md),
                              _buildInvitationsList(
                                  context.loc.partner_receivedRequests,
                                  receivedInvitations,
                                  isReceived: true),
                            ],

                            if (sentInvitations.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.md),
                              _buildInvitationsList(
                                  context.loc.partner_sentRequests,
                                  sentInvitations,
                                  isReceived: false),
                            ] else if (receivedInvitations.isEmpty &&
                                kDebugMode) ...[
                              const SizedBox(height: AppSpacing.xl),
                              Text(
                                context.loc.partner_noPendingInvites,
                                textAlign: TextAlign.center,
                                style: VpWidgets.googleFont(
                                  color: context.palette.contentTertiary,
                                  fontSize: 12,
                                ),
                              ),
                            ],

                            // Invite a partner who has no JustUs account yet.
                            if (partner == null) ...[
                              const SizedBox(height: AppSpacing.md),
                              _buildInviteByEmailButton(),
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
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: TextButton.icon(
                onPressed: () {
                  LogoutUtils.showLogoutDialog(
                      context, () => LogoutUtils.performLogout(context));
                },
                icon: Icon(Icons.logout_rounded,
                    size: 20, color: context.palette.contentSecondary),
                label: Text(
                  context.loc.partner_logout,
                  style: VpWidgets.googleFont(
                    fontWeight: FontWeight.w600,
                    color: context.palette.contentSecondary,
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
    required VoidCallback onTap,
  }) {
    return _buildConnectionCard(
      title: name,
      subtitle: context.loc.partner_connected,
      onTap: onTap,
      avatar: Stack(
        clipBehavior: Clip.none,
        children: [
          VPAvatar(
            imageUrl: imageUrl,
            size: _connectionAvatarSize,
            borderColor: context.palette.primary,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: context.palette.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  VpWidgets.boxShadow(context, blurRadius: 4),
                ],
              ),
              child: Icon(Icons.favorite,
                  size: 16, color: context.palette.onPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddPartnerCard({required VoidCallback onTap}) {
    return _buildConnectionCard(
      title: context.loc.partner_newConnection,
      subtitle: context.loc.partner_addPartner,
      onTap: onTap,
      avatar: Container(
        width: _connectionAvatarSize,
        height: _connectionAvatarSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.palette.surface,
          border: Border.all(
            color: context.palette.primary.withValues(alpha: 0.5),
            width: 2,
          ),
          boxShadow: [
            VpWidgets.boxShadow(
              context,
              color: context.palette.primary.withValues(alpha: 0.15),
            ),
          ],
        ),
        child: Icon(
          Icons.add_rounded,
          size: 40,
          color: context.palette.primaryVariant,
        ),
      ),
    );
  }

  Widget _buildConnectionCard({
    required Widget avatar,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 180,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              avatar,
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: VpWidgets.googleFont(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: context.palette.contentPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: VpWidgets.googleFont(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: context.palette.primaryVariant,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInvitationsList(
      String title, List<PartnershipInvitation> invitations,
      {required bool isReceived}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VPSectionHeader(title: title),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: invitations.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
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
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  Widget _buildInviteByEmailButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: TextButton.icon(
        onPressed: () => DialogUtils.showPartnerInviteEmail(context),
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
        label: Text(
          context.loc.partner_inviteEmailPrompt,
          textAlign: TextAlign.center,
          style: VpWidgets.googleFont(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: TextButton.styleFrom(
          foregroundColor: context.palette.primaryVariant,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
        ),
      ),
    );
  }

  Widget _buildYourCodeCard(String code) {
    return VPCard(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderColor: context.palette.primary.withValues(alpha: 0.3),
      shadowColor: context.palette.primary.withValues(alpha: 0.1),
      child: Column(
        children: [
          Text(
            context.loc.partner_personalCodeTitle,
            textAlign: TextAlign.center,
            style: VpWidgets.googleFont(
              color: context.palette.contentTertiary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    code,
                    style: VpWidgets.googleFont(
                      color: context.palette.contentPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              IconButton(
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: code)));
                  ErrorHandler.showSnackBar(
                      context, context.loc.partner_codeCopied);
                },
                icon: Icon(Icons.copy_rounded,
                    color: context.palette.primaryVariant, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor:
                      context.palette.primary.withValues(alpha: 0.1),
                  padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.loc.partner_personalCodeSubtitle,
            textAlign: TextAlign.center,
            style: VpWidgets.googleFont(
              color: context.palette.contentTertiary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
