import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

import 'test_helpers/mock_secure_storage.dart';
import 'test_helpers/realtime_payload_factory.dart';

class _MockSupabaseClient extends Mock implements sb.SupabaseClient {}

class _MockRealtimeChannel extends Mock implements sb.RealtimeChannel {}

class _MockRealtimeClient extends Mock implements sb.RealtimeClient {}

class _MockGoTrueClient extends Mock implements sb.GoTrueClient {}

class _MockAuthState extends Mock implements AuthState {}

class _MockPartnerState extends Mock implements PartnerState {}

class _MockProfileState extends Mock implements ProfileState {}

class _MockDriveState extends Mock implements DriveState {}

class _MockGameState extends Mock implements GameState {}

class _MockBucketState extends Mock implements BucketState {}

class _MockHomepageState extends Mock implements HomepageState {}

/// Real `MoodRepository` without a network: the counters prove which refetch
/// path the pipeline chose, and the returned values prove the state really
/// changed.
class _FakeMoodRepository extends MoodRepository {
  final String partnerEmoji = 'partner-emoji';
  int fetchPartnerMoodCalls = 0;
  int fetchMyMoodCalls = 0;
  int fetchRecentCoupleEmojisCalls = 0;
  int fetchTimelineCalls = 0;

  @override
  Future<ResultWrapper<MoodResponse>> fetchPartnerMood() async {
    fetchPartnerMoodCalls++;
    return Success(MoodResponse(
      success: true,
      emoji: partnerEmoji,
      createdAt: '2026-05-02T00:00:00.000Z',
    ));
  }

  @override
  Future<ResultWrapper<MoodResponse>> fetchMyMood() async {
    fetchMyMoodCalls++;
    return Success(MoodResponse(success: true, emoji: 'my-emoji'));
  }

  @override
  Future<ResultWrapper<List<String>>> fetchRecentCoupleEmojis() async {
    fetchRecentCoupleEmojisCalls++;
    return const Success<List<String>>([]);
  }

  @override
  Future<ResultWrapper<List<MoodEntry>>> fetchTimeline({
    int limit = 4,
    int offset = 0,
  }) async {
    fetchTimelineCalls++;
    return const Success<List<MoodEntry>>([]);
  }
}

