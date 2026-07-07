import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:justus/all_imports.dart';

class RealtimeSyncService with WidgetsBindingObserver {
  RealtimeSyncService({
    required AuthState authState,
    required MoodState moodState,
    required HomepageState homepageState,
    required PartnerState partnerState,
    required BucketState bucketState,
    required GameState gameState,
    required DriveState driveState,
    sb.SupabaseClient? client,
  })  : _authState = authState,
        _moodState = moodState,
        _homepageState = homepageState,
        _partnerState = partnerState,
        _bucketState = bucketState,
        _gameState = gameState,
        _driveState = driveState,
        _client = client ?? SupabaseService().client;

  final AuthState _authState;
  final MoodState _moodState;
  final HomepageState _homepageState;
  final PartnerState _partnerState;
  final BucketState _bucketState;
  final GameState _gameState;
  final DriveState _driveState;
  final sb.SupabaseClient _client;

  sb.RealtimeChannel? _channel;
  StreamSubscription<dynamic>? _authSubscription;
  Timer? _reconnectTimer;
  Timer? _moodRefreshTimer;
  Timer? _partnershipRefreshTimer;
  Timer? _missYouRefreshTimer;
  Timer? _bucketRefreshTimer;
  Timer? _gameRefreshTimer;
  Timer? _driveRefreshTimer;

  bool _started = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _subscribing = false;
  bool _suppressProcessing = false;
  int _generation = 0;
  int? _userId;
  int? _partnerId;
  int? _partnershipId;

  final Queue<String> _recentEventKeys = Queue<String>();
  final Set<String> _recentEventKeySet = <String>{};

  void suppress() {
    AnsiLogger.realtime('suppress() - pausing event processing');
    _suppressProcessing = true;
  }

  void resume({bool refresh = true}) {
    _suppressProcessing = false;
    AnsiLogger.realtime(
        'resume() - resumed event processing, refresh=$refresh');
    if (refresh) {
      unawaited(_refreshAll());
    }
  }

  Future<void> refreshChannel() async {
    AnsiLogger.realtime(
        'refreshChannel() - replacing channel to drop stale events');
    await _unsubscribe();
    if (!_disposed && _foreground && _userId != null) {
      await _subscribe(refreshAfterSubscribe: true);
    }
  }

  void start() {
    if (_started || _disposed) return;

    _started = true;
    AnsiLogger.realtime('start() - service started, userId=$_userId');
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = _client.auth.onAuthStateChange.listen((authState) {
      AnsiLogger.realtime(
          'auth state changed: event=${authState.event} foreground=$_foreground userId=$_userId');

      // Token refresh is handled internally by Supabase; just update the
      // JWT on the existing Realtime connection without disconnecting.
      if (authState.event == sb.AuthChangeEvent.tokenRefreshed) {
        final token = authState.session?.accessToken;
        if (token != null) {
          AnsiLogger.realtime('token refreshed -> realtime.setAuth()');
          unawaited(_client.realtime.setAuth(token));
        }
        return;
      }

      if (_foreground && _userId != null) {
        _scheduleReconnect();
      }
    });
  }

