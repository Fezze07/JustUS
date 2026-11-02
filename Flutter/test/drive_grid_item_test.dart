import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_path_provider.dart';

DriveItem _item(String type, {String? thumb}) {
  return DriveItem(
    id: 1,
    type: type,
    content: 'uploads/1/original.bin',
    metadata: thumb == null ? null : {'thumbnail': thumb},
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    isFavorite: 0,
  );
}

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('it'),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 120, height: 120, child: child),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installMockPathProvider();
  });

  test('contentThumb returns the generated key and never the full object', () {
    expect(_item('image', thumb: 'uploads/1/thumb.jpg').contentThumb,
        'uploads/1/thumb.jpg');
    expect(_item('image').contentThumb, isNull);
    expect(_item('video').contentThumb, isNull);
  });

  testWidgets('a video thumbnail renders without a video player',
      (tester) async {
    await tester.pumpWidget(_host(DriveGridItem(
      item: _item('video', thumb: 'uploads/1/thumb.jpg'),
      onTap: () {},
    )));

    final image =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(image.imageUrl, contains('filename=uploads%2F1%2Fthumb.jpg'));
    expect(find.byType(VideoPlayer), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a video without a thumbnail shows a placeholder',
      (tester) async {
    await tester.pumpWidget(_host(DriveGridItem(
      item: _item('video'),
      onTap: () {},
    )));

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
  });

  testWidgets('an image without a thumbnail never falls back to the original',
      (tester) async {
    await tester.pumpWidget(_host(DriveGridItem(
      item: _item('image'),
      onTap: () {},
    )));

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byIcon(Icons.image_not_supported), findsOneWidget);
  });

  testWidgets('audio and PDF tiles are static icons', (tester) async {
    await tester.pumpWidget(_host(DriveGridItem(
      item: _item('audio'),
      onTap: () {},
    )));

    expect(find.byIcon(Icons.audiotrack), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);

    await tester.pumpWidget(_host(DriveGridItem(
      item: _item('file'),
      onTap: () {},
    )));

    expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });
}
