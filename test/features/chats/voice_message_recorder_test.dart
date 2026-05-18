import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'production voice recorder uses the web-compatible stream API',
    () async {
      final source = await File(
        'lib/features/chats/voice_message_recorder.dart',
      ).readAsString();

      expect(source, isNot(contains("import 'dart:io';")));
      expect(source, contains('startStream'));
      expect(source, isNot(contains('Directory.systemTemp')));
      expect(source, isNot(contains('File(')));
    },
  );
}
