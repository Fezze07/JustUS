import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

/// The add dialog stays open until the write is accepted, so `addItem` must
/// report success/failure and raise the empty-text message itself.
class _FakeBucketRepository extends BucketRepository {
  _FakeBucketRepository({this.result = const Success<void>(null)});

  final ResultWrapper<void> result;
  final List<String> addedTexts = [];

  @override
  Future<ResultWrapper<void>> addBucketItem(
      String text, String? category) async {
    addedTexts.add(text);

    return result;
  }

  @override
  Future<ResultWrapper<void>> toggleBucketItem(int id, bool done) async =>
      result;

  @override
  Future<ResultWrapper<void>> deleteBucketItem(int id) async => result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  test('empty text is rejected with a message and never hits the repository',
      () async {
    final repo = _FakeBucketRepository();
    final state = BucketState(repository: repo);

    final added = await state.addItem('   ', 'Personal');

    expect(added, isFalse);
    expect(repo.addedTexts, isEmpty);
    expect(state.message, LanguageHelper.appLoc.bucket_enterText);

    state.clear();
  });

  test('a successful write returns true and confirms the addition', () async {
    final repo = _FakeBucketRepository();
    final state = BucketState(repository: repo);

    final added = await state.addItem('first', 'Personal');

    expect(added, isTrue);
    expect(repo.addedTexts, ['first']);
    expect(state.message, LanguageHelper.appLoc.bucket_added);

    state.clear();
  });

  test('toggling done confirms the new state, undone says so too', () async {
    final state = BucketState(repository: _FakeBucketRepository());

    await state.toggleDone(1, true);
    expect(state.message, LanguageHelper.appLoc.bucket_markedDone);

    await state.toggleDone(1, false);
    expect(state.message, LanguageHelper.appLoc.bucket_markedUndone);

    state.clear();
  });

  test('a successful delete confirms the removal and reports success',
      () async {
    final state = BucketState(repository: _FakeBucketRepository());

    final deleted = await state.deleteItem(1);

    expect(deleted, isTrue);
    expect(state.message, LanguageHelper.appLoc.bucket_deleted);

    state.clear();
  });

  test('a failed delete reports false and raises no success confirmation',
      () async {
    final repo = _FakeBucketRepository(
      result: const GenericError<void>(message: 'delete rejected', code: 500),
    );
    final state = BucketState(repository: repo);

    final deleted = await state.deleteItem(1);

    expect(deleted, isFalse);
    expect(state.message, isNot(LanguageHelper.appLoc.bucket_deleted),
        reason: 'the screen must be told to restore the row, not confirm it');

    state.clear();
  });

  test('a failed write returns false so the dialog can stay open', () async {
    final repo = _FakeBucketRepository(
      result: const GenericError<void>(message: 'insert rejected', code: 500),
    );
    final state = BucketState(repository: repo);

    final added = await state.addItem('first', 'Personal');

    expect(added, isFalse);

    state.clear();
  });
}
