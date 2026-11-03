import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/watch_together/watch_protocol.dart';

List<int> _json(Map<String, Object?> map) => utf8.encode(jsonEncode(map));

WatchLink _link(String url) => parseWatchLink(url).link!;

void main() {
  group('links', () {
    test('files and streams the app can play are told apart', () {
      expect(
        _link('https://cdn.example.com/a/movie.mp4').kind,
        WatchLinkKind.video,
      );
      expect(
        _link('https://cdn.example.com/a/MOVIE.MOV').kind,
        WatchLinkKind.video,
      );
      expect(
        _link('https://cdn.example.com/a.webm?token=1').kind,
        WatchLinkKind.video,
      );
      expect(
        _link('https://cdn.example.com/live/index.m3u8').kind,
        WatchLinkKind.hls,
      );
      expect(
        _link('https://cdn.example.com/song.mp3').kind,
        WatchLinkKind.audio,
      );
      expect(
        _link('https://cdn.example.com/song.m4a').kind,
        WatchLinkKind.audio,
      );
      for (final link in [
        'https://cdn.example.com/a.mp4',
        'https://cdn.example.com/a.m3u8',
        'https://cdn.example.com/a.flac',
      ]) {
        expect(_link(link).synced, isTrue);
      }
    });

    test('anything else is a web page that can not be kept in step', () {
      for (final url in [
        'https://www.youtube.com/watch?v=abc',
        'https://youtu.be/abc',
        'https://www.bilibili.com/video/BV1xx',
        'https://example.com/',
        'https://example.com/folder.mp4/page',
      ]) {
        final link = _link(url);
        expect(link.kind, WatchLinkKind.webPage, reason: url);
        expect(link.synced, isFalse);
      }
    });

    test('only https links to public hosts are accepted', () {
      WatchLinkProblem? problem(String text) => parseWatchLink(text).problem;
      expect(problem(''), WatchLinkProblem.empty);
      expect(problem('   '), WatchLinkProblem.empty);
      expect(problem('http://example.com/a.mp4'), WatchLinkProblem.notHttps);
      expect(problem('ftp://example.com/a.mp4'), WatchLinkProblem.invalid);
      expect(problem('javascript:alert(1)'), WatchLinkProblem.invalid);
      expect(problem('file:///etc/passwd'), WatchLinkProblem.invalid);
      expect(problem('example.com/a.mp4'), WatchLinkProblem.invalid);
      expect(
        problem('https://user:pw@example.com/a.mp4'),
        WatchLinkProblem.invalid,
      );
      expect(
        problem('https://localhost/a.mp4'),
        WatchLinkProblem.privateAddress,
      );
      expect(
        problem('https://box.local/a.mp4'),
        WatchLinkProblem.privateAddress,
      );
      expect(problem('https://printer/a.mp4'), WatchLinkProblem.privateAddress);
      expect(
        problem('https://192.168.1.4/a.mp4'),
        WatchLinkProblem.privateAddress,
      );
      expect(
        problem('https://10.0.0.2/a.mp4'),
        WatchLinkProblem.privateAddress,
      );
      expect(
        problem('https://127.0.0.1/a.mp4'),
        WatchLinkProblem.privateAddress,
      );
      expect(
        problem('https://169.254.169.254/latest'),
        WatchLinkProblem.privateAddress,
      );
      expect(
        problem('https://172.20.1.1/a.mp4'),
        WatchLinkProblem.privateAddress,
      );
      expect(problem('https://[::1]/a.mp4'), WatchLinkProblem.privateAddress);
      expect(
        problem('https://2130706433/a.mp4'),
        WatchLinkProblem.privateAddress,
      );
      expect(problem('https://${'a' * 2100}.com/'), WatchLinkProblem.tooLong);
      // A public address is fine.
      expect(parseWatchLink('https://93.184.216.34/a.mp4').link, isNotNull);
      expect(parseWatchLink('https://172.32.0.1/a.mp4').link, isNotNull);
    });

    test('the fragment is dropped and spaces around the link are ignored', () {
      final link = _link('  https://example.com/a.mp4#t=30  ');
      expect(link.text, 'https://example.com/a.mp4');
    });

    test('a title falls back to the file name, or the site', () {
      expect(
        _link('https://cdn.example.com/m/Night%20Train.mp4').fallbackTitle,
        'Night Train.mp4',
      );
      expect(
        _link('https://www.youtube.com/watch?v=1').fallbackTitle,
        'www.youtube.com',
      );
    });

    test('titles lose control and direction characters and are cut', () {
      expect(
        tidyWatchTitle('  Movie\u202E night\u0007\n\n  two  '),
        'Movie night two',
      );
      expect(tidyWatchTitle('x' * 200).length, maxWatchTitleChars);
    });
  });

  group('packets', () {
    final sent = DateTime.fromMillisecondsSinceEpoch(1760000000000);

    test('a start survives the trip', () {
      final bytes = encodeWatchStart(
        id: 'abc-123',
        link: _link('https://cdn.example.com/a.mp4'),
        title: 'Movie night',
        positionMs: 42000,
        playing: true,
        seq: 3,
        sentAt: sent,
      );
      final packet = decodeWatchPacket(bytes) as WatchStartPacket;
      expect(packet.id, 'abc-123');
      expect(packet.link.text, 'https://cdn.example.com/a.mp4');
      expect(packet.link.kind, WatchLinkKind.video);
      expect(packet.title, 'Movie night');
      expect(packet.positionMs, 42000);
      expect(packet.playing, isTrue);
      expect(packet.seq, 3);
      expect(packet.sentAt, sent);
    });

    test('a sync survives the trip, for every cause', () {
      for (final cause in WatchCause.values) {
        final bytes = encodeWatchSync(
          id: 'abc',
          cause: cause,
          positionMs: 1500,
          playing: cause == WatchCause.play,
          seq: 9,
          sentAt: sent,
        );
        final packet = decodeWatchPacket(bytes) as WatchSyncPacket;
        expect(packet.cause, cause);
        expect(packet.positionMs, 1500);
        expect(packet.playing, cause == WatchCause.play);
        expect(packet.seq, 9);
      }
    });

    test('an end and an ask survive the trip', () {
      final end = decodeWatchPacket(encodeWatchEnd(id: 'abc', seq: 4));
      expect(end, isA<WatchEndPacket>());
      expect((end as WatchEndPacket).id, 'abc');
      expect(decodeWatchPacket(encodeWatchAsk()), isA<WatchAskPacket>());
    });

    test('an encoded position is kept inside the allowed range', () {
      final bytes = encodeWatchSync(
        id: 'abc',
        cause: WatchCause.seek,
        positionMs: -5,
        playing: false,
        seq: 1,
        sentAt: sent,
      );
      expect((decodeWatchPacket(bytes) as WatchSyncPacket).positionMs, 0);
    });

    test('bad packets are dropped', () {
      Map<String, Object?> sync() => {
        'v': 1,
        'k': 'y',
        'id': 'abc',
        'c': 'beat',
        'p': 1000,
        'r': 1,
        'n': 1,
        'ts': 1760000000000,
      };
      expect(decodeWatchPacket(_json(sync())), isA<WatchSyncPacket>());

      expect(decodeWatchPacket(utf8.encode('not json')), isNull);
      expect(decodeWatchPacket(utf8.encode('[1,2]')), isNull);
      expect(decodeWatchPacket(const <int>[0xff, 0xfe, 0x00]), isNull);
      expect(decodeWatchPacket(_json({...sync(), 'v': 2})), isNull);
      expect(decodeWatchPacket(_json({...sync(), 'k': 'zz'})), isNull);
      expect(decodeWatchPacket(_json({...sync(), 'c': 'rewind'})), isNull);
      expect(decodeWatchPacket(_json({...sync(), 'id': ''})), isNull);
      expect(decodeWatchPacket(_json({...sync(), 'id': 'a b'})), isNull);
      expect(decodeWatchPacket(_json({...sync(), 'id': 'x' * 41})), isNull);
      expect(decodeWatchPacket(_json({...sync(), 'id': 7})), isNull);
      expect(decodeWatchPacket(_json({...sync(), 'p': -1})), isNull);
      expect(
        decodeWatchPacket(_json({...sync(), 'p': maxWatchPositionMs + 1})),
        isNull,
      );
      expect(decodeWatchPacket(_json({...sync(), 'p': 1.5})), isNull);
      expect(decodeWatchPacket(_json({...sync(), 'p': '5'})), isNull);
      expect(decodeWatchPacket(_json({...sync(), 'r': 2})), isNull);
      expect(decodeWatchPacket(_json({...sync(), 'r': true})), isNull);
      expect(decodeWatchPacket(_json({...sync(), 'n': -1})), isNull);
      expect(decodeWatchPacket(_json({...sync()}..remove('ts'))), isNull);
    });

    test('a start with a link that is not allowed is dropped', () {
      Map<String, Object?> start(String url) => {
        'v': 1,
        'k': 's',
        'id': 'abc',
        'u': url,
        't': 'x',
        'p': 0,
        'r': 0,
        'n': 1,
        'ts': 1760000000000,
      };
      expect(
        decodeWatchPacket(_json(start('https://example.com/a.mp4'))),
        isA<WatchStartPacket>(),
      );
      for (final url in [
        'http://example.com/a.mp4',
        'https://127.0.0.1/a.mp4',
        'javascript:alert(1)',
        'file:///etc/passwd',
        '',
      ]) {
        expect(decodeWatchPacket(_json(start(url))), isNull, reason: url);
      }
      expect(
        decodeWatchPacket(_json({...start('https://e.com/a.mp4'), 'u': 5})),
        isNull,
      );
    });

    test('a start title is cleaned', () {
      final packet =
          decodeWatchPacket(
                _json({
                  'v': 1,
                  'k': 's',
                  'id': 'abc',
                  'u': 'https://example.com/a.mp4',
                  't': 'Night\u202E  train\u0000',
                  'p': 0,
                  'r': 0,
                  'n': 1,
                  'ts': 1760000000000,
                }),
              )
              as WatchStartPacket;
      expect(packet.title, 'Night train');
    });

    test('a packet over the size limit is dropped unread', () {
      final big = utf8.encode(
        jsonEncode({
          'v': 1,
          'k': 'y',
          'id': 'abc',
          'c': 'beat',
          'p': 0,
          'r': 0,
          'n': 1,
          'ts': 1,
          'pad': 'x' * (maxWatchPacketBytes + 10),
        }),
      );
      expect(decodeWatchPacket(big), isNull);
    });
  });

  group('rate limits', () {
    test('one person gets so many packets in a window', () {
      var now = DateTime(2026, 11, 4, 12);
      final limits = WatchRateLimits(max: 3, now: () => now);
      expect(limits.allow('a'), isTrue);
      expect(limits.allow('a'), isTrue);
      expect(limits.allow('a'), isTrue);
      expect(limits.allow('a'), isFalse);
      // Somebody else is not held back.
      expect(limits.allow('b'), isTrue);
      now = now.add(const Duration(seconds: 6));
      expect(limits.allow('a'), isTrue);
    });
  });

  group('keeping in step', () {
    final received = DateTime(2026, 11, 4, 20, 0, 10);

    test('transit counts only inside zero to two seconds', () {
      expect(
        watchTransit(
          received.subtract(const Duration(milliseconds: 300)),
          received,
        ),
        const Duration(milliseconds: 300),
      );
      // A clock that is ahead of ours counts for nothing.
      expect(
        watchTransit(received.add(const Duration(seconds: 30)), received),
        Duration.zero,
      );
      // A clock that is far behind is cut to the longest transit.
      expect(
        watchTransit(received.subtract(const Duration(minutes: 5)), received),
        watchMaxTransit,
      );
    });

    test('a playing host moves on, a paused one stays', () {
      final playing = WatchAnchor.fromPacket(
        positionMs: 10000,
        playing: true,
        sentAt: received.subtract(const Duration(milliseconds: 400)),
        received: received,
      );
      expect(playing.expectedMs(received), 10400);
      expect(
        playing.expectedMs(received.add(const Duration(seconds: 3))),
        13400,
      );
      final paused = WatchAnchor.fromPacket(
        positionMs: 10000,
        playing: false,
        sentAt: received.subtract(const Duration(seconds: 1)),
        received: received,
      );
      expect(
        paused.expectedMs(received.add(const Duration(minutes: 1))),
        10000,
      );
    });

    test('the expected position stays inside the media', () {
      final anchor = WatchAnchor(
        positionMs: 59000,
        at: received,
        playing: true,
      );
      expect(
        anchor.expectedMs(
          received.add(const Duration(seconds: 30)),
          durationMs: 60000,
        ),
        60000,
      );
    });

    test('more than a second apart needs a seek, up to a second does not', () {
      expect(watchNeedsSeek(localMs: 10000, expectedMs: 10000), isFalse);
      expect(watchNeedsSeek(localMs: 10900, expectedMs: 10000), isFalse);
      expect(watchNeedsSeek(localMs: 9100, expectedMs: 10000), isFalse);
      expect(watchNeedsSeek(localMs: 10000, expectedMs: 10000 + 1000), isFalse);
      expect(watchNeedsSeek(localMs: 10000, expectedMs: 11001), isTrue);
      expect(watchNeedsSeek(localMs: 12500, expectedMs: 10000), isTrue);
    });
  });
}
