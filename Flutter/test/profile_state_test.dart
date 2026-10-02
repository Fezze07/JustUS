import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_path_provider.dart';
import 'test_helpers/mock_secure_storage.dart';

class FakeUserRepository extends UserRepository {
  ResultWrapper<void> nameResult = const Success<void>(null);
  String? lastName;
  int nameCalls = 0;
  String uploadedPicUrl = 'profile/1/new-pic.jpg';
  int uploadCalls = 0;
  String? profilePicUrl;

  @override
  Future<ResultWrapper<void>> updateDisplayName(String displayName) async {
    nameCalls += 1;
    lastName = displayName;

    return nameResult;
  }

  @override
  Future<ResultWrapper<User>> fetchProfile() async {
    return Success(User(
      id: 1,
      email: 'user@example.com',
      displayName: 'Alex',
      profilePicUrl: profilePicUrl,
    ));
  }

  @override
  Future<ResultWrapper<String>> uploadProfilePicture(File file) async {
    uploadCalls += 1;

    return Success(uploadedPicUrl);
  }

  @override
  Future<ResultWrapper<void>> debugWipeData() async {
    return const Success<void>(null);
  }
}

class FakePartnerRepository extends PartnershipRepository {
  @override
  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    return Success(PartnershipResponse(success: true));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    installMockSecureStorage();
  });

  setUp(() {
    StorageService.resetForTest();
    SharedPreferences.setMockInitialValues({});
  });

  test('updateDisplayName persists server-side and updates local caches',
      () async {
    final repo = FakeUserRepository();
    final state = ProfileState(
      userRepo: repo,
      partnershipRepo: FakePartnerRepository(),
    );
    await state.loadProfile(force: true);
    expect(state.userProfile?.username, 'Alex');

    final saved = await state.updateDisplayName('Alexis');

    expect(saved, isTrue);
    expect(repo.nameCalls, 1);
    expect(repo.lastName, 'Alexis');
    expect(state.userProfile?.username, 'Alexis');
    expect((await StorageService.getUserProfile())?.displayName, 'Alexis');
    expect(await StorageService.getUsername(), 'Alexis');
  });

  test('updateDisplayName failure returns false and leaves state unchanged',
      () async {
    final repo = FakeUserRepository()
      ..nameResult = const GenericError(
        message: 'DB error',
        code: 500,
      );
    final state = ProfileState(
      userRepo: repo,
      partnershipRepo: FakePartnerRepository(),
    );
    await state.loadProfile(force: true);

    final saved = await state.updateDisplayName('Marco');

    expect(saved, isFalse);
    expect(state.userProfile?.username, 'Alex');
    expect(await StorageService.getUsername(), isNull);
  });

  test('wipeAppData clears checkpoints, feature caches and profile keys',
      () async {
    installMockPathProvider();
    SharedPreferences.setMockInitialValues({
      'mood_me': 'happy',
      'chk_drive_items': '2026-09-01T00:00:00.000Z',
      'user_profile': '{}',
    });
    StorageService.resetForTest();

    final state = ProfileState(
      userRepo: FakeUserRepository(),
      partnershipRepo: FakePartnerRepository(),
    );

    final wiped = await state.wipeAppData();

    expect(wiped, isTrue);
    expect(await CacheService.getCheckpoint(CacheService.kDriveItems), isNull);
    expect(await StorageService.getMood('me'), isNull);
    expect(await StorageService.getUserProfile(), isNull);
  });

  test('no stored version leaves the avatar URL unversioned', () async {
    final repo = FakeUserRepository()..profilePicUrl = 'profile/1/old-pic.jpg';
    final state = ProfileState(
      userRepo: repo,
      partnershipRepo: FakePartnerRepository(),
    );
    await state.loadProfile(force: true);

    expect(state.profilePicVersion, isNull);
    expect(state.versionedProfilePicUrl, isNot(contains('v=')));
    expect(state.versionedProfilePicUrl,
        contains('filename=profile%2F1%2Fold-pic.jpg'));
  });

  test('uploadProfilePhoto stores a version that busts the avatar cache key',
      () async {
    installMockPathProvider();
    final repo = FakeUserRepository()..profilePicUrl = 'profile/1/old-pic.jpg';
    final state = ProfileState(
      userRepo: repo,
      partnershipRepo: FakePartnerRepository(),
    );
    await state.loadProfile(force: true);

    await state.uploadProfilePhoto('does-not-need-to-exist.jpg');

    expect(repo.uploadCalls, 1);
    expect(state.userProfile?.profilePicUrl, 'profile/1/new-pic.jpg');
    final version = state.profilePicVersion;
    expect(version, isNotNull);
    expect(await StorageService.getProfilePicVersion(), version);
    expect(
      state.versionedProfilePicUrl,
      contains('filename=profile%2F1%2Fnew-pic.jpg&v=$version'),
    );

    final restored = ProfileState(
      userRepo: repo,
      partnershipRepo: FakePartnerRepository(),
    );
    await restored.loadProfile(force: true);

    expect(restored.profilePicVersion, version);
    expect(restored.versionedProfilePicUrl, contains('v=$version'));
  });

  test('clear drops the in-memory profile pic version', () async {
    final repo = FakeUserRepository()..profilePicUrl = 'profile/1/old-pic.jpg';
    final state = ProfileState(
      userRepo: repo,
      partnershipRepo: FakePartnerRepository(),
    );
    await state.loadProfile(force: true);
    await state.uploadProfilePhoto('does-not-need-to-exist.jpg');

    state.clear();

    expect(state.profilePicVersion, isNull);
    expect(state.versionedProfilePicUrl, isNull);
  });
}
