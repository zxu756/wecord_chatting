import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/error_reports/error_scrubber.dart';

const _jwt =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
    'eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4ifQ.'
    'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';

void main() {
  group('message', () {
    test('removes JWTs, bearer headers and key=value secrets', () {
      final out = ErrorScrubber.message(
        'Failed with $_jwt and Authorization: Bearer abcDEF123456 '
        'apikey=sb_publishable_abc123 refresh_token: r3fr3sh',
      );
      expect(out, isNot(contains('eyJ')));
      expect(out, isNot(contains('abcDEF123456')));
      expect(out, isNot(contains('sb_publishable')));
      expect(out, isNot(contains('r3fr3sh')));
      expect(out, contains('<token>'));
    });

    test('removes emails, phone numbers and long numbers', () {
      final out = ErrorScrubber.message(
        'No user ada.lovelace+x@example.co.uk, call +1 (415) 555-0100, '
        'id 12345678901',
      );
      expect(out, isNot(contains('ada')));
      expect(out, isNot(contains('example')));
      expect(out, isNot(contains('415')));
      expect(out, isNot(contains('12345678901')));
    });

    test('keeps a URL down to its host: no path, file name or query', () {
      final out = ErrorScrubber.message(
        'GET https://abc.supabase.co/storage/v1/object/sign/chat/secret_plans.pdf'
        '?token=$_jwt failed',
      );
      expect(out, contains('https://abc.supabase.co'));
      expect(out, isNot(contains('secret_plans')));
      expect(out, isNot(contains('storage')));
      expect(out, isNot(contains('token=')));
    });

    test('removes local paths and file names', () {
      expect(
        ErrorScrubber.message(
          'Cannot open /Users/ada/Documents/Taxes 2025/return.pdf now',
        ),
        allOf(isNot(contains('ada')), isNot(contains('return.pdf'))),
      );
      expect(
        ErrorScrubber.message(r'Cannot open C:\Users\ada\Pictures\me.png'),
        isNot(contains('me.png')),
      );
      expect(
        ErrorScrubber.message('Missing file:///home/ada/notes.txt'),
        isNot(contains('notes.txt')),
      );
    });

    test('drops quoted text (user content) but keeps Dart type wording', () {
      final out = ErrorScrubber.message(
        'Exception: could not send "hello my password is hunter2" to \'Bob\'',
      );
      expect(out, isNot(contains('hunter2')));
      expect(out, isNot(contains('Bob')));
      expect(
        ErrorScrubber.message(
          "type 'Null' is not a subtype of type 'String' in type cast",
        ),
        "type 'Null' is not a subtype of type 'String' in type cast",
      );
      expect(
        ErrorScrubber.message("The method 'send' was called on null."),
        "The method 'send' was called on null.",
      );
    });

    test('keeps only the first line and cuts it', () {
      final out = ErrorScrubber.message(
        'First line\nSecond line has secrets',
        maxLength: 8,
      );
      expect(out, 'First l…');
      expect(
        ErrorScrubber.message('Bad state: No element\nmore'),
        'Bad state: No element',
      );
    });

    test('keeps error codes and ordinary words', () {
      expect(
        ErrorScrubber.message('PostgrestException code=42883 function missing'),
        'PostgrestException code=42883 function missing',
      );
    });

    test('long opaque strings and UUIDs are removed', () {
      final out = ErrorScrubber.message(
        'room 8f14e45f-ceea-467a-9d1e-0123456789ab key '
        'A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6',
      );
      expect(out, isNot(contains('8f14e45f')));
      expect(out, isNot(contains('A1b2C3')));
    });
  });

  group('stack', () {
    test('keeps functions and package/dart libraries, drops local paths', () {
      const trace = '''
#0      _ChatState._send (package:wecord/features/chats/chat.dart:42:7)
#1      State.setState (package:flutter/src/widgets/framework.dart:1200:9)
#2      main (file:///Users/ada/dev/wecord/lib/main.dart:10:3)
#3      _rootRun (dart:async/zone.dart:1399:13)
#4      foo (/Users/ada/dev/secret_project/lib/x.dart:1:1)
#5      Object.bar (https://wecord.app/assets/private/main.dart.js:123:45)
<asynchronous suspension>''';
      final out = ErrorScrubber.stack(trace);
      expect(out, contains('_ChatState._send'));
      expect(out, contains('package:wecord/features/chats/chat.dart:42:7'));
      expect(out, contains('dart:async/zone.dart:1399:13'));
      expect(out, contains('<asynchronous suspension>'));
      expect(out, isNot(contains('/Users')));
      expect(out, isNot(contains('ada')));
      expect(out, isNot(contains('secret_project')));
      expect(out, isNot(contains('private')));
    });

    test('is cut to 8 KB on a line boundary', () {
      final trace = [
        for (var i = 0; i < 2000; i++)
          '#$i      Frame$i (package:wecord/a/b.dart:$i:1)',
      ].join('\n');
      final out = ErrorScrubber.stack(trace);
      expect(utf8.encode(out).length, lessThanOrEqualTo(8192));
      expect(utf8.encode(out).length, greaterThan(8000));
      expect(out.split('\n').last, endsWith(')'));
    });

    test('a trace from --split-debug-info keeps what symbolizing needs', () {
      // The shape of a stack in a release build made with
      // --split-debug-info: no names, only addresses, and a header that says
      // which build it came from. tool/errors_report.sh --symbolize needs the
      // header and every frame as they are.
      const trace = '''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 4242, tid: 9001, name 1.ui
os: ios arch: arm64 comp: no sim: no
build_id: 'a1b2c3d4e5f60718293a4b5c6d7e8f90'
isolate_dso_base: 1048a8000, vm_dso_base: 1048a8000
isolate_instructions: 1048b5000, vm_instructions: 1048ae000
    #00 abs 00000001049f5bd3 virt 000000000014dbd3 _kDartIsolateSnapshotInstructions+0x1234
    #01 abs 00000001049f5c11 virt 000000000014dc11 _kDartIsolateSnapshotInstructions+0x4d6''';
      final out = ErrorScrubber.stack(trace);
      expect(out, contains("build_id: 'a1b2c3d4e5f60718293a4b5c6d7e8f90'"));
      expect(out, contains('isolate_dso_base: 1048a8000'));
      expect(out, contains('isolate_instructions: 1048b5000'));
      expect(
        out,
        contains(
          '#00 abs 00000001049f5bd3 virt 000000000014dbd3 '
          '_kDartIsolateSnapshotInstructions+0x1234',
        ),
      );
      expect(out, contains('#01 abs 00000001049f5c11'));
      expect(out.split('\n').first, startsWith('*** ***'));
    });

    test('removes tokens that appear in a frame', () {
      final out = ErrorScrubber.stack('#0 f (package:a/b.dart:1:1) $_jwt');
      expect(out, isNot(contains('eyJ')));
    });
  });

  group('fingerprint', () {
    String fp(String message, {String stack = '', String kind = 'k'}) =>
        ErrorScrubber.fingerprint(
          kind: kind,
          type: 'T',
          message: message,
          stack: stack,
        );

    test('is 16 hex characters and stable', () {
      expect(fp('a'), matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(fp('a'), fp('a'));
    });

    test('ignores numbers and line numbers', () {
      expect(fp('failed 3 times'), fp('failed 17 times'));
      expect(
        fp('x', stack: '#0 f (package:a/b.dart:10:2)'),
        fp('x', stack: '#0 f (package:a/b.dart:99:5)'),
      );
    });

    test('differs by kind, message and top frames', () {
      expect(fp('a'), isNot(fp('b')));
      expect(fp('a', kind: 'x'), isNot(fp('a', kind: 'y')));
      expect(
        fp('a', stack: '#0 f (package:a/b.dart:1:1)'),
        isNot(fp('a', stack: '#0 g (package:a/b.dart:1:1)')),
      );
    });
  });

  group('route', () {
    test('keeps words and hides ids, codes and the query', () {
      expect(ErrorScrubber.route('/settings/devices'), '/settings/devices');
      expect(
        ErrorScrubber.route(
          '/chats/8f14e45f-ceea-467a-9d1e-0123456789ab?x=ada@example.com',
        ),
        '/chats/:id',
      );
      expect(ErrorScrubber.route('/call/Ab12Cd'), '/call/:id');
      expect(ErrorScrubber.route('/'), '/');
    });
  });
}
