import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/qr/qr_camera.dart';
import 'package:wecord/features/qr/qr_repository.dart';

import '../../mobile/phone_test_support.dart';
import 'qr_fakes.dart';

const _site = 'https://wecord.jokebear.fyi';

/// Where the app is now.
String _location(PhoneWorld world) => world.router.state.uri.toString();

void main() {
  late PhoneWorld world;
  late FakeQrRepository qr;
  late FakeQrCamera camera;
  late FakeUrlLauncher launcher;
  late Uint8List? pickedBytes;
  String? decoded;

  setUp(() {
    world = PhoneWorld();
    qr = FakeQrRepository()
      ..users[sampleUserCode] = const QrProfile(
        id: 'user-2',
        username: 'bart',
        displayName: 'Bart',
      );
    camera = FakeQrCamera();
    launcher = FakeUrlLauncher();
    pickedBytes = null;
    decoded = null;
    world.extraOverrides = qrOverrides(
      repository: qr,
      camera: camera,
      launcher: launcher,
      decoder: (bytes) async {
        pickedBytes = bytes;
        return decoded;
      },
    );
  });

  /// Opens Friends and taps Scan in Add friend.
  Future<void> openScanner(WidgetTester tester) async {
    await world.open(tester, '/contacts');
    await tester.tap(find.byKey(const ValueKey('add-friend-scan')));
    await settle(tester);
  }

  group('Scan', () {
    testWidgets('is in Add friend, with My QR code beside it', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await world.open(tester, '/contacts');
      expect(find.byKey(const ValueKey('add-friend-scan')), findsOneWidget);
      expect(find.byKey(const ValueKey('add-friend-my-qr')), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('is in the + menu on the phone home', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await world.open(tester, '/home');
      await tester.tap(find.byKey(const ValueKey('phone-home-new')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('phone-new-scan')));
      await settle(tester);
      expect(find.byKey(const ValueKey('qr-scanner-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-camera')), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('is in Settings, with My QR code and the pat suffix', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      await world.open(tester, '/me');
      expect(find.byKey(const ValueKey('settings-my-qr')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-scan')), findsOneWidget);
      expect(find.byKey(const ValueKey('pat-suffix-row')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-my-qr')));
      await settle(tester);
      expect(find.byKey(const ValueKey('my-qr-sheet')), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('a person\'s code opens their profile', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openScanner(tester);

      camera.onCode!('$_site/u/$sampleUserCode');
      await settle(tester);

      expect(qr.resolved, [sampleUserCode]);
      expect(_location(world), '/profile/user-2?source=qr');
      expect(find.byKey(const ValueKey('qr-scanner-sheet')), findsNothing);
      await world.close(tester);
    });

    testWidgets('a code that leads nowhere says so', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openScanner(tester);

      camera.onCode!('$_site/u/zzzz2345zzzz6789');
      await settle(tester);

      expect(_location(world), '/contacts');
      expect(
        find.text("This QR code doesn't work. It may have been reset."),
        findsOneWidget,
      );
      await world.close(tester);
    });

    testWidgets('a broken connection says so', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      qr.failResolve = StateError('offline');
      await openScanner(tester);

      camera.onCode!('$_site/u/$sampleUserCode');
      await settle(tester);

      expect(
        find.text("Couldn't open the QR code. Try again."),
        findsOneWidget,
      );
      await world.close(tester);
    });

    testWidgets('a group\'s code opens the join page', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openScanner(tester);

      camera.onCode!('$_site/g/$sampleGroupCode');
      await settle(tester);

      expect(_location(world), '/g/$sampleGroupCode');
      expect(find.byKey(const ValueKey('group-qr-join')), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('a circle invite opens the join flow', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openScanner(tester);

      camera.onCode!('/invite/Ab3dEf5hJk');
      await settle(tester);

      expect(_location(world), '/invite/ab3def5hjk');
      await world.close(tester);
    });

    testWidgets('a call link opens the call', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openScanner(tester);

      camera.onCode!('$_site/call/abcd2345efgh');
      await settle(tester);

      expect(_location(world), '/call/abcd2345efgh');
      await world.close(tester);
    });

    testWidgets('anything else is shown, to copy or open', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openScanner(tester);

      camera.onCode!('https://example.com/menu');
      await settle(tester);

      expect(find.byKey(const ValueKey('scanned-text-sheet')), findsOneWidget);
      expect(find.text('https://example.com/menu'), findsOneWidget);
      expect(
        find.textContaining('This link is not from WeCord'),
        findsOneWidget,
      );

      // Copy puts it on the clipboard.
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('scanned-copy')));
      await settle(tester);
      expect(copied, 'https://example.com/menu');
      expect(find.text('Copied'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('scanned-open')));
      await settle(tester);
      expect(launcher.opened, [Uri.parse('https://example.com/menu')]);
      await world.close(tester);
    });

    testWidgets('plain text can only be copied', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openScanner(tester);

      camera.onCode!('table 12, order 7');
      await settle(tester);

      expect(find.text('table 12, order 7'), findsOneWidget);
      expect(find.byKey(const ValueKey('scanned-copy')), findsOneWidget);
      expect(find.byKey(const ValueKey('scanned-open')), findsNothing);
      await world.close(tester);
    });

    testWidgets('a link that cannot be opened says so', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      launcher.succeeds = false;
      await openScanner(tester);
      camera.onCode!('https://example.com/menu');
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('scanned-open')));
      await settle(tester);
      expect(find.text("Couldn't open the link."), findsOneWidget);
      await world.close(tester);
    });
  });

  group('Choose from photos', () {
    testWidgets('reads the code in the picture', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      world.imagePicker.nextImage = ChatImageUpload(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'screenshot.png',
        mimeType: 'image/png',
      );
      decoded = '$_site/u/$sampleUserCode';
      await openScanner(tester);

      await tester.tap(find.byKey(const ValueKey('qr-choose-photo')));
      await settle(tester);

      expect(pickedBytes, [1, 2, 3]);
      expect(_location(world), '/profile/user-2?source=qr');
      await world.close(tester);
    });

    testWidgets('says when the picture has no code', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      world.imagePicker.nextImage = ChatImageUpload(
        bytes: Uint8List.fromList([1]),
        fileName: 'cat.jpg',
        mimeType: 'image/jpeg',
      );
      await openScanner(tester);

      await tester.tap(find.byKey(const ValueKey('qr-choose-photo')));
      await settle(tester);

      expect(find.text('No QR code found in that picture.'), findsOneWidget);
      // Still scanning: the sheet stays.
      expect(find.byKey(const ValueKey('qr-scanner-sheet')), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('closing the picker changes nothing', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      world.imagePicker.nextImage = null;
      await openScanner(tester);

      await tester.tap(find.byKey(const ValueKey('qr-choose-photo')));
      await settle(tester);

      expect(world.imagePicker.pickCalls, 1);
      expect(find.text('No QR code found in that picture.'), findsNothing);
      expect(find.byKey(const ValueKey('qr-scanner-sheet')), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('a picture that cannot be opened says so', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      world.imagePicker.pickError = StateError('unreadable');
      await openScanner(tester);

      await tester.tap(find.byKey(const ValueKey('qr-choose-photo')));
      await settle(tester);

      expect(
        find.text("Couldn't open that picture. Try another."),
        findsOneWidget,
      );
      await world.close(tester);
    });
  });

  group('without a camera', () {
    testWidgets('permission denied is explained, photos still work', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      camera.failWith = QrCameraProblem.permissionDenied;
      await openScanner(tester);

      expect(find.text('Camera access is off'), findsOneWidget);
      expect(find.textContaining('system settings'), findsOneWidget);
      expect(find.byKey(const ValueKey('qr-choose-photo')), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('no camera at all is explained', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      camera.failWith = QrCameraProblem.unavailable;
      await openScanner(tester);

      expect(find.text('No camera available'), findsOneWidget);
      await world.close(tester);
    });
  });

  group('QR links opened in the app', () {
    testWidgets('/u/<code> replaces itself with the profile', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await world.open(tester, '/u/$sampleUserCode');
      expect(_location(world), '/profile/user-2?source=qr');
      await world.close(tester);
    });

    testWidgets('/u/<code> that leads nowhere says so', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await world.open(tester, '/u/zzzz2345zzzz6789');
      expect(find.text("This QR code doesn't work"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('qr-link-home')));
      await settle(tester);
      expect(_location(world), '/home');
      await world.close(tester);
    });

    testWidgets('/u/<code> without a connection can be tried again', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      qr.failResolve = StateError('offline');
      await world.open(tester, '/u/$sampleUserCode');
      expect(find.text('Could not open the QR code'), findsOneWidget);
      qr.failResolve = null;
      await tester.tap(find.byKey(const ValueKey('qr-link-retry')));
      await settle(tester);
      expect(_location(world), '/profile/user-2?source=qr');
      await world.close(tester);
    });

    testWidgets('/g/<code> shows the group and joins it', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await world.open(tester, '/g/$sampleGroupCode');

      expect(find.text('Weekend climbers'), findsOneWidget);
      expect(find.text('12 members'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('group-qr-join')));
      await settle(tester);

      expect(qr.joined, [sampleGroupCode]);
      expect(_location(world), '/chats/group-1');
      await world.close(tester);
    });

    testWidgets('/g/<code> of a group you are in opens the chat', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      qr.preview = const GroupQrPreview(
        state: GroupQrState.expired,
        conversationId: 'group-1',
        title: 'Weekend climbers',
        memberCount: 12,
        isMember: true,
      );
      await world.open(tester, '/g/$sampleGroupCode');

      expect(find.text("You're already in this group."), findsOneWidget);
      expect(find.byKey(const ValueKey('group-qr-join')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('group-qr-open')));
      await settle(tester);
      expect(_location(world), '/chats/group-1');
      await world.close(tester);
    });

    testWidgets('/g/<code> that ran out says so', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      qr.preview = const GroupQrPreview(state: GroupQrState.expired);
      await world.open(tester, '/g/$sampleGroupCode');

      expect(find.text('This group QR code has expired'), findsOneWidget);
      expect(find.text('Ask a group admin for a new one.'), findsOneWidget);
      expect(find.byKey(const ValueKey('group-qr-join')), findsNothing);
      await world.close(tester);
    });

    testWidgets('/g/<code> that does not exist shows nothing of a group', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      qr.preview = const GroupQrPreview(state: GroupQrState.notFound);
      await world.open(tester, '/g/$sampleGroupCode');

      expect(find.text("This group QR code doesn't work"), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('a join that fails says so and can be tried again', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      qr.failJoin = StateError('offline');
      await world.open(tester, '/g/$sampleGroupCode');

      await tester.tap(find.byKey(const ValueKey('group-qr-join')));
      await settle(tester);
      expect(find.text("Couldn't join the group. Try again."), findsOneWidget);

      qr.failJoin = null;
      await tester.tap(find.byKey(const ValueKey('group-qr-join')));
      await settle(tester);
      expect(_location(world), '/chats/group-1');
      await world.close(tester);
    });

    testWidgets('a code that ran out while the page was open is reloaded', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      qr.join = const GroupQrJoin(state: GroupQrJoinState.expired);
      await world.open(tester, '/g/$sampleGroupCode');

      qr.preview = const GroupQrPreview(state: GroupQrState.expired);
      await tester.tap(find.byKey(const ValueKey('group-qr-join')));
      await settle(tester);

      expect(find.text('This group QR code has expired'), findsOneWidget);
      await world.close(tester);
    });
  });
}
