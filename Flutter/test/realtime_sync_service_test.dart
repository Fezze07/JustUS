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
    registerFallbackValue(_MockRealtimeChannel() as sb.RealtimeChannel);
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
  late _MockPartnerState partnerState;
  late _MockAuthState authState;
  late _MockDriveState driveState;

  /// Configure the identity, then subscribe without waiting for the reconnect
  /// backoff timer (`refreshChannel` cancels it and subscribes right away).
  Future<void> connect() async {
    service.configure(userId: 42, partnerId: 77, partnershipId: 9001);
    await service.refreshChannel();
    statusCallback?.call(sb.RealtimeSubscribeStatus.subscribed, null);
    await pumpEventQueue();
  }

  /// Same as [connect], for `testWidgets` where the fake clock only advances
  /// through `tester.pump()` (so `pumpEventQueue()` would never return).
  Future<void> connectWith(WidgetTester tester) async {
    service.configure(userId: 42, partnerId: 77, partnershipId: 9001);
    await service.refreshChannel();
    statusCallback?.call(sb.RealtimeSubscribeStatus.subscribed, null);
    await tester.pump();
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
      statusCallback = invocation.positionalArguments[0] as void Function(
          sb.RealtimeSubscribeStatus, Object?)?;
      return channel;
    });

    authChanges = StreamController<sb.AuthState>.broadcast();
    goTrue = _MockGoTrueClient();
    when(() => goTrue.onAuthStateChange).thenAnswer((_) => authChanges.stream);

    realtimeClient = _MockRealtimeClient();
    when(() => realtimeClient.setAuth(any())).thenAnswer((_) async {});

    client = _MockSupabaseClient();
    when(() => client.channel(any())).thenReturn(channel);
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
    partnerState = _MockPartnerState();
    when(partnerState.refreshFromRealtime).thenAnswer((_) async {});
    authState = _MockAuthState();
    when(authState.refreshPartnershipFromRealtime).thenAnswer((_) async {});
    when(authState.fetchInvitations).thenAnswer((_) async {});
    when(() => bucket.refreshFromRealtime()).thenAnswer((_) async {});
    when(() => game.refreshFromRealtime()).thenAnswer((_) async {});
    driveState = _MockDriveState();
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
      verify(() => client.channel('justus-sync-42-1')).called(1);
    });

    test('an identity change opens a new channel instead of reusing it',
        () async {
      await connect();

      service.configure(userId: 42, partnerId: 77, partnershipId: 4242);
      await service.refreshChannel();

      verify(() => client.channel('justus-sync-42-2')).called(1);
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

    test('a burst of partner mood inserts coalesces into one refetch',
        () async {
      await connect();
      final partnerCallsBefore = moodRepository.fetchPartnerMoodCalls;

      for (var i = 1; i <= 3; i++) {
        emit('moods', sb.PostgresChangeEvent.insert,
            newRecord: {'id': i, 'user_id': 77}, at: DateTime.utc(2026, 1, i));
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

    test('a PK-only partnership DELETE triggers a PartnershipState refresh',
        () async {
      await connect();
      clearInteractions(partnerState);

      emit('partnerships', sb.PostgresChangeEvent.delete,
          oldRecord: {'id': 9001});
      await Future<void>.delayed(_afterDebounce);

      verify(partnerState.refreshFromRealtime).called(1);
    });
  });

  group('RealtimeSyncService connection lifecycle', () {
    test('a token refresh is left to Supabase without resubscribing', () async {
      service.start();
      await connect();

      authChanges.add(const sb.AuthState(
        sb.AuthChangeEvent.tokenRefreshed,
        null,
      ));
      await pumpEventQueue();

      verifyNever(() => realtimeClient.setAuth(any()));
      verify(() => client.channel(any())).called(1);
      verifyNever(() => client.removeChannel(any()));
    });

    testWidgets(
        'signedOut disconnects immediately and stops reconnects and polling',
        (tester) async {
      service.start();
      await connectWith(tester);

      // Three failures activate the 15 s polling fallback before sign-out.
      statusCallback?.call(sb.RealtimeSubscribeStatus.closed, null);
      statusCallback?.call(sb.RealtimeSubscribeStatus.closed, null);
      await tester.pump();

      clearInteractions(partnerState);
      clearInteractions(client);

      authChanges.add(const sb.AuthState(
        sb.AuthChangeEvent.signedOut,
        null,
      ));
      await tester.pump();

      verify(() => client.removeChannel(channel)).called(1);

      await tester.pump(const Duration(seconds: 30));

      verifyNever(() => client.channel(any()));
      verifyNever(() => partnerState.refreshFromRealtime());
    });

    testWidgets(
        'an in-flight subscription cannot create a channel after signedOut',
        (tester) async {
      service.start();
      await connectWith(tester);

      final gate = Completer<String>();
      when(() => client.removeChannel(any())).thenAnswer((_) => gate.future);

      service.configure(userId: 42, partnerId: 77, partnershipId: 4242);
      await tester.pump(const Duration(seconds: 2));

      authChanges.add(const sb.AuthState(
        sb.AuthChangeEvent.signedOut,
        null,
      ));
      await tester.pump();

      gate.complete('removed');
      await tester.pump();

      verify(() => client.channel('justus-sync-42-1')).called(1);
      verifyNever(() => client.channel('justus-sync-42-2'));
    });

    testWidgets('an authenticated configure reconnects after signedOut',
        (tester) async {
      service.start();
      await connectWith(tester);

      authChanges.add(const sb.AuthState(
        sb.AuthChangeEvent.signedOut,
        null,
      ));
      await tester.pump();

      service.configure(userId: null, partnerId: null, partnershipId: null);
      await tester.pump();

      service.configure(userId: 42, partnerId: 77, partnershipId: 9001);
      await service.refreshChannel();
      statusCallback?.call(sb.RealtimeSubscribeStatus.subscribed, null);
      await tester.pump();

      verify(() => client.channel(any())).called(2);
    });

    test('dispose removes the channel and stops the auth listener', () async {
      service.start();
      await connect();

      await service.dispose();

      verify(() => client.removeChannel(channel)).called(1);
      verifyNever(() => realtimeClient.setAuth(any()));
    });
  });

  group('RealtimeSyncService unpaired mode', () {
    Future<void> connectUnpaired() async {
      service.configure(userId: 42, partnerId: null, partnershipId: null);
      await service.refreshChannel();
      statusCallback?.call(sb.RealtimeSubscribeStatus.subscribed, null);
      await pumpEventQueue();
    }

    test('unauthenticated user never creates a Realtime channel', () async {
      service.configure(userId: null, partnerId: null, partnershipId: null);
      await service.refreshChannel();
      await pumpEventQueue();

      verifyNever(() => client.channel(any()));
      expect(callbacks, isEmpty);
    });

    test('unpaired user subscribes exclusively to partnerships', () async {
      await connectUnpaired();

      expect(callbacks.keys.toSet(), {'partnerships'});
      verify(() => client.channel('justus-sync-42-1')).called(1);
    });

    test('unpaired refreshChannel does not fetch couple-specific data',
        () async {
      await connectUnpaired();

      verify(authState.fetchInvitations).called(1);
      verify(partnerState.refreshFromRealtime).called(1);
      verify(authState.refreshPartnershipFromRealtime).called(1);

      expect(moodRepository.fetchPartnerMoodCalls, 0);
      expect(moodRepository.fetchMyMoodCalls, 0);
      verifyNever(() => home.refreshFromRealtime());
      verifyNever(() => bucket.refreshFromRealtime());
      verifyNever(() => game.refreshFromRealtime());
      verifyNever(driveState.refreshFromRealtime);
    });

    test('unpaired partnership INSERT, UPDATE, and PK-only DELETE refresh invitations and coalesce bursts',
        () async {
      await connectUnpaired();
      clearInteractions(authState);
      clearInteractions(partnerState);
      when(authState.fetchInvitations).thenAnswer((_) async {});
      when(authState.refreshPartnershipFromRealtime).thenAnswer((_) async {});
      when(partnerState.refreshFromRealtime).thenAnswer((_) async {});

      emit(
        'partnerships',
        sb.PostgresChangeEvent.insert,
        newRecord: {'id': 501, 'user_id_1': 42, 'user_id_2': 77},
        at: DateTime.utc(2026, 1, 1, 0, 0, 1),
      );
      emit(
        'partnerships',
        sb.PostgresChangeEvent.update,
        newRecord: {'id': 501, 'user_id_1': 42, 'user_id_2': 77},
        at: DateTime.utc(2026, 1, 1, 0, 0, 2),
      );
      emit(
        'partnerships',
        sb.PostgresChangeEvent.delete,
        oldRecord: {'id': 501},
        at: DateTime.utc(2026, 1, 1, 0, 0, 3),
      );

      await Future<void>.delayed(_afterDebounce);

      verify(authState.fetchInvitations).called(1);
      verify(partnerState.refreshFromRealtime).called(1);
      verify(authState.refreshPartnershipFromRealtime).called(1);
    });

    test('AuthState.fetchInvitations ignores stale overlapping responses',
        () async {
      final firstCompleter =
          Completer<ResultWrapper<List<PartnershipInvitation>>>();
      final secondCompleter =
          Completer<ResultWrapper<List<PartnershipInvitation>>>();
      var callCount = 0;

      final repo = _OverlappingInvitationsRepo(() {
        callCount++;
        return callCount == 1 ? firstCompleter.future : secondCompleter.future;
      });
      final realAuth = AuthState(partnershipRepo: repo);
      await realAuth.setLoginData(
        accessToken: 'token',
        user: User(id: 42, displayName: 'me', partnershipCode: 'CODE'),
      );

      final firstFuture = realAuth.fetchInvitations();
      final secondFuture = realAuth.fetchInvitations();

      secondCompleter.complete(Success([
        PartnershipInvitation(
          id: 2,
          status: 'pending',
          createdAt: DateTime.utc(2026),
          partnerId: 88,
          partnerDisplayName: 'newer',
          isReceived: true,
        ),
      ]));
      await secondFuture;

      firstCompleter.complete(Success([
        PartnershipInvitation(
          id: 1,
          status: 'pending',
          createdAt: DateTime.utc(2026),
          partnerId: 77,
          partnerDisplayName: 'older',
          isReceived: true,
        ),
      ]));
      await firstFuture;

      expect(realAuth.receivedInvitations.map((i) => i.id).toList(), [2]);
    });
  });
}

class _OverlappingInvitationsRepo extends PartnershipRepository {
  _OverlappingInvitationsRepo(this._next);

  final Future<ResultWrapper<List<PartnershipInvitation>>> Function() _next;

  @override
  Future<ResultWrapper<List<PartnershipInvitation>>> getPendingInvitations() =>
      _next();
}
