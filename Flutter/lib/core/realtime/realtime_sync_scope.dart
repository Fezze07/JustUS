import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class RealtimeSyncScope extends StatefulWidget {
  const RealtimeSyncScope({super.key, required this.child});

  final Widget child;

  @override
  State<RealtimeSyncScope> createState() => _RealtimeSyncScopeState();
}

class _RealtimeSyncScopeState extends State<RealtimeSyncScope> {
  RealtimeSyncService? _service;
  bool _configureScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_service != null) return;

    final authState = context.read<AuthState>();
    final moodState = context.read<MoodState>();
    final homepageState = context.read<HomepageState>();
    final partnerState = context.read<PartnerState>();
    final bucketState = context.read<BucketState>();
    final gameState = context.read<GameState>();
    final driveState = context.read<DriveState>();
    final profileState = context.read<ProfileState>();

    _service = RealtimeSyncService(
      authState: authState,
      moodState: moodState,
      homepageState: homepageState,
      partnerState: partnerState,
      bucketState: bucketState,
      gameState: gameState,
      driveState: driveState,
      profileState: profileState,
    )..start();

    authState.onClearFeatureStates = () {
      moodState.clear();
      homepageState.clear();
      bucketState.clear();
      gameState.clear();
      driveState.clear();
      profileState.clear();
    };
    AnsiLogger.realtime('RealtimeSyncScope created');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthState, PartnerState>(
      builder: (context, authState, partnerState, child) {
        if (!_configureScheduled) {
          _configureScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _configureScheduled = false;
            if (!mounted) return;

            final resolvedPartnershipId = authState.partnershipId ??
                partnerState.partnershipInfo?.partnershipId;
            AnsiLogger.realtime(
                'configure called - userId=${authState.userId} partnerId=${authState.partnerId ?? partnerState.partnershipInfo?.partner?.id} partnershipId=$resolvedPartnershipId');
            _service?.configure(
              userId: authState.userId,
              partnerId: authState.partnerId ??
                  partnerState.partnershipInfo?.partner?.id,
              partnershipId: resolvedPartnershipId,
            );
          });
        }

        return Provider<RealtimeSyncService>.value(
          value: _service!,
          child: child,
        );
      },
      child: widget.child,
    );
  }

  @override
  void dispose() {
    final service = _service;
    _service = null;
    if (service != null) {
      unawaited(service.dispose());
    }
    super.dispose();
  }
}
