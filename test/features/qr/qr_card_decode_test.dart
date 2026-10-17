import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/qr/qr_card.dart';
import 'package:wecord/features/qr/qr_image_decoder.dart';
import 'package:wecord/features/qr/qr_image_export.dart';
import 'package:wecord/features/qr/qr_links.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

const _code = 'abcd2345efgh6789';

/// The card as people save it: pumps it, takes its picture and reads the
/// QR code back out of the picture, the way "Choose from photos" does.
Future<Uint8List> _cardPicture(
  WidgetTester tester, {
  required ThemeData theme,
  required String data,
  double pixelRatio = 3,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: QrCard(
              data: data,
              title: 'Ada Lovelace',
              subtitle: '@ada',
              hint: 'Scan to add me on WeCord',
              avatarBuilder: (size) => PersonAvatar(name: 'Ada', size: size),
            ),
          ),
        ),
      ),
    ),
  );
  final png = await tester.runAsync(
    () => captureBoundaryPng(key, pixelRatio: pixelRatio),
  );
  return png!;
}

void main() {
  for (final (name, theme) in [
    ('light', WeCordTheme.light()),
    ('dark', WeCordTheme.dark()),
  ]) {
    testWidgets('the saved $name card carries a code that reads back', (
      tester,
    ) async {
      final link = userQrUrl(_code, site: 'https://wecord.jokebear.fyi');
      final png = await _cardPicture(tester, theme: theme, data: link);
      final text = await tester.runAsync(() => decodeQrFromImageBytes(png));
      expect(text, link);
      expect(parseScannedText(text!), const UserQrLink(_code));
    });
  }

  testWidgets('a group card reads back at a smaller picture size', (
    tester,
  ) async {
    final link = groupQrUrl(_code, site: 'https://wecord.jokebear.fyi');
    final png = await _cardPicture(
      tester,
      theme: WeCordTheme.light(),
      data: link,
      pixelRatio: 2,
    );
    final text = await tester.runAsync(() => decodeQrFromImageBytes(png));
    expect(parseScannedText(text!), const GroupQrLink(_code));
  });

  testWidgets('a picture without a code reads as nothing', (tester) async {
    final png = await tester.runAsync(() async {
      // A small blank PNG.
      return Uint8List.fromList(_blankPng);
    });
    final text = await tester.runAsync(() => decodeQrFromImageBytes(png!));
    expect(text, isNull);
    final garbage = await tester.runAsync(
      () => decodeQrFromImageBytes(Uint8List.fromList([1, 2, 3, 4])),
    );
    expect(garbage, isNull);
  });
}

/// A 1x1 white PNG.
const _blankPng = <int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xff, 0xff, 0x3f,
  0x00, 0x05, 0xfe, 0x02, 0xfe, 0xa7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
];
