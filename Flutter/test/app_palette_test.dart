import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justus/all_imports.dart';

import 'test_helpers/source_scan.dart';

double _relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Contrast of [fg] painted over [bg], compositing translucency first.
///
/// The dark palette uses genuinely translucent ink and surface tokens
/// (`contentSecondary` is `0xB3FFFFFF`, `surfaceGroup` is `0x662D1652`).
/// Measuring their RGB channels directly — as this file used to — treats them
/// as fully opaque and reports a contrast the user never actually sees.
double _contrastOn(Color fg, Color bg) =>
    _contrast(Color.alphaBlend(fg, bg), bg);

void main() {
  final palettes = <String, AppPalette>{
    'light': AppPalette.light,
    'dark': AppPalette.dark,
  };

  for (final entry in palettes.entries) {
    final name = entry.key;
    final p = entry.value;

    group('AppPalette.$name', () {
      test('brightness matches the palette', () {
        expect(
            p.brightness, name == 'light' ? Brightness.light : Brightness.dark);
      });

      test('body ink is readable on every surface', () {
        for (final surface in <Color>[
          p.canvas,
          p.surface,
          p.surfaceElevated,
          p.surfaceSunken,
        ]) {
          expect(
              _contrastOn(p.contentPrimary, surface), greaterThanOrEqualTo(4.5),
              reason: 'contentPrimary on '
                  '${surface.toARGB32().toRadixString(16)}');
        }

        // A translucent surface token is what the user actually sees only after
        // it is composited onto the backdrop it is painted over.
        final compositedGroup = Color.alphaBlend(p.surfaceGroup, p.canvas);
        expect(_contrastOn(p.contentPrimary, compositedGroup),
            greaterThanOrEqualTo(4.5),
            reason: 'contentPrimary on surfaceGroup over canvas '
                '(${compositedGroup.toARGB32().toRadixString(16)})');
      });

      test('secondary ink is readable on the main surfaces', () {
        for (final surface in <Color>[p.canvas, p.surface, p.surfaceElevated]) {
          expect(_contrastOn(p.contentSecondary, surface),
              greaterThanOrEqualTo(4.5),
              reason: 'contentSecondary is translucent in the dark palette');
        }
      });

      test('foreground sits on the primary fill', () {
        expect(_contrastOn(p.onPrimary, p.primary), greaterThanOrEqualTo(4.5));
      });

      test('foreground sits on the danger surface', () {
        expect(_contrastOn(p.onDanger, p.dangerSurface),
            greaterThanOrEqualTo(4.5));
      });

      test('primaryVariant is usable as text on the canvas', () {
        expect(
            _contrastOn(p.primaryVariant, p.canvas), greaterThanOrEqualTo(4.5));
      });

      test('status accents are distinguishable from the canvas', () {
        for (final status in <Color>[p.danger, p.success, p.warning, p.info]) {
          expect(_contrastOn(status, p.canvas), greaterThanOrEqualTo(3.0),
              reason: 'status accent on canvas');
        }
      });

      test('canvas and surface are not the same value', () {
        expect(p.canvas, isNot(p.surface));
      });
    });
  }

  group('AppPalette light/dark differ', () {
    test('surfaces and ink flip', () {
      expect(AppPalette.light.canvas, isNot(AppPalette.dark.canvas));
      expect(AppPalette.light.surface, isNot(AppPalette.dark.surface));
      expect(AppPalette.light.contentPrimary,
          isNot(AppPalette.dark.contentPrimary));
    });

    test('lerp interpolates between the two', () {
      final mid = AppPalette.light.lerp(AppPalette.dark, 0.5);
      expect(mid.canvas, isNot(AppPalette.light.canvas));
      expect(mid.canvas, isNot(AppPalette.dark.canvas));
      expect(mid.contentPrimary, isNot(AppPalette.light.contentPrimary));
      expect(mid.contentPrimary, isNot(AppPalette.dark.contentPrimary));
    });

    test('lerp keeps the brightness switch on the right side of t=0.5', () {
      // A `lerp` that always returned the same palette would still satisfy a
      // midpoint-only check, so pin the switch behaviour explicitly.
      expect(AppPalette.light.lerp(AppPalette.dark, 0.49).brightness,
          Brightness.light);
      expect(AppPalette.light.lerp(AppPalette.dark, 0.51).brightness,
          Brightness.dark);
      // The endpoints must be (near-)exact, not approximations.
      expect(AppPalette.light.lerp(AppPalette.dark, 0).canvas,
          AppPalette.light.canvas);
      expect(AppPalette.light.lerp(AppPalette.dark, 1).canvas,
          AppPalette.dark.canvas);
    });
  });

  group('lib/ does not reintroduce static brightness colors', () {
    late Directory libDir;

    setUpAll(() {
      // No machine-specific fallback: if lib/ is missing the scan must fail
      // loudly rather than scan a hardcoded absolute path.
      libDir = resolveLibDir();
    });

    /// `AppPalette.brand*` members that are legitimately identical in both
    /// themes. Anything else read from a `brand*` name is a themed value in
    /// disguise, and any new `brand*` member has to be argued for here.
    const brandOnly = <String>{
      'brandPrimary',
      'brandAccentAqua',
      'brandNeonPurple',
      'brandNeonBlue',
      'brandNeonGreen',
      'brandNeonPink',
      'brandGradientStart',
      'brandGradientAccent',
      'brandHeroOverlay',
      'brandHeroGlass',
    };

    Iterable<File> sourceFiles() => libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.contains(
            '${Platform.pathSeparator}theme${Platform.pathSeparator}'))
        .where((f) => !f.path.endsWith('app_theme.dart'));

    test('only brand-fixed tokens are read from a brand* static', () {
      final offenders = <String>[];
      final brand = RegExp(r'AppPalette\.(brand\w+)');
      for (final file in sourceFiles()) {
        for (final match in brand.allMatches(file.readAsStringSync())) {
          final symbol = match.group(1)!;
          if (!brandOnly.contains(symbol)) {
            offenders.add('${file.path}: AppPalette.$symbol');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'Brightness-dependent colors must not be brand-fixed; use '
              'context.palette instead:\n${offenders.join('\n')}');
    });

    test('the removed AppColors class is not referenced again', () {
      final offenders = <String>[];
      for (final file in libDir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        if (file.path.contains(
            '${Platform.pathSeparator}theme${Platform.pathSeparator}')) {
          continue;
        }
        if (RegExp(r'\bAppColors\b').hasMatch(file.readAsStringSync())) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'AppColors was folded into AppPalette.Brand:\n'
              '${offenders.join('\n')}');
    });

    test('no raw white/black/grey outside the theme token files', () {
      final offenders = <String>[];
      final raw = RegExp(r'Colors\.(white\d*|black\d*|grey\d*)\b');
      for (final file in sourceFiles()) {
        final content = file
            .readAsStringSync()
            .replaceAll(RegExp(r'//.*'), '')
            .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
        for (final match in raw.allMatches(content)) {
          offenders.add('${file.path}: ${match.group(0)}');
        }
      }
      // The auth hero keeps the Violet-Punk gradient in both themes, so its
      // white icon and wordmark are brand-fixed rather than themed ink.
      final authHero = offenders.where((o) =>
          o.contains('vp_widgets.dart') &&
          RegExp(r'Colors\.(white|white70)\b').hasMatch(o));
      expect(offenders.toSet().difference(authHero.toSet()), isEmpty,
          reason: 'Use a palette token so the color adapts to the theme:\n'
              '${offenders.join('\n')}');
    });
  });
}
