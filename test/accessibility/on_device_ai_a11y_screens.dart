// Settings → AI → "Prefer on-device AI" (roadmap F8), for the accessibility
// guard (guidelines_test.dart) and the screenshot tools: a Mac or iPhone with
// Apple Intelligence ready, one where it is switched off in the system
// Settings, and one that can never run it (an iPhone with an A16 chip).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/on_device/on_device_ai.dart';
import 'package:wecord/features/ai/translate_repository.dart';

import '../features/ai/ai_fakes.dart';
import '../features/ai/on_device/on_device_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// Settings → AI scrolled to the on-device row, on a device whose model is in
/// [status].
Future<void> openOnDeviceAiSettings(
  WidgetTester tester,
  PhoneWorld world, {
  OnDeviceAiStatus status = const OnDeviceAiStatus.available(),
  bool prefer = true,
}) async {
  world.extraOverrides = [
    aiRepositoryProvider.overrideWithValue(
      FakeAiRepository()
        ..storedSettings = const AiTranslateSettings(
          target: AiLanguage.chinese,
        ),
    ),
    aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
    onDeviceAiBackendProvider.overrideWithValue(
      FakeOnDeviceBackend(status: status),
    ),
    onDeviceAiPreferenceStoreProvider.overrideWithValue(
      InMemoryOnDeviceAiPreferenceStore(prefer),
    ),
  ];
  await world.open(tester, '/me');
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('on-device-ai-switch')),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  // The AI switch above it in view when it fits.
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
  await settle(tester);
}

final onDeviceAiA11yScreens = <A11yScreen>[
  A11yScreen('on-device-ai-settings', openOnDeviceAiSettings),
  A11yScreen(
    'on-device-ai-settings-off',
    (tester, world) => openOnDeviceAiSettings(tester, world, prefer: false),
  ),
  A11yScreen(
    'on-device-ai-settings-not-enabled',
    (tester, world) => openOnDeviceAiSettings(
      tester,
      world,
      status: const OnDeviceAiStatus.unavailable(
        OnDeviceAiUnavailable.notEnabled,
      ),
    ),
  ),
  A11yScreen(
    'on-device-ai-settings-not-eligible',
    (tester, world) => openOnDeviceAiSettings(
      tester,
      world,
      status: const OnDeviceAiStatus.unavailable(
        OnDeviceAiUnavailable.deviceNotEligible,
      ),
    ),
  ),
];
