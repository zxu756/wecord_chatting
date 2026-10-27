import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/ai_settings.dart';
import 'package:wecord/features/ai/on_device/on_device_ai.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../ai_fakes.dart';
import 'on_device_fakes.dart';

Widget _scope(
  FakeOnDeviceBackend backend, {
  FakeAiRepository? ai,
  OnDeviceAiPreferenceStore? store,
}) {
  return ProviderScope(
    overrides: [
      aiRepositoryProvider.overrideWithValue(ai ?? FakeAiRepository()),
      aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
      onDeviceAiBackendProvider.overrideWithValue(backend),
      onDeviceAiPreferenceStoreProvider.overrideWithValue(
        store ?? InMemoryOnDeviceAiPreferenceStore(),
      ),
    ],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: const Scaffold(
        body: SingleChildScrollView(child: AiSettingsGroup()),
      ),
    ),
  );
}

const _row = ValueKey('on-device-ai-switch');

bool _switchValue(WidgetTester tester) => tester
    .widget<WeCordSwitch>(
      find.descendant(
        of: find.byKey(_row),
        matching: find.byType(WeCordSwitch),
      ),
    )
    .value;

void main() {
  testWidgets('the web and Android show no on-device choice', (tester) async {
    await tester.pumpWidget(_scope(FakeOnDeviceBackend(supported: false)));
    await tester.pumpAndSettle();
    expect(find.byKey(_row), findsNothing);
    expect(find.text('Prefer on-device AI'), findsNothing);
  });

  testWidgets('an Apple device with the model on shows it switched on', (
    tester,
  ) async {
    await tester.pumpWidget(_scope(FakeOnDeviceBackend()));
    await tester.pumpAndSettle();
    expect(find.text('Prefer on-device AI'), findsOneWidget);
    expect(find.textContaining('the text never leaves it'), findsOneWidget);
    expect(_switchValue(tester), isTrue);
  });

  testWidgets('turning it off is remembered', (tester) async {
    final store = InMemoryOnDeviceAiPreferenceStore();
    await tester.pumpWidget(_scope(FakeOnDeviceBackend(), store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_row));
    await tester.pumpAndSettle();
    expect(_switchValue(tester), isFalse);
    expect(await store.load(), isFalse);
  });

  testWidgets('a saved choice is read back', (tester) async {
    await tester.pumpWidget(
      _scope(
        FakeOnDeviceBackend(),
        store: InMemoryOnDeviceAiPreferenceStore(false),
      ),
    );
    await tester.pumpAndSettle();
    expect(_switchValue(tester), isFalse);
  });

  testWidgets('a device without Apple Intelligence says so and stays off', (
    tester,
  ) async {
    final backend = FakeOnDeviceBackend(
      status: const OnDeviceAiStatus.unavailable(
        OnDeviceAiUnavailable.deviceNotEligible,
      ),
    );
    await tester.pumpWidget(_scope(backend));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "This device doesn't support Apple Intelligence, so AI uses the server.",
      ),
      findsOneWidget,
    );
    expect(_switchValue(tester), isFalse);
    await tester.tap(find.byKey(_row));
    await tester.pumpAndSettle();
    expect(_switchValue(tester), isFalse, reason: 'it can never work here');
  });

  testWidgets('Apple Intelligence being off can be fixed, so it can be set', (
    tester,
  ) async {
    final backend = FakeOnDeviceBackend(
      status: const OnDeviceAiStatus.unavailable(
        OnDeviceAiUnavailable.notEnabled,
      ),
    );
    await tester.pumpWidget(_scope(backend));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Turn on Apple Intelligence in the system Settings to use it. Until then, AI uses the server.',
      ),
      findsOneWidget,
    );
    expect(_switchValue(tester), isTrue);
  });

  testWidgets('is hidden when the server has no AI', (tester) async {
    final ai = FakeAiRepository()
      ..statusError = const AiNotConfiguredException();
    await tester.pumpWidget(_scope(FakeOnDeviceBackend(), ai: ai));
    await tester.pumpAndSettle();
    expect(find.byKey(_row), findsNothing);
  });
}
