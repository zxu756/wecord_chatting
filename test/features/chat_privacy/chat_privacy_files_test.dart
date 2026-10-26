import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chat_privacy/chat_privacy_repository.dart';
import 'package:wecord/features/chats/file_message.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../file_preview/file_preview_fakes.dart';
import 'chat_privacy_fakes.dart';

const _attachment = FileAttachment(
  bucket: 'chat-files',
  path: 'conversation-1/plan.txt',
  name: 'plan.txt',
  mimeType: 'text/plain',
  size: 2048,
);

PreviewFile _file() => PreviewFile.fromFileAttachment(
  _attachment,
  messageId: 'm1',
  conversationId: 'conversation-1',
);

FakeChatPrivacyRepository _privacy({required bool restricted}) {
  return FakeChatPrivacyRepository(
    chats: restricted
        ? {
            'conversation-1': const ChatPrivacy(
              restricted: true,
              requestedBy: {'user-2'},
            ),
          }
        : const {},
  );
}

Widget _app(Widget Function(BuildContext) home, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: Builder(builder: home),
    ),
  );
}

/// What a chat that has advanced chat privacy on takes off its files: the
/// download button of a file message, and Download, Share, Open in and Copy
/// text in the file viewer. The server refuses nothing here (the file is
/// readable to anyone in the chat), so the app must not offer what would look
/// like keeping a secret.
void main() {
  group('a file message', () {
    Widget message(List<Override> overrides) => _app(
      (context) => const Scaffold(
        body: FileMessageContent(
          attachment: _attachment,
          textColor: Colors.black,
          messageId: 'm1',
          conversationId: 'conversation-1',
        ),
      ),
      [...filePreviewOverrides(), ...overrides],
    );

    final download = find.byKey(
      const ValueKey('file-message-download-conversation-1/plan.txt'),
    );

    testWidgets('has its download button in an open chat', (tester) async {
      await tester.pumpWidget(
        message([
          chatPrivacyRepositoryProvider.overrideWithValue(
            _privacy(restricted: false),
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(download, findsOneWidget);
    });

    testWidgets('has none in a restricted chat', (tester) async {
      await tester.pumpWidget(
        message([
          chatPrivacyRepositoryProvider.overrideWithValue(
            _privacy(restricted: true),
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('plan.txt'), findsOneWidget);
      expect(download, findsNothing);
    });
  });

  group('the file viewer', () {
    Future<FakeFileActions> open(
      WidgetTester tester, {
      required bool restricted,
    }) async {
      final actions = FakeFileActions();
      await tester.pumpWidget(
        _app(
          (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    unawaited(openFilePreview(context, file: _file())),
                child: const Text('open'),
              ),
            ),
          ),
          [
            ...filePreviewOverrides(actions: actions),
            chatPrivacyRepositoryProvider.overrideWithValue(
              _privacy(restricted: restricted),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      // The setting is read once the viewer asks for it.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      return actions;
    }

    testWidgets('offers Download, Share and Open in in an open chat', (
      tester,
    ) async {
      await open(tester, restricted: false);
      expect(find.byTooltip('Download'), findsOneWidget);
      expect(find.byTooltip('Share'), findsOneWidget);
      expect(find.byTooltip('Open in…'), findsOneWidget);
    });

    testWidgets('offers none of them in a restricted chat', (tester) async {
      final actions = await open(tester, restricted: true);
      expect(
        find.byKey(const ValueKey('file-preview-top-bar')),
        findsOneWidget,
      );
      expect(find.byTooltip('Download'), findsNothing);
      expect(find.byTooltip('Share'), findsNothing);
      expect(find.byTooltip('Open in…'), findsNothing);
      expect(actions.saved, isEmpty);
    });
  });
}
