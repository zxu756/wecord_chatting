// Renders the QR code, Scan, pat-pat and Note to self screens on a phone and
// a desktop, light and dark, with real fonts, and writes PNGs for eyeballing.
// Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/qr_pat_screenshots_test.dart \
//     --dart-define=QR_PAT_SCREENS_DIR=build/qr-pat
//
// Pick screens with --dart-define=QR_PAT_ONLY=my-qr,scanner,note.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/qr/group_qr_sheet.dart';
import 'package:wecord/features/qr/qr_camera.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../../test/features/pat/pat_fakes.dart';
import '../../test/features/qr/qr_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'QR_PAT_SCREENS_DIR',
  defaultValue: 'build/qr-pat',
);
const _only = String.fromEnvironment('QR_PAT_ONLY');

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

class _Variant {
  const _Variant(this.name, this.viewport, this.dark);

  final String name;
  final PhoneViewport viewport;
  final bool dark;

  bool get desktop => viewport == _desktop;
}

const _variants = [
  _Variant('phone-light', notchedPhone, false),
  _Variant('phone-dark', notchedPhone, true),
  _Variant('desktop-light', _desktop, false),
  _Variant('desktop-dark', _desktop, true),
];

final _note = ConversationSummary(
  id: 'note-1',
  type: ConversationType.direct,
  unreadCount: 0,
  title: 'Note to self',
  memberCount: 1,
  isNoteToSelf: true,
  pinnedAt: minutesAgo(5000),
  lastMessageBody: 'Train tickets for Friday: booking ref 8KQ2LM',
  lastMessageType: MessageType.text,
  lastMessageSenderId: 'user-1',
  lastMessageAt: minutesAgo(20),
);

/// A made-up view through a phone camera: a dim room with a bright window.
Widget _sceneCamera(
  BuildContext context, {
  required ValueChanged<String> onCode,
  required ValueChanged<QrCameraProblem> onProblem,
}) {
  return const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3B3F4A), Color(0xFF1B1D24), Color(0xFF55493B)],
      ),
    ),
  );
}

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    for (var round = 0; round < 3; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await settle(tester);
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
  }

  final only = _only.isEmpty ? null : _only.split(',').toSet();

  void screen(
    String group,
    String name,
    Future<void> Function(
      WidgetTester tester,
      PhoneWorld world,
      _Variant variant,
    )
    open, {
    FakeQrRepository? repository,
    FakeQrCamera? camera,
    List<String> variants = const [
      'phone-light',
      'phone-dark',
      'desktop-light',
      'desktop-dark',
    ],
  }) {
    if (only != null && !only.contains(group)) {
      return;
    }
    for (final variant in _variants) {
      if (!variants.contains(variant.name)) {
        continue;
      }
      testWidgets('$name ${variant.name}', (tester) async {
        if (variant.desktop) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        }
        try {
          usePhoneViewport(tester, variant.viewport);
          final world = PhoneWorld()
            ..themeMode = variant.dark ? ThemeMode.dark : ThemeMode.light;
          world.extraOverrides = [
            ...qrOverrides(
              repository: repository ?? FakeQrRepository(),
              exporter: FakeQrImageExporter(),
              launcher: FakeUrlLauncher(),
            ),
            qrCameraBuilderProvider.overrideWithValue(
              camera?.build ?? _sceneCamera,
            ),
            ...patOverrides(FakePatRepository()..currentSuffix = "'s shoulder"),
          ];
          await open(tester, world, variant);
          await shoot(tester, '$name-${variant.name}');
          await world.close(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    final list = find.byKey(const ValueKey('settings-page-list'));
    if (finder.evaluate().isEmpty && list.evaluate().isNotEmpty) {
      await tester.dragUntilVisible(finder, list, const Offset(0, -200));
    }
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester);
  }

  // The settings page on a phone; on a desktop the window's profile page.
  Future<void> openSettingsRow(
    WidgetTester tester,
    PhoneWorld world,
    _Variant variant,
    String key,
  ) async {
    await world.open(tester, '/me');
    if (variant.desktop) {
      await tester.tap(find.text('My profile').first);
      await settle(tester);
    }
    await tapKey(tester, key);
  }

  // ---------------------------------------------------------------- my QR

  screen('my-qr', 'my-qr', (tester, world, variant) async {
    await openSettingsRow(tester, world, variant, 'settings-my-qr');
  });
  screen('my-qr', 'my-qr-reset', (tester, world, variant) async {
    await openSettingsRow(tester, world, variant, 'settings-my-qr');
    await tapKey(tester, 'qr-reset');
  }, variants: const ['phone-light', 'phone-dark']);
  screen('my-qr', 'settings', (tester, world, variant) async {
    await world.open(tester, '/me');
    if (variant.desktop) {
      await tester.tap(find.text('My profile').first);
      await settle(tester);
    }
  });
  screen('my-qr', 'add-friend', (tester, world, variant) async {
    await world.open(tester, '/contacts');
  });

  // ------------------------------------------------------------------ scan

  screen('scanner', 'scanner', (tester, world, variant) async {
    await openSettingsRow(tester, world, variant, 'settings-scan');
  });
  final deniedCamera = FakeQrCamera()
    ..failWith = QrCameraProblem.permissionDenied;
  screen(
    'scanner',
    'scanner-camera-off',
    (tester, world, variant) async {
      await openSettingsRow(tester, world, variant, 'settings-scan');
    },
    camera: deniedCamera,
    variants: const ['phone-light', 'phone-dark'],
  );
  final readingCamera = FakeQrCamera();
  screen(
    'scanner',
    'scanned-text',
    (tester, world, variant) async {
      await openSettingsRow(tester, world, variant, 'settings-scan');
      readingCamera.onCode!('https://example.com/venue-map?table=12');
      await settle(tester);
    },
    camera: readingCamera,
    variants: const ['phone-light', 'phone-dark'],
  );
  screen('scanner', 'new-menu', (tester, world, variant) async {
    await world.open(tester, '/home');
    await tapKey(tester, variant.desktop ? 'home-new' : 'phone-home-new');
  });

  // ------------------------------------------------------------ group QR

  screen('group', 'group-qr', (tester, world, variant) async {
    await world.open(tester, '/home');
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(
      showGroupQrSheet(
        context,
        conversationId: 'group-1',
        title: groupDetail.title,
        memberCount: 42,
      ),
    );
    await settle(tester);
  });
  screen('group', 'group-qr-join', (tester, world, variant) async {
    await world.open(tester, '/g/$sampleGroupCode');
  }, variants: const ['phone-light', 'phone-dark', 'desktop-light']);
  screen('group', 'group-details', (tester, world, variant) async {
    world.chats.messages = richMessages();
    await world.open(
      tester,
      '${ChatsScreen.path}/group-1',
      extra: ChatThreadRouteExtra(
        title: groupDetail.title,
        type: ConversationType.group,
      ),
    );
    await tester.tap(find.byTooltip('Group details'));
    await settle(tester);
    final qr = find.byKey(const ValueKey('group-detail-qr'));
    if (qr.evaluate().isNotEmpty) {
      await tester.ensureVisible(qr);
      await settle(tester);
    }
  }, variants: const ['phone-light', 'phone-dark']);

  // --------------------------------------------------------------- pat-pat

  screen('pat', 'pat-lines', (tester, world, variant) async {
    world.chats.messages = [
      ...richMessages(),
      patMessage(
        'pat-theirs',
        actorId: 'user-2',
        targetId: 'user-1',
        actorName: 'Bart',
        targetName: 'Ada',
        suffix: "'s shoulder",
        age: const Duration(minutes: 10),
      ),
      patMessage(
        'pat-mine',
        actorId: 'user-1',
        targetId: 'user-2',
        suffix: "'s shoulder",
        age: const Duration(seconds: 20),
      ),
    ];
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
  });
  screen('pat', 'pat-suffix', (tester, world, variant) async {
    await openSettingsRow(tester, world, variant, 'pat-suffix-row');
  });

  // ---------------------------------------------------------- note to self

  Future<void> openNote(
    WidgetTester tester,
    PhoneWorld world,
    _Variant variant,
  ) async {
    world.chats
      ..conversations = [...world.chats.conversations, _note]
      ..readMarkers = const []
      ..messages = [
        for (final (index, text) in [
          'Train tickets for Friday: booking ref 8KQ2LM',
          'Venue map is in the shared drive',
          'Remember to bring the charger',
        ].indexed)
          phoneMessage(
            'note-$index',
            me,
            text,
            minutesAgo: 90 - index * 30,
            conversationId: 'note-1',
          ),
      ];
    await world.open(
      tester,
      '${ChatsScreen.path}/note-1',
      extra: const ChatThreadRouteExtra(
        title: 'Note to self',
        type: ConversationType.direct,
      ),
    );
  }

  screen('note', 'note-to-self', openNote);
  screen('note', 'home-with-note', (tester, world, variant) async {
    world.chats.conversations = [..._withNote(world)];
    await world.open(tester, '/home');
  });
  screen('note', 'home-note-not-made-yet', (tester, world, variant) async {
    await world.open(tester, '/home');
  }, variants: const ['phone-light', 'phone-dark']);
}

List<ConversationSummary> _withNote(PhoneWorld world) => [
  ...world.chats.conversations,
  _note,
];
