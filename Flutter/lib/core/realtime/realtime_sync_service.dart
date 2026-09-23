import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

/// Facade over the Realtime synchronization stack.
///
/// Owns the feature states and coordinates the shared
/// [RealtimeSyncSession] (identity, dedup, row decoding), one
/// [RealtimeSyncConnection] (channel, lifecycle, reconnect, polling fallback),
/// and one per-feature handler that routes its table's payloads into the
/// corresponding state. The 9 `.onPostgresChanges` bindings are declared here
/// so the table -> handler wiring stays in one place.
class RealtimeSyncService {
  RealtimeSyncService({
    required AuthState authState,
    required MoodState moodState,
    required HomepageState homepageState,
    required PartnerState partnerState,
    required BucketState bucketState,
    required GameState gameState,
    required DriveState driveState,
    required ProfileState profileState,
    sb.SupabaseClient? client,
  })  : _authState = authState,
        _moodState = moodState,
        _homepageState = homepageState,
        _partnerState = partnerState,
        _bucketState = bucketState,
        _gameState = gameState,
        _driveState = driveState,
        _profileState = profileState,
        _client = client ?? SupabaseService().client {
    _session = RealtimeSyncSession();
    _moodHandler =
        MoodRealtimeHandler(session: _session, moodState: _moodState);
    _partnershipHandler = RefetchRealtimeHandler(
      session: _session,
      isRelevant: _session.isRelevantPartnership,
      refetch: () async {
        BaseRepository.clearPartnershipCache();
        await Future.wait([
          _partnerState.refreshFromRealtime(),
          _authState.refreshPartnershipFromRealtime(),
        ]);
      },
    );
    _missYouHandler = MissYouRealtimeHandler(
        session: _session, homepageState: _homepageState);
    _bucketHandler =
        BucketRealtimeHandler(session: _session, bucketState: _bucketState);
    _gameHandler =
        GameRealtimeHandler(session: _session, gameState: _gameState);
    _driveHandler = RefetchRealtimeHandler(
      session: _session,
      isRelevant: _session.isRelevantDrive,
      refetch: () => _driveState.refreshFromRealtime(),
    );
    _userProfileHandler = RefetchRealtimeHandler(
      session: _session,
      isRelevant: (payload) =>
          payload.eventType.name == 'update' &&
          _session.isRelevantUserProfile(payload),
      refetch: () async {
        BaseRepository.clearPartnershipCache();
        await Future.wait([
          _profileState.loadProfile(force: true),
          _partnerState.refreshFromRealtime(),
          _authState.refreshPartnershipFromRealtime(),
        ]);
      },
    );
    _connection = RealtimeSyncConnection(
      client: _client,
      session: _session,
      refreshAll: _refreshAll,
      bindings: [
        RealtimeTableBinding(table: 'moods', callback: _moodHandler.handle),
        RealtimeTableBinding(
            table: 'partnerships', callback: _partnershipHandler.handle),
        RealtimeTableBinding(
            table: 'missyou', callback: _missYouHandler.handle),
        RealtimeTableBinding(
            table: 'bucket_items', callback: _bucketHandler.handle),
        RealtimeTableBinding(
            table: 'game_questions', callback: _gameHandler.handle),
        RealtimeTableBinding(
            table: 'game_answers', callback: _gameHandler.handle),
        RealtimeTableBinding(
            table: 'drive_items', callback: _driveHandler.handle),
        RealtimeTableBinding(
            table: 'drive_item_reactions', callback: _driveHandler.handle),
        RealtimeTableBinding(
            table: 'user_profiles', callback: _userProfileHandler.handle),
      ],
    );
  }

  final AuthState _authState;
  final MoodState _moodState;
  final HomepageState _homepageState;
  final PartnerState _partnerState;
  final BucketState _bucketState;
  final GameState _gameState;
  final DriveState _driveState;
  final ProfileState _profileState;
  final sb.SupabaseClient _client;

  late final RealtimeSyncSession _session;
  late final MoodRealtimeHandler _moodHandler;
  late final RefetchRealtimeHandler _partnershipHandler;
  late final MissYouRealtimeHandler _missYouHandler;
  late final BucketRealtimeHandler _bucketHandler;
  late final GameRealtimeHandler _gameHandler;
  late final RefetchRealtimeHandler _driveHandler;
  late final RefetchRealtimeHandler _userProfileHandler;
  late final RealtimeSyncConnection _connection;

  bool _started = false;
  bool _disposed = false;

  void suppress() {
    AnsiLogger.realtime('suppress() - pausing event processing');
    _session.suppressProcessing = true;
    _gameHandler.clear();
    _moodHandler.clear();
  }

  void resume({bool refresh = true}) {
    _session.suppressProcessing = false;
    AnsiLogger.realtime(
        'resume() - resumed event processing, refresh=$refresh');
    if (refresh) {
      unawaited(_refreshAll());
    }
  }

  Future<void> refreshChannel() async {
    AnsiLogger.realtime(
        'refreshChannel() - replacing channel to drop stale events');
    await _connection.unsubscribe();
    if (!_disposed && _connection.foreground && _session.userId != null) {
      await _connection.subscribe(refreshAfterSubscribe: true);
    }
  }

  void start() {
    if (_started || _disposed) return;

    _started = true;
    AnsiLogger.realtime('start() - service started, userId=${_session.userId}');
    _connection.start();
  }

  void configure({
    required int? userId,
    required int? partnerId,
    required int? partnershipId,
  }) {
    if (_disposed) return;

    final changed = _session.userId != userId ||
        _session.partnerId != partnerId ||
        _session.partnershipId != partnershipId;
    _connection.resetRetryCounters();
    _session.userId = userId;
    _session.partnerId = partnerId;
    _session.partnershipId = partnershipId;

    if (!changed) return;

    _gameHandler.clear();
    _moodHandler.clear();

    AnsiLogger.realtime(
        'configure() - CHANGE: userId=$userId partnerId=$partnerId partnershipId=$partnershipId foreground=${_connection.foreground}');

    if (_connection.usePollingFallback) {
      _connection.deactivatePollingFallback();
    }

    if (userId == null || partnershipId == null) {
      AnsiLogger.realtime(
          'configure() - userId=$userId partnershipId=$partnershipId, deferring subscribe');
      unawaited(_connection.unsubscribe());
      return;
    }

    if (_connection.foreground) {
      _connection.scheduleReconnect();
    }
  }

  Future<void> _refreshAll() async {
    AnsiLogger.realtime('_refreshAll() - refreshing all states');
    await Future.wait([
      _moodState.refreshFromRealtime(),
      _homepageState.refreshFromRealtime(),
      _partnerState.refreshFromRealtime(),
      _authState.refreshPartnershipFromRealtime(),
      _bucketState.refreshFromRealtime(),
      _gameState.refreshFromRealtime(),
      _driveState.refreshFromRealtime(),
    ]);
    AnsiLogger.realtime('_refreshAll() - done');
  }

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;
    _gameHandler.clear();
    _moodHandler.clear();
    _partnershipHandler.dispose();
    _driveHandler.dispose();
    _userProfileHandler.dispose();
    await _connection.dispose();
  }
}
