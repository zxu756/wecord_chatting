// Renders the circle Insights page on a phone and a desktop, light, dark and
// high contrast, with real fonts, and writes PNGs for eyeballing. The window
// is tall enough to show the whole page. Not part of `flutter test`; run it
// with:
//
//   flutter test tool/screenshots/insights_screenshots_test.dart \
//     --dart-define=INSIGHTS_SCREENS_DIR=build/insights
//
// Chinese with --dart-define=INSIGHTS_SCREENS_ZH=true.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/insights/insights_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

import '../../test/features/circles/insights_fakes.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'INSIGHTS_SCREENS_DIR',
  defaultValue: 'build/insights',
);
const _zh = bool.fromEnvironment('INSIGHTS_SCREENS_ZH');

class _Variant {
  const _Variant(this.name, this.size, this.theme);

  final String name;
  final Size size;
  final ThemeData theme;
}

void main() {
  setUpAll(loadScreenshotFonts);

  final variants = [
    _Variant('phone-light', const Size(390, 2900), WeCordTheme.light()),
    _Variant('phone-dark', const Size(390, 2900), WeCordTheme.dark()),
    _Variant('desktop-light', const Size(1440, 2300), WeCordTheme.light()),
    _Variant('desktop-dark', const Size(1440, 2300), WeCordTheme.dark()),
    _Variant(
      'phone-light-hc',
      const Size(390, 2900),
      WeCordTheme.light().copyWith(
        extensions: const [WeCordTokens.lightHighContrast],
      ),
    ),
    _Variant(
      'phone-dark-hc',
      const Size(390, 2900),
      WeCordTheme.dark().copyWith(
        extensions: const [WeCordTokens.darkHighContrast],
      ),
    ),
  ];

  for (final small in [false, true]) {
    for (final variant in variants) {
      if (small && !variant.name.startsWith('phone-light')) {
        continue;
      }
      final name = '${small ? 'small-' : ''}${variant.name}';
      testWidgets('insights $name', (tester) async {
        AppStrings.isChinese = _zh;
        addTearDown(() => AppStrings.isChinese = false);
        tester.view.physicalSize = variant.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        Future<Object?> rpc(
          String function,
          Map<String, dynamic> params,
        ) async {
          if (function == 'get_circle_insights') {
            return insightsJson(small: small);
          }
          throw StateError('Unexpected $function');
        }

        await tester.pumpWidget(
          ProviderScope(
            retry: noProviderRetry,
            overrides: [circleRpcProvider.overrideWithValue(rpc)],
            child: MaterialApp(
              theme: variant.theme,
              debugShowCheckedModeBanner: false,
              home: const CircleInsightsScreen(circleId: 'circle-1'),
            ),
          ),
        );
        for (var round = 0; round < 3; round++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)),
          );
          await tester.pumpAndSettle();
        }
        final renderView = tester.binding.renderViews.first;
        final layer = renderView.debugLayer! as OffsetLayer;
        await tester.runAsync(() async {
          final image = await layer.toImage(renderView.paintBounds);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$_outputDir/$name.png');
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}
