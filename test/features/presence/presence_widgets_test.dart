import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/home/user_panel.dart';
import 'package:wecord/features/presence/presence_activity_listener.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/models/profile.dart';

import 'presence_repository_test.dart';

void main() {
  testWidgets('the user panel picks a status', (tester) async {
    final presence = FakePresenceRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          presenceRepositoryProvider.overrideWithValue(presence),
          currentProfileProvider.overrideWith(
            (ref) async => Profile(
              id: 'user-1',
              username: 'ada',
              displayName: 'Ada',
              bio: '',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Align(child: UserPanel())),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('user-panel-presence-online')),
      findsOneWidget,
    );
    expect(find.text('Online'), findsOneWidget);

    await tester.tap(find.text('Ada'));
    await tester.pumpAndSettle();
    expect(find.text('Do Not Disturb'), findsOneWidget);
    expect(find.text('Set custom status'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('presence-option-idle')));
    await tester.pumpAndSettle();

    expect(presence.savedStatuses, [PresenceStatus.idle]);
    expect(
      find.byKey(const ValueKey('user-panel-presence-idle')),
      findsOneWidget,
    );
    expect(find.text('Idle'), findsOneWidget);
  });

  testWidgets('goes idle after a quiet while and back on input', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PresenceActivityListener(
            enabled: true,
            idleAfter: Duration(minutes: 10),
            child: Scaffold(body: SizedBox.expand()),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(minutes: 9));
    expect(container.read(presenceInactiveProvider), isFalse);

    // Input part way through restarts the wait.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(const Offset(20, 20));
    await tester.pump(const Duration(minutes: 9));
    expect(container.read(presenceInactiveProvider), isFalse);

    await tester.pump(const Duration(minutes: 2));
    expect(container.read(presenceInactiveProvider), isTrue);

    await mouse.moveTo(const Offset(30, 30));
    await tester.pump();
    expect(container.read(presenceInactiveProvider), isFalse);
    await mouse.removePointer();
  });

  testWidgets('phones never go idle', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PresenceActivityListener(
            enabled: false,
            child: Scaffold(body: SizedBox.expand()),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(hours: 1));
    expect(container.read(presenceInactiveProvider), isFalse);
  });
}
