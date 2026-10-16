// Runs Flutter's accessibility guidelines over the main screens, in the
// light and dark themes and with the platform's "Increase contrast" on:
// tap target sizes (Android 48, iOS 44), labelled tap targets and text
// contrast. The guideline messages list every offending widget, so a
// failure says what to fix.
//
// To see every failure at once instead of stopping at the first screen:
//   flutter test test/accessibility/guidelines_test.dart \
//     --dart-define=A11Y_REPORT=true
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

const _report = bool.fromEnvironment('A11Y_REPORT');

/// The guideline checks, by name. Tap targets only apply to touch layouts.
final _guidelines = <String, (AccessibilityGuideline, bool touchOnly)>{
  'android tap target': (androidTapTargetGuideline, true),
  'ios tap target': (iOSTapTargetGuideline, true),
  'labeled tap target': (labeledTapTargetGuideline, false),
  'text contrast': (textContrastGuideline, false),
};

void main() {
  for (final mode in const [
    (ThemeMode.light, false),
    (ThemeMode.dark, false),
    (ThemeMode.light, true),
    (ThemeMode.dark, true),
  ]) {
    final (themeMode, highContrast) = mode;
    final modeName = '${themeMode.name}${highContrast ? ' high contrast' : ''}';
    group(modeName, () {
      for (final screen in allA11yScreens) {
        // High contrast only needs the contrast guideline on a few screens;
        // the sizes do not change.
        testWidgets('${screen.name} meets the guidelines', (tester) async {
          if (screen.desktop) {
            debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          }
          final handle = tester.ensureSemantics();
          try {
            usePhoneViewport(tester, screen.viewport);
            if (highContrast) {
              tester.platformDispatcher.accessibilityFeaturesTestValue =
                  const FakeAccessibilityFeatures(highContrast: true);
              addTearDown(
                tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
              );
            }
            final world = PhoneWorld()..themeMode = themeMode;
            await screen.open(tester, world);
            await settle(tester);

            final failures = <String>[];
            for (final MapEntry(key: name, value: (guideline, touchOnly))
                in _guidelines.entries) {
              if (touchOnly && screen.desktop) {
                continue;
              }
              if (highContrast && name != 'text contrast') {
                continue;
              }
              final result = await guideline.evaluate(tester);
              if (!result.passed) {
                failures.add('$name: ${result.reason}');
              }
            }
            if (failures.isNotEmpty) {
              final message = failures.join('\n');
              if (_report) {
                debugPrint('FAIL ${screen.name} ($modeName)\n$message');
              } else {
                fail('${screen.name} ($modeName)\n$message');
              }
            }
            await world.close(tester);
          } finally {
            debugDefaultTargetPlatformOverride = null;
            handle.dispose();
          }
        });
      }
    });
  }
}
