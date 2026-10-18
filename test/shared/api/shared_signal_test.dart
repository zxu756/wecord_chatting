import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/api/shared_signal.dart';

void main() {
  /// A source that records how often it was opened and closed.
  ({SharedSignal signal, void Function() fire, List<String> log}) make({
    Duration window = const Duration(milliseconds: 300),
  }) {
    final log = <String>[];
    void Function()? notify;
    final signal = SharedSignal((n) {
      log.add('open');
      notify = n;
      return () {
        log.add('close');
        notify = null;
      };
    }, window: window);
    return (signal: signal, fire: () => notify?.call(), log: log);
  }

  test('many listeners share one source, opened by the first and closed by '
      'the last', () {
    fakeAsync((async) {
      final source = make();
      expect(source.log, isEmpty);

      final first = source.signal.stream.listen((_) {});
      final second = source.signal.stream.listen((_) {});
      final third = source.signal.stream.listen((_) {});
      expect(source.log, ['open']);

      unawaited(first.cancel());
      unawaited(second.cancel());
      async.flushMicrotasks();
      expect(source.log, ['open']);

      unawaited(third.cancel());
      async.flushMicrotasks();
      expect(source.log, ['open', 'close']);

      // Listening again opens it again.
      final again = source.signal.stream.listen((_) {});
      expect(source.log, ['open', 'close', 'open']);
      unawaited(again.cancel());
    });
  });

  test('every listener hears every change', () {
    fakeAsync((async) {
      final source = make();
      var a = 0;
      var b = 0;
      final first = source.signal.stream.listen((_) => a++);
      final second = source.signal.stream.listen((_) => b++);

      source.fire();
      async.flushMicrotasks();
      expect((a, b), (1, 1));

      unawaited(first.cancel());
      unawaited(second.cancel());
    });
  });

  test('a burst is one change at once and one more when the window ends', () {
    fakeAsync((async) {
      final source = make();
      var heard = 0;
      final subscription = source.signal.stream.listen((_) => heard++);

      for (var i = 0; i < 20; i++) {
        source.fire();
        async.elapse(const Duration(milliseconds: 10));
      }
      // The first went out at once; the other 19 wait for the window's end.
      expect(heard, 1);
      async.elapse(const Duration(milliseconds: 300));
      expect(heard, 2);

      // The window the merged change opened passes quietly; the next
      // change is immediate again.
      async.elapse(const Duration(milliseconds: 300));
      expect(heard, 2);
      source.fire();
      async.flushMicrotasks();
      expect(heard, 3);
      async.elapse(const Duration(seconds: 1));
      expect(heard, 3);

      unawaited(subscription.cancel());
    });
  });

  test('a change after the last listener left is not delivered later', () {
    fakeAsync((async) {
      final source = make();
      var heard = 0;
      final subscription = source.signal.stream.listen((_) => heard++);
      source.fire();
      source.fire();
      async.flushMicrotasks();
      unawaited(subscription.cancel());
      async.elapse(const Duration(seconds: 1));
      expect(heard, 1);
    });
  });
}
