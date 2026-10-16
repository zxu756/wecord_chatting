import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/chats/media_send/media_tray.dart';
import 'package:wecord/features/chats/media_send/media_tray_controller.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'media_fakes.dart';

const _conversation = 'conversation-1';

XFile _file(String name, String mime, {int length = 3}) {
  return XFile.fromData(
    Uint8List.fromList([1, 2, 3]),
    name: name,
    path: name,
    mimeType: mime,
    length: length,
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Future<void> Function()? onSend,
  void Function(BuildContext)? onAddMore,
  bool sendEnabled = true,
  bool dark = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      videoPosterReaderProvider.overrideWithValue((file) async => null),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: dark ? WeCordTheme.dark() : WeCordTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: MediaTray(
                conversationId: _conversation,
                sendEnabled: sendEnabled,
                onSend: onSend ?? () async {},
                onAddMore: onAddMore ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return container;
}

MediaTrayController _controller(ProviderContainer container) =>
    container.read(mediaTrayProvider(_conversation).notifier);

MediaTrayState _state(ProviderContainer container) =>
    container.read(mediaTrayProvider(_conversation));

Future<void> _add(
  WidgetTester tester,
  ProviderContainer container,
  List<XFile> files,
) async {
  // Keep the tray alive: it is watched by the widget.
  await tester.runAsync(() => _controller(container).add(files));
  await tester.pump();
}

void main() {
  testWidgets('an empty tray shows nothing', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('media-tray')), findsNothing);
  });

  testWidgets('photos show as thumbnails you can take out again', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _add(tester, container, [testPhoto('a.jpg'), testPhoto('b.jpg')]);

    expect(find.text('2 photos'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.byKey(const ValueKey('media-tray-add')), findsOneWidget);

    final first = _state(container).items.first;
    await tester.tap(find.byKey(ValueKey('media-tray-remove-${first.id}')));
    await tester.pump();
    expect(find.text('1 photo'), findsOneWidget);

    final second = _state(container).items.single;
    await tester.tap(find.byKey(ValueKey('media-tray-remove-${second.id}')));
    await tester.pump();
    expect(find.byKey(const ValueKey('media-tray')), findsNothing);
  });

  testWidgets('the title names what is in the tray', (tester) async {
    final container = await _pump(tester);
    await _add(tester, container, [_file('a.pdf', 'application/pdf')]);
    expect(find.text('1 file'), findsOneWidget);
    await _add(tester, container, [testPhoto('b.jpg')]);
    expect(find.text('2 items'), findsOneWidget);
  });

  testWidgets('a tray holds ten and says what was left out', (tester) async {
    final container = await _pump(tester);
    await _add(tester, container, [
      for (var i = 0; i < 12; i++) _file('f$i.txt', 'text/plain'),
    ]);

    expect(_state(container).items, hasLength(10));
    expect(find.text('10 files'), findsOneWidget);
    expect(
      find.text('You can send up to 10 at a time. 2 left out.'),
      findsOneWidget,
    );
    // Full: no add button.
    expect(find.byKey(const ValueKey('media-tray-add')), findsNothing);

    // The notice goes when dismissed.
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.byKey(const ValueKey('media-tray-left-out')), findsNothing);

    // Adding more to a full tray changes nothing but the notice.
    await _add(tester, container, [_file('g.txt', 'text/plain')]);
    expect(_state(container).items, hasLength(10));
  });

  testWidgets('Original quality shows with photos and is remembered', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _add(tester, container, [_file('a.pdf', 'application/pdf')]);
    expect(find.text('Original quality'), findsNothing);

    await _add(tester, container, [testPhoto('b.jpg')]);
    expect(find.text('Original quality'), findsOneWidget);
    expect(find.text('Resized to 2560 px · location removed'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('media-tray-original')));
    await tester.pump();
    expect(_state(container).original, isTrue);

    // Emptying the tray keeps the choice for the next one.
    _controller(container).clear();
    await tester.pump();
    expect(_state(container).original, isTrue);
  });

  testWidgets('the caption is kept and sending is offered', (tester) async {
    var sent = 0;
    final container = await _pump(tester, onSend: () async => sent += 1);
    await _add(tester, container, [testPhoto('a.jpg'), testPhoto('b.jpg')]);

    await tester.enterText(
      find.byKey(const ValueKey('media-tray-caption')),
      'Lake day',
    );
    expect(_state(container).caption, 'Lake day');
    expect(find.text('Send 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('media-tray-send')));
    await tester.pump();
    expect(sent, 1);
  });

  testWidgets('sending waits while slowmode lasts', (tester) async {
    final container = await _pump(tester, sendEnabled: false);
    await _add(tester, container, [testPhoto('a.jpg')]);
    expect(
      tester
          .widget<WeCordButton>(find.byKey(const ValueKey('media-tray-send')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('while preparing, the tray says how far and locks', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _add(tester, container, [testPhoto('a.jpg'), testPhoto('b.jpg')]);

    _controller(container).setPreparing((1, 2));
    await tester.pump();

    expect(find.text('Preparing 1 of 2…'), findsOneWidget);
    expect(
      tester
          .widget<WeCordButton>(find.byKey(const ValueKey('media-tray-send')))
          .loading,
      isTrue,
    );
    expect(find.byKey(const ValueKey('media-tray-add')), findsNothing);
  });

  testWidgets('files being looked at show as placeholders', (tester) async {
    final container = await _pump(tester);
    await tester.runAsync(() async {
      unawaited(_controller(container).add([testPhoto('a.jpg')]));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(find.text('1 item'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(find.text('1 photo'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('add more hands over its own place on screen', (tester) async {
    BuildContext? anchor;
    final container = await _pump(
      tester,
      onAddMore: (context) => anchor = context,
    );
    await _add(tester, container, [testPhoto('a.jpg')]);

    await tester.tap(find.byKey(const ValueKey('media-tray-add')));
    expect(anchor, isNotNull);
  });

  testWidgets('works in the dark theme too', (tester) async {
    final container = await _pump(tester, dark: true);
    await _add(tester, container, [testPhoto('a.jpg')]);
    expect(find.byKey(const ValueKey('media-tray')), findsOneWidget);
  });
}