  void configure({
    required int? userId,
    required int? partnerId,
    required int? partnershipId,
  }) {
    if (_disposed) return;

    final changed = _userId != userId ||
        _partnerId != partnerId ||
        _partnershipId != partnershipId;
    AnsiLogger.realtime(
        'configure() - userId=$userId partnerId=$partnerId partnershipId=$partnershipId changed=$changed foreground=$_foreground');
    _userId = userId;
    _partnerId = partnerId;
    _partnershipId = partnershipId;

    if (userId == null || partnershipId == null) {
      AnsiLogger.realtime(
          'configure() - userId=$userId partnershipId=$partnershipId, deferring subscribe');
      unawaited(_unsubscribe());
      return;
    }

    if (changed && _foreground) {
      _scheduleReconnect();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;

    AnsiLogger.realtime(
        'lifecycle state=$state foreground=$_foreground userId=$_userId');

    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        if (_userId != null) {
          _scheduleReconnect(refreshAfterSubscribe: true);
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _foreground = false;
        unawaited(_unsubscribe());
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _scheduleReconnect({bool refreshAfterSubscribe = false}) {
    if (_disposed || !_foreground || _userId == null || _subscribing) return;

    AnsiLogger.realtime(
        '_scheduleReconnect() - refreshAfterSubscribe=$refreshAfterSubscribe');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(milliseconds: 250), () {
      AnsiLogger.realtime(
          '_scheduleReconnect() - timer fired, calling _subscribe');
      unawaited(_subscribe(refreshAfterSubscribe: refreshAfterSubscribe));
    });
  }

  Future<void> _subscribe({required bool refreshAfterSubscribe}) async {
    if (_disposed || _subscribing || !_foreground || _userId == null) {
      AnsiLogger.realtime(
          '_subscribe() - SKIP: disposed=$_disposed subscribing=$_subscribing foreground=$_foreground userId=$_userId');
      return;
    }

    _subscribing = true;
    _suppressProcessing = false;
    AnsiLogger.realtime(
        '_subscribe() - subscribing generation=${_generation + 1} userId=$_userId refreshAfterSubscribe=$refreshAfterSubscribe');
    try {
      await _unsubscribe();
      if (_disposed || !_foreground || _userId == null) return;

      _generation += 1;
      final channel = _client
          .channel('justus-sync-$_userId-$_generation')
          .onPostgresChanges(
            event: sb.PostgresChangeEvent.all,
            schema: 'public',
            table: 'moods',
            callback: _handleMoodPayload,
          )
          .onPostgresChanges(
            event: sb.PostgresChangeEvent.all,
            schema: 'public',
            table: 'partnerships',
            callback: _handlePartnershipPayload,
          )
          .onPostgresChanges(
            event: sb.PostgresChangeEvent.all,
            schema: 'public',
            table: 'missyou',
            callback: _handleMissYouPayload,
          )
          .onPostgresChanges(
            event: sb.PostgresChangeEvent.all,
            schema: 'public',
            table: 'bucket_items',
            callback: _handleBucketPayload,
          )
          .onPostgresChanges(
            event: sb.PostgresChangeEvent.all,
            schema: 'public',
            table: 'game_questions',
            callback: _handleGamePayload,
          )
          .onPostgresChanges(
            event: sb.PostgresChangeEvent.all,
            schema: 'public',
            table: 'game_answers',
            callback: _handleGamePayload,
          )
          .onPostgresChanges(
            event: sb.PostgresChangeEvent.all,
            schema: 'public',
            table: 'drive_items',
            callback: _handleDrivePayload,
          )
          .onPostgresChanges(
            event: sb.PostgresChangeEvent.all,
            schema: 'public',
            table: 'drive_item_reactions',
            callback: _handleDrivePayload,
          );

      _channel = channel;
      final int subscribedGeneration = _generation;
      channel.subscribe((status, error) {
        if (_disposed) return;

        if (subscribedGeneration != _generation) {
          AnsiLogger.realtime(
              'channel status=$status (stale gen=$subscribedGeneration, current=$_generation) - ignoring');
          return;
        }

        AnsiLogger.realtime(
            'channel status=$status${error != null ? ' error=$error' : ''}');

        if (status == sb.RealtimeSubscribeStatus.subscribed) {
          if (refreshAfterSubscribe) {
            unawaited(_refreshAll());
          }
          return;
        }

        if (status == sb.RealtimeSubscribeStatus.closed ||
            status == sb.RealtimeSubscribeStatus.channelError ||
            status == sb.RealtimeSubscribeStatus.timedOut) {
          if (error != null) {
            AnsiLogger.error('channel status $status: $error',
                tag: 'RealtimeSync');
          }
          _scheduleReconnect();
        }
      });
    } finally {
      _subscribing = false;
    }
  }

  Future<void> _unsubscribe() async {
    _reconnectTimer?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel == null) {
      AnsiLogger.realtime('_unsubscribe() - no active channel');
      return;
    }

    AnsiLogger.realtime('_unsubscribe() - removing channel');
    try {
      await _client.removeChannel(channel);
      AnsiLogger.realtime('_unsubscribe() - channel removed');
    } catch (e) {
      AnsiLogger.error('removeChannel failed: $e', tag: 'RealtimeSync');
    }
  }

  void _handleMoodPayload(sb.PostgresChangePayload payload) {
    AnsiLogger.realtime(
        '_handleMoodPayload - table=${payload.table} eventType=${payload.eventType.name}');
    if (_suppressProcessing) return;
    if (!_isRelevantMood(payload) || !_markSeen(payload)) return;

    final changedUserId = _rowUserId(_currentRecord(payload), 'user_id');

    _moodRefreshTimer?.cancel();
    _moodRefreshTimer = Timer(const Duration(milliseconds: 120), () {
      AnsiLogger.realtime(
          '_handleMoodPayload -> refreshFromRealtime(changedUserId=$changedUserId)');
      unawaited(_moodState.refreshFromRealtime(changedUserId: changedUserId));
    });
  }

  void _handlePartnershipPayload(sb.PostgresChangePayload payload) {
    AnsiLogger.realtime(
        '_handlePartnershipPayload - table=${payload.table} eventType=${payload.eventType.name}');
    if (_suppressProcessing) return;
    if (!_isRelevantPartnership(payload) || !_markSeen(payload)) return;

    _partnershipRefreshTimer?.cancel();
    _partnershipRefreshTimer = Timer(const Duration(milliseconds: 150), () {
      AnsiLogger.realtime('_handlePartnershipPayload -> refreshFromRealtime()');
      BaseRepository.clearPartnershipCache();
      unawaited(Future.wait([
        _partnerState.refreshFromRealtime(),
        _authState.refreshPartnershipFromRealtime(),
      ]));
    });
  }

  void _handleMissYouPayload(sb.PostgresChangePayload payload) {
    AnsiLogger.realtime(
        '_handleMissYouPayload - table=${payload.table} eventType=${payload.eventType.name}');
    if (_suppressProcessing) return;
    if (!_isRelevantMissYou(payload) || !_markSeen(payload)) return;

    _homepageState.addMissYou();
  }

  void _handleBucketPayload(sb.PostgresChangePayload payload) {
    AnsiLogger.realtime(
        '_handleBucketPayload - table=${payload.table} eventType=${payload.eventType.name}');
    if (_suppressProcessing) return;
    if (!_isPartnershipRecord(payload) || !_markSeen(payload)) return;

    AnsiLogger.realtime('_handleBucketPayload -> applyRealtimeEvent()');
    unawaited(_bucketState.applyRealtimeEvent(
      eventType: payload.eventType.name,
      newRecord: payload.newRecord,
      oldRecord: payload.oldRecord,
    ));
  }

  void _handleGamePayload(sb.PostgresChangePayload payload) {
    AnsiLogger.realtime(
        '_handleGamePayload - table=${payload.table} eventType=${payload.eventType.name}');
    if (_suppressProcessing) return;
    if (!_isRelevantGame(payload) || !_markSeen(payload)) return;

    _gameRefreshTimer?.cancel();
    _gameRefreshTimer = Timer(const Duration(milliseconds: 150), () {
      final table = payload.table;
      final eventType = payload.eventType.name;
      final newRecord = payload.newRecord;

      if (table == 'game_questions' && eventType == 'update') {
        AnsiLogger.realtime('_handleGamePayload -> handleQuestionUpdate()');
        unawaited(_gameState.handleQuestionUpdate(newRecord));
      } else if (table == 'game_questions' && eventType == 'delete') {
        AnsiLogger.realtime('_handleGamePayload -> handleQuestionDelete()');
        unawaited(_gameState.handleQuestionDelete(payload.oldRecord));
      } else if (table == 'game_answers' && eventType == 'insert') {
        AnsiLogger.realtime('_handleGamePayload -> handleAnswerInsert()');
        unawaited(_gameState.handleAnswerInsert(newRecord));
      } else if (table == 'game_answers' && eventType == 'update') {
        AnsiLogger.realtime('_handleGamePayload -> handleAnswerUpdate()');
        unawaited(_gameState.handleAnswerUpdate(newRecord));
      } else if (table == 'game_answers' && eventType == 'delete') {
        AnsiLogger.realtime('_handleGamePayload -> handleAnswerDelete()');
        unawaited(_gameState.handleAnswerDelete(payload.oldRecord));
      }
    });
  }

  void _handleDrivePayload(sb.PostgresChangePayload payload) {
    AnsiLogger.realtime(
        '_handleDrivePayload - table=${payload.table} eventType=${payload.eventType.name}');
    if (_suppressProcessing) return;
    if (!_isRelevantDrive(payload) || !_markSeen(payload)) return;

    _driveRefreshTimer?.cancel();
    _driveRefreshTimer = Timer(const Duration(milliseconds: 150), () {
      AnsiLogger.realtime('_handleDrivePayload -> refreshFromRealtime()');
      unawaited(_driveState.refreshFromRealtime());
    });
  }

  bool _isRelevantMood(sb.PostgresChangePayload payload) {
    final userId = _rowUserId(_currentRecord(payload), 'user_id');
    if (userId == null) return false;

    return userId == _userId || userId == _partnerId;
  }

  bool _isRelevantPartnership(sb.PostgresChangePayload payload) {
    final row = _currentRecord(payload);
    final userIds = <int?>[
      _rowUserId(row, 'user_id_1'),
      _rowUserId(row, 'user_id_2'),
      _rowUserId(row, 'user_id_a'),
      _rowUserId(row, 'user_id_b'),
    ];

    return userIds.any((id) => id != null && id == _userId);
  }

  bool _isRelevantMissYou(sb.PostgresChangePayload payload) {
    return _isPartnershipRecord(payload);
  }

  bool _isPartnershipRecord(sb.PostgresChangePayload payload) {
    final partnershipId = _partnershipId;
    if (partnershipId == null) return true;

    final eventPartnershipId =
        _rowInt(_currentRecord(payload), 'partnership_id');

    return eventPartnershipId == null || eventPartnershipId == partnershipId;
  }

  bool _isRelevantGame(sb.PostgresChangePayload payload) {
    final row = _currentRecord(payload);
    if (payload.table == 'game_questions') {
      return _isPartnershipRecord(payload);
    }

    final userId = _rowInt(row, 'user_id');
    if (userId == null) return _partnershipId != null;

    return userId == _userId || userId == _partnerId;
  }

  bool _isRelevantDrive(sb.PostgresChangePayload payload) {
    if (payload.table == 'drive_items') {
      return _isPartnershipRecord(payload);
    }

    final itemId = _rowInt(_currentRecord(payload), 'item_id');
    if (itemId == null) return _partnershipId != null;

    return _driveState.driveItems.any((item) => item.id == itemId);
  }

  Map<String, dynamic> _currentRecord(sb.PostgresChangePayload payload) {
    if (payload.newRecord.isNotEmpty) return payload.newRecord;

    return payload.oldRecord;
  }

  int? _rowUserId(Map<String, dynamic> row, String key) {
    return _rowInt(row, key);
  }

  int? _rowInt(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);

    return null;
  }

  bool _markSeen(sb.PostgresChangePayload payload) {
    final row = _currentRecord(payload);
    final id = row['id'] ?? row['partnership_id'] ?? row['user_id'] ?? '';
    final key = [
      payload.table,
      payload.eventType.name,
      id,
      payload.commitTimestamp.toUtc().toIso8601String(),
    ].join(':');

    if (_recentEventKeySet.contains(key)) {
      AnsiLogger.realtime('_markSeen - DUPLICATE key=$key');
      return false;
    }

    AnsiLogger.realtime('_markSeen - NEW event key=$key');
    _recentEventKeys.addLast(key);
    _recentEventKeySet.add(key);
    const maxTrackedEvents = 80;
    while (_recentEventKeys.length > maxTrackedEvents) {
      _recentEventKeySet.remove(_recentEventKeys.removeFirst());
    }

    return true;
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
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _moodRefreshTimer?.cancel();
    _partnershipRefreshTimer?.cancel();
    _missYouRefreshTimer?.cancel();
    _bucketRefreshTimer?.cancel();
    _gameRefreshTimer?.cancel();
    _driveRefreshTimer?.cancel();
    await _authSubscription?.cancel();
    await _unsubscribe();
  }
}
