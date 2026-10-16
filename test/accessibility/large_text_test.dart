// Rows that hold a fixed height clip their text at large text sizes. On
// desktop at 2.0x text, the sidebars' rows (circle channels, threads, the
// events entry, direct messages, friends and notifications, members) must
// grow with the text: every line of text inside a row fits in the row.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// The rows of a sidebar or list, found by the prefix of their key.
Finder _rows(List<String> prefixes) {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        prefixes.any((prefix) => key.value.startsWith(prefix));
  });
}

/// Fails for every paragraph inside [rows] that is taller than its row.
void expectTextFitsRows(WidgetTester tester, Finder rows) {
  expect(rows, findsWidgets, reason: 'no rows to check');
  final clipped = <String>[];
  for (final element in rows.evaluate()) {
    final row = element.renderObject! as RenderBox;
    void visit(RenderObject object) {
      if (object is RenderParagraph) {
        final box = object as RenderBox;
        // Where the text starts and ends inside the row. The paragraph's
        // own size is cut to what the row gave it, so ask what its lines
        // need.
        final top = box.localToGlobal(Offset.zero, ancestor: row).dy;
        final bottom = top + box.getMinIntrinsicHeight(box.size.width);
        if (top < -0.5 || bottom > row.size.height + 0.5) {
          clipped.add(
            '"${object.text.toPlainText()}" spans ${top.toStringAsFixed(1)}'
            '..${bottom.toStringAsFixed(1)} in a row ${row.size.height} tall '
            '(${element.widget.key})',
          );
        }
      }
      object.visitChildren(visit);
    }

    visit(row);
  }
  expect(clipped, isEmpty, reason: clipped.join('\n'));
}

void main() {
  /// Opens [route] as a macOS desktop window with 2.0x text, runs [check]
  /// and cleans up.
  Future<void> onDesktop(
    WidgetTester tester,
    String route,
    void Function() check,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      usePhoneViewport(tester, desktopLargeTextViewport);
      final world = PhoneWorld();
      await world.open(tester, route);
      await settle(tester);
      check();
      await world.close(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('circle channel, thread and events rows grow with the text', (
    tester,
  ) async {
    await onDesktop(
      tester,
      '/circles/circle-1',
      () => expectTextFitsRows(
        tester,
        _rows(['circle-channel-row-', 'circle-events-entry']),
      ),
    );
  });

  testWidgets('direct message and navigation rows grow with the text', (
    tester,
  ) async {
    await onDesktop(
      tester,
      '/home',
      () => expectTextFitsRows(
        tester,
        _rows(['home-dm-', 'home-friends', 'home-inbox', 'home-search']),
      ),
    );
  });

  testWidgets('member rows grow with the text', (tester) async {
    await onDesktop(
      tester,
      '/circles/circle-1',
      () => expectTextFitsRows(
        tester,
        _rows(['member-online-', 'member-offline-', 'member-timed-out-']),
      ),
    );
  });
}
