import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/composer_drafts.dart';

import '../../mobile/phone_test_support.dart';

void main() {
  void seedDrafts(PhoneWorld world) {
    world.draftStore.drafts['user-1'] = {
      'conv-general': const ComposerDraft(text: 'See you at the trailhead'),
      'conv-ann': const ComposerDraft(text: 'Reminder:\n  bring   snacks'),
      'conv-random': const ComposerDraft(text: 'that meme though'),
      // Only a reply, no text: nothing to show.
      'conv-help': const ComposerDraft(text: ' ', replyToMessageId: 'm1'),
    };
  }

  Finder draftIn(String channelId) => find.descendant(
    of: find.byKey(ValueKey('circle-channel-row-$channelId')),
    matching: find.byKey(const ValueKey('channel-draft')),
  );

  String draftText(WidgetTester tester, String channelId) =>
      tester.widget<Text>(draftIn(channelId)).textSpan!.toPlainText();

  phoneTestWidgets('channel rows show their drafts', (tester, viewport) async {
    final world = PhoneWorld();
    seedDrafts(world);
    await world.open(tester, '/circles/circle-1');

    expect(draftText(tester, 'ch-ann'), 'Draft Reminder: bring snacks');
    expect(draftText(tester, 'ch-general'), 'Draft See you at the trailhead');
    expect(draftIn('ch-help'), findsNothing);
    expect(draftIn('ch-photos'), findsNothing);

    // A short name keeps all of itself next to the draft.
    final shortName = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byKey(const ValueKey('circle-channel-row-ch-general')),
        matching: find.text('general'),
      ),
    );
    if (viewport != notchedPhoneLargeText) {
      expect(shortName.didExceedMaxLines, isFalse);
    }
    // A long name still leaves room for "Draft".
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('circle-channel-row-ch-random')),
    );
    final row = tester.getRect(
      find.byKey(const ValueKey('circle-channel-row-ch-random')),
    );
    final draft = tester.getRect(draftIn('ch-random'));
    expect(draft.width, greaterThan(row.width * 0.2));
  });

  testWidgets('the open channel on desktop keeps its draft in the composer', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      usePhoneViewport(
        tester,
        const PhoneViewport(
          name: 'desktop',
          size: Size(1440, 900),
          devicePixelRatio: 1,
        ),
      );
      final world = PhoneWorld();
      seedDrafts(world);
      await world.open(tester, '/circles/circle-1');

      // general is open: its draft is in the composer, not the sidebar.
      expect(draftIn('ch-general'), findsNothing);
      expect(draftText(tester, 'ch-ann'), 'Draft Reminder: bring snacks');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
