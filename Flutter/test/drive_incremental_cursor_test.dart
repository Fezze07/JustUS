import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

class _MockClient extends Mock implements sb.SupabaseClient {}

class _MockFrom extends Mock implements sb.SupabaseQueryBuilder {}

/// Awaiting the builder yields the canned rows; `then` is implemented because
/// mocktail's canned response never resolves under `await`. The builder is
/// `@immutable`, so the rows are read through a getter instead of a field.
class _MockFilter extends Mock
    implements sb.PostgrestFilterBuilder<sb.PostgrestList> {
  _MockFilter(this.rows);

  final sb.PostgrestList Function() rows;

  @override
  Future<R> then<R>(
    Function(sb.PostgrestList value) onValue, {
    Function? onError,
  }) async {
    try {
      return await onValue(rows()) as R;
    } catch (error, stackTrace) {
      if (onError == null) rethrow;
      return onError(error, stackTrace) as R;
    }
  }
}

sb.PostgrestList _rows() => [
      {
        'id': 1,
        'name': 'boundary.png',
        'type': 'image',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-31T00:00:00.000Z',
        'is_favorite': 0,
      },
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
      '10.15: an item whose updated_at equals the checkpoint is requested on '
      'the next incremental sync (gte, not gt)', () async {
    const checkpoint = '2026-01-31T00:00:00.000Z';
    await CacheService.saveCheckpoint(CacheService.kDriveItems, checkpoint);

    final client = _MockClient();
    final from = _MockFrom();
    final filter = _MockFilter(_rows);

    when(() => client.from('v_drive_dashboard')).thenAnswer((_) => from);
    when(() => from.select(any())).thenAnswer((_) => filter);
    when(() => filter.gte(any(), any())).thenAnswer((_) => filter);
    when(() => filter.gt(any(), any())).thenAnswer((_) => filter);
    when(() => filter.order(any(), ascending: any(named: 'ascending')))
        .thenAnswer((_) => filter);

    final result =
        await DriveRepository(sbClient: client).fetchDriveItemsIncremental();

    expect(result.valueOrNull, hasLength(1));
    // The boundary row is requested: inclusive lower bound on the checkpoint.
    verify(() => filter.gte('updated_at', checkpoint)).called(1);
    verifyNever(() => filter.gt('updated_at', any()));
  });
}