/// Long enough to clear the 120 ms mood batch and the 150 ms refetch debounce.
const _afterDebounce = Duration(milliseconds: 400);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
        _MockRealtimeChannel() as sb.RealtimeChannel);
  });

  late _MockSupabaseClient client;
  late _MockRealtimeChannel channel;
  late _MockRealtimeClient realtimeClient;
  late _MockGoTrueClient goTrue;
  late StreamController<sb.AuthState> authChanges;
  late Map<String, void Function(sb.PostgresChangePayload)> callbacks;
  late void Function(sb.RealtimeSubscribeStatus, Object?)? statusCallback;

  late RealtimeSyncService service;
  late _FakeMoodRepository moodRepository;
  late MoodState moodState;
  late _MockGameState game;
  late _MockBucketState bucket;
  late _MockHomepageState home;

  /// Configure the identity, then subscribe without waiting for the reconnect
  /// backoff timer (`refreshChannel` cancels it and subscribes right away).
  Future<void> connect() async {
    service.configure(userId: 42, partnerId: 77, partnershipId: 9001);
    await service.refreshChannel();
    statusCallback?.call(sb.RealtimeSubscribeStatus.subscribed, null);
    await pumpEventQueue();
  }

  void emit(
    String table,
    sb.PostgresChangeEvent eventType, {
    Map<String, dynamic> newRecord = const {},
    Map<String, dynamic> oldRecord = const {},
    DateTime? at,
  }) {
    callbacks[table]!.call(realtimePayload(
      table: table,
      eventType: eventType,
      newRecord: newRecord,
      oldRecord: oldRecord,
      commitTimestamp: at ?? DateTime.utc(2026),
    ));
  }

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();

    callbacks = {};
    statusCallback = null;

    channel = _MockRealtimeChannel();
    // `event: all` is matched literally on purpose: every table must be
    // subscribed for all four event types.
    when(() => channel.onPostgresChanges(
          event: sb.PostgresChangeEvent.all,
          schema: any(named: 'schema'),
          table: any(named: 'table'),
          callback: any(named: 'callback'),
        )).thenAnswer((invocation) {
      final named = invocation.namedArguments;
      callbacks[named[#table] as String] =
          named[#callback] as void Function(sb.PostgresChangePayload);
      return channel;
    });
    when(() => channel.subscribe(any())).thenAnswer((invocation) {
      statusCallback = invocation.positionalArguments[0]
          as void Function(sb.RealtimeSubscribeStatus, Object?)?;
      return channel;
    });

    authChanges = StreamController<sb.AuthState>.broadcast();
    goTrue = _MockGoTrueClient();
    when(() => goTrue.onAuthStateChange).thenAnswer((_) => authChanges.stream);

    realtimeClient = _MockRealtimeClient();
    when(() => realtimeClient.setAuth(any())).thenAnswer((_) async {});

    client = _MockSupabaseClient();
    when(() => client.channel(any()))
        .thenReturn(channel);
    when(() => client.realtime).thenReturn(realtimeClient);
    when(() => client.auth).thenReturn(goTrue);
    when(() => client.removeChannel(any())).thenAnswer((_) async => 'removed');

    moodRepository = _FakeMoodRepository();
    moodState = MoodState(repository: moodRepository);

    game = _MockGameState();
    when(() => game.handleQuestionInsert(any())).thenAnswer((_) async {});
    when(() => game.handleQuestionUpdate(any())).thenAnswer((_) async {});
    when(() => game.handleAnswerInsert(any())).thenAnswer((_) async {});
    when(() => game.handleAnswerUpdate(any())).thenAnswer((_) async {});
    when(() => game.handleAnswerDelete(any())).thenAnswer((_) async {});
    when(() => game.handleQuestionDelete(any())).thenAnswer((_) async {});

    bucket = _MockBucketState();
    when(() => bucket.applyRealtimeEvent(
          eventType: any(named: 'eventType'),
          newRecord: any(named: 'newRecord'),
          oldRecord: any(named: 'oldRecord'),
        )).thenAnswer((_) async {});

    home = _MockHomepageState();
    when(() => home.addMissYou(rowId: any(named: 'rowId'))).thenReturn(null);
    when(() => home.refreshFromRealtime()).thenAnswer((_) async {});

    // Every state that takes part in `refreshAll()` (fired once the channel
    // reports `subscribed`) must answer, otherwise the refresh throws.
    final partnerState = _MockPartnerState();
    when(partnerState.refreshFromRealtime).thenAnswer((_) async {});
    final authState = _MockAuthState();
    when(authState.refreshPartnershipFromRealtime).thenAnswer((_) async {});
    when(() => bucket.refreshFromRealtime()).thenAnswer((_) async {});
    when(() => game.refreshFromRealtime()).thenAnswer((_) async {});
    final driveState = _MockDriveState();
    when(driveState.refreshFromRealtime).thenAnswer((_) async {});
    final profileState = _MockProfileState();
    when(() => profileState.loadProfile(force: any(named: 'force')))
        .thenAnswer((_) async {});

    service = RealtimeSyncService(
      authState: authState,
      moodState: moodState,
      homepageState: home,
      partnerState: partnerState,
      bucketState: bucket,
      gameState: game,
      driveState: driveState,
      profileState: profileState,
      client: client,
    );
  });

  tearDown(() async {
    await service.dispose();
    await authChanges.close();
    moodState.clear();
  });

  group('RealtimeSyncService binding wiring', () {
    test('the first channel binds all nine tables to their handlers', () async {
      await connect();

      expect(callbacks.keys.toSet(), {
        'moods',
        'partnerships',
        'missyou',
        'bucket_items',
        'game_questions',
        'game_answers',
        'drive_items',
        'drive_item_reactions',
        'user_profiles',
      });
      verify(() => client.channel('justus-sync-42-1'))
          .called(1);
    });

    test('an identity change opens a new channel instead of reusing it',
        () async {
      await connect();

      service.configure(userId: 42, partnerId: 77, partnershipId: 4242);
      await service.refreshChannel();

      verify(() => client.channel('justus-sync-42-2'))
          .called(1);
      // The stale generation must be removed before resubscribing.
      verify(() => client.removeChannel(channel)).called(1);
    });
  });

  group('RealtimeSyncService payload pipeline (channel -> handler -> state)',
      () {
    test('a partner mood insert refreshes the real MoodState', () async {
      await connect();
      // The connect-time refresh already refetched everything once: the event
      // must add exactly one partner refresh of its own.
      final partnerCallsBefore = moodRepository.fetchPartnerMoodCalls;
      final myCallsBefore = moodRepository.fetchMyMoodCalls;

      emit('moods', sb.PostgresChangeEvent.insert,
          newRecord: {'id': 1, 'user_id': 77, 'emoji_char': 'partner-emoji'});
      await Future<void>.delayed(_afterDebounce);

      expect(moodRepository.fetchPartnerMoodCalls, partnerCallsBefore + 1);
      expect(moodState.partnerMood, 'partner-emoji',
          reason: 'the real state must hold the fetched value');
      expect(moodRepository.fetchMyMoodCalls, myCallsBefore,
          reason: "a partner's change must not refetch our own mood");
    });

    test('a burst of partner mood inserts coalesces into one refetch', () async {
      await connect();
      final partnerCallsBefore = moodRepository.fetchPartnerMoodCalls;

      for (var i = 1; i <= 3; i++) {
        emit('moods', sb.PostgresChangeEvent.insert,
            newRecord: {'id': i, 'user_id': 77},
            at: DateTime.utc(2026, 1, i));
      }
      await Future<void>.delayed(_afterDebounce);

      expect(moodRepository.fetchPartnerMoodCalls, partnerCallsBefore + 1,
          reason: 'the trailing-edge batch must collapse the burst');
    });

    test('a game_questions insert reaches the game state without a debounce',
        () async {
      await connect();

      emit('game_questions', sb.PostgresChangeEvent.insert,
          newRecord: {'id': 5, 'partnership_id': 9001});
      await pumpEventQueue();

      verify(() => game.handleQuestionInsert(any())).called(1);
    });

    test('a replayed missyou insert reaches the counter once', () async {
      await connect();

      emit('missyou', sb.PostgresChangeEvent.insert,
          newRecord: {'id': 7, 'partnership_id': 9001, 'user_id': 77});
      emit('missyou', sb.PostgresChangeEvent.insert,
          newRecord: {'id': 7, 'partnership_id': 9001, 'user_id': 77});
      await pumpEventQueue();

      verify(() => home.addMissYou(rowId: 7)).called(1);
    });

    test("another partnership's bucket row never reaches the state", () async {
      await connect();

      emit('bucket_items', sb.PostgresChangeEvent.insert,
          newRecord: {'id': 3, 'partnership_id': 4});
      await pumpEventQueue();

      verifyNever(() => bucket.applyRealtimeEvent(
            eventType: any(named: 'eventType'),
            newRecord: any(named: 'newRecord'),
            oldRecord: any(named: 'oldRecord'),
          ));
    });
  });

  group('RealtimeSyncService connection lifecycle', () {
    test('a token refresh updates the JWT without resubscribing', () async {
      service.start();
      await connect();

      authChanges.add(sb.AuthState(
        sb.AuthChangeEvent.tokenRefreshed,
        sb.Session(
          accessToken: 'jwt-2',
          refreshToken: 'refresh-2',
          tokenType: 'bearer',
          user: const sb.User(
            id: '42',
            appMetadata: {},
            userMetadata: {},
            aud: '',
            createdAt: '2026-05-01T00:00:00.000Z',
          ),
        ),
      ));
      await pumpEventQueue();

      verify(() => realtimeClient.setAuth('jwt-2')).called(1);
      verify(() => client.channel(any()))
          .called(1);
      verifyNever(() => client.removeChannel(any()));
    });

    test('dispose removes the channel and stops the auth listener', () async {
      service.start();
      await connect();

      await service.dispose();

      verify(() => client.removeChannel(channel)).called(1);
      verifyNever(() => realtimeClient.setAuth(any()));
    });
  });
}