import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wecord/features/qr/group_qr_sheet.dart';
import 'package:wecord/features/qr/my_qr_sheet.dart';
import 'package:wecord/features/qr/qr_card.dart';
import 'package:wecord/features/qr/qr_image_export.dart';
import 'package:wecord/features/qr/qr_links.dart';

import '../../mobile/phone_test_support.dart';
import 'qr_fakes.dart';

/// Opens [open] from a button, the way a settings row does.
Future<void> _pumpHost(
  WidgetTester tester,
  PhoneWorld world,
  Future<void> Function(BuildContext context) open,
) async {
  await pumpStandalone(
    tester,
    world,
    Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => unawaited(open(context)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settle(tester);
}

/// Lets a picture of the card be taken: the engine renders on its own time,
/// which the test clock does not wait for.
Future<void> _waitForPicture(
  WidgetTester tester,
  FakeQrImageExporter exporter,
) async {
  for (var wait = 0; wait < 100; wait++) {
    if (exporter.saved.isNotEmpty || exporter.shared.isNotEmpty) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  await settle(tester);
}

void main() {
  late PhoneWorld world;
  late FakeQrRepository qr;
  late FakeQrImageExporter exporter;

  setUp(() {
    world = PhoneWorld();
    qr = FakeQrRepository();
    exporter = FakeQrImageExporter();
    world.extraOverrides = qrOverrides(repository: qr, exporter: exporter);
  });

  group('My QR code', () {
    testWidgets('shows who it is for, with a link to the site in the code', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      await _pumpHost(tester, world, showMyQrSheet);

      expect(find.text('My QR code'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('@ada'), findsOneWidget);
      expect(find.text('Scan to add me on WeCord'), findsOneWidget);
      final code = tester.widget<QrCard>(find.byType(QrCard)).data;
      expect(code, userQrUrl(sampleUserCode));
      expect(code, startsWith('https://wecord.jokebear.fyi/u/'));
      // The code is opaque: nothing of the user id is in it.
      expect(code, isNot(contains('user-1')));
    });

    testWidgets('Save image hands the picture of the card over', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      await _pumpHost(tester, world, showMyQrSheet);

      await tester.tap(find.byKey(const ValueKey('qr-save-image')));
      await _waitForPicture(tester, exporter);

      expect(exporter.saved, hasLength(1));
      expect(exporter.saved.single.name, 'wecord-qr-ada');
      // A PNG, larger than the card.
      expect(exporter.saved.single.png.sublist(1, 4), 'PNG'.codeUnits);
      expect(exporter.saved.single.png.length, greaterThan(5000));
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('Share sends the picture with the link', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await _pumpHost(tester, world, showMyQrSheet);

      await tester.tap(find.byKey(const ValueKey('qr-share')));
      await _waitForPicture(tester, exporter);

      expect(exporter.shared, hasLength(1));
      expect(
        exporter.shared.single.text,
        'Add me on WeCord: ${userQrUrl(sampleUserCode)}',
      );
      // Sharing says nothing more: the share sheet did the talking.
      expect(find.byKey(const ValueKey('qr-status')), findsNothing);
    });

    testWidgets('a failed save says so', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      exporter.saveOutcome = QrExportOutcome.failed;
      await _pumpHost(tester, world, showMyQrSheet);

      await tester.tap(find.byKey(const ValueKey('qr-save-image')));
      await _waitForPicture(tester, exporter);

      expect(
        find.text("Couldn't save the picture. Try again."),
        findsOneWidget,
      );
    });

    testWidgets('Reset QR code asks first, then makes a new code', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      await _pumpHost(tester, world, showMyQrSheet);
      final before = tester.widget<QrCard>(find.byType(QrCard)).data;

      await tester.tap(find.byKey(const ValueKey('qr-reset')));
      await settle(tester);
      expect(find.text('Reset your QR code?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(qr.resets, 0);

      await tester.tap(find.byKey(const ValueKey('qr-reset')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('qr-reset-confirm')));
      await settle(tester);

      expect(qr.resets, 1);
      final after = tester.widget<QrCard>(find.byType(QrCard)).data;
      expect(after, isNot(before));
      expect(after, userQrUrl(qr.code));
      expect(find.text('Your QR code was reset.'), findsOneWidget);
    });

    testWidgets('a failed reset leaves the code and says so', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      qr.failReset = StateError('offline');
      await _pumpHost(tester, world, showMyQrSheet);

      await tester.tap(find.byKey(const ValueKey('qr-reset')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('qr-reset-confirm')));
      await settle(tester);

      expect(
        find.text("Couldn't reset the QR code. Try again."),
        findsOneWidget,
      );
      expect(
        tester.widget<QrCard>(find.byType(QrCard)).data,
        userQrUrl(sampleUserCode),
      );
    });

    testWidgets('a code that does not load can be tried again', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      qr.failMyCode = StateError('offline');
      await _pumpHost(tester, world, showMyQrSheet);
      expect(find.text("Couldn't load your QR code."), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);

      qr.failMyCode = null;
      await tester.tap(find.byKey(const ValueKey('qr-retry')));
      await settle(tester);
      expect(find.byType(QrImageView), findsOneWidget);
    });
  });

  group('Group QR code', () {
    testWidgets('shows the group, how long it works and a link', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      await _pumpHost(
        tester,
        world,
        (context) => showGroupQrSheet(
          context,
          conversationId: 'group-1',
          title: 'Weekend climbers',
          memberCount: 12,
        ),
      );

      expect(find.text('Group QR code'), findsOneWidget);
      expect(find.text('Weekend climbers'), findsOneWidget);
      expect(find.text('12 members'), findsOneWidget);
      expect(find.text('Scan to join the group'), findsOneWidget);
      expect(find.text('Expires in 7 days'), findsOneWidget);
      expect(
        tester.widget<QrCard>(find.byType(QrCard)).data,
        groupQrUrl(sampleGroupCode),
      );
      expect(qr.groupRequests.single, (
        conversationId: 'group-1',
        refresh: false,
      ));
    });

    testWidgets('Refresh makes a new code and says so', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await _pumpHost(
        tester,
        world,
        (context) => showGroupQrSheet(
          context,
          conversationId: 'group-1',
          title: 'Weekend climbers',
        ),
      );

      await tester.tap(find.byKey(const ValueKey('group-qr-refresh')));
      await settle(tester);

      expect(qr.groupRequests.last.refresh, isTrue);
      expect(find.text('A new QR code was made.'), findsOneWidget);
      expect(
        tester.widget<QrCard>(find.byType(QrCard)).data,
        groupQrUrl(qr.groupQr.code),
      );
    });

    testWidgets('Share sends the group link', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await _pumpHost(
        tester,
        world,
        (context) => showGroupQrSheet(
          context,
          conversationId: 'group-1',
          title: 'Weekend climbers',
        ),
      );

      await tester.tap(find.byKey(const ValueKey('qr-share')));
      await _waitForPicture(tester, exporter);

      expect(
        exporter.shared.single.text,
        'Join my group on WeCord: ${groupQrUrl(sampleGroupCode)}',
      );
      expect(exporter.shared.single.name, 'wecord-group-qr');
    });

    testWidgets('someone who may not share it is told by the server', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      qr.failGroup = StateError('Only an owner or an admin can share');
      await _pumpHost(
        tester,
        world,
        (context) => showGroupQrSheet(
          context,
          conversationId: 'group-1',
          title: 'Weekend climbers',
        ),
      );

      expect(find.text("Couldn't load the QR code."), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
    });
  });

  group('how long a group code has left', () {
    final now = DateTime.utc(2026, 10, 18, 12);

    test('is told in days, hours or minutes', () {
      expect(
        groupQrExpiryLabel(now.add(const Duration(days: 7)), now: now),
        'Expires in 7 days',
      );
      expect(
        groupQrExpiryLabel(
          now.add(const Duration(days: 6, hours: 20)),
          now: now,
        ),
        'Expires in 7 days',
      );
      expect(
        groupQrExpiryLabel(now.add(const Duration(hours: 30)), now: now),
        'Expires in 2 days',
      );
      expect(
        groupQrExpiryLabel(now.add(const Duration(hours: 5)), now: now),
        'Expires in 5 hours',
      );
      expect(
        groupQrExpiryLabel(now.add(const Duration(minutes: 20)), now: now),
        'Expires within the hour',
      );
    });
  });
}
