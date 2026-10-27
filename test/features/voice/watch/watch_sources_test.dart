import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/watch/watch_sources.dart';

void main() {
  group('parseWatchLink', () {
    WatchEmbedSource embed(String text) {
      final result = parseWatchLink(text);
      expect(result.problem, isNull, reason: text);
      return result.source! as WatchEmbedSource;
    }

    test('reads the usual YouTube addresses', () {
      for (final text in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtube.com/watch?v=dQw4w9WgXcQ&t=42s',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=x',
        'https://youtu.be/dQw4w9WgXcQ?si=abc',
        'youtu.be/dQw4w9WgXcQ',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
        'https://www.youtube.com/live/dQw4w9WgXcQ',
        'https://www.youtube.com/embed/dQw4w9WgXcQ',
        'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ',
      ]) {
        final source = embed(text);
        expect(source.provider, WatchEmbedProvider.youtube, reason: text);
        expect(source.id, 'dQw4w9WgXcQ', reason: text);
      }
    });

    test('reads Bilibili video pages', () {
      final bv = embed('https://www.bilibili.com/video/BV1GJ411x7h7/?p=2');
      expect(bv.provider, WatchEmbedProvider.bilibili);
      expect(bv.id, 'BV1GJ411x7h7');
      expect(bv.embedUri().queryParameters['bvid'], 'BV1GJ411x7h7');

      final lower = embed('https://m.bilibili.com/video/bv1GJ411x7h7');
      expect(lower.id, 'BV1GJ411x7h7');

      final av = embed('https://www.bilibili.com/video/av170001');
      expect(av.id, 'av170001');
      expect(av.embedUri().queryParameters['aid'], '170001');
    });

    test('asks for the full Bilibili link instead of a short one', () {
      expect(
        parseWatchLink('https://b23.tv/abc123').problem,
        WatchLinkProblem.shortLink,
      );
    });

    test('reads links to media files', () {
      final video = parseWatchLink('https://cdn.example.com/a/Film.MP4?x=1');
      expect(video.source, isA<WatchLinkSource>());
      expect(video.source!.isAudio, isFalse);
      expect(video.source!.label, 'Film.MP4');

      final audio = parseWatchLink('https://cdn.example.com/song.mp3');
      expect(audio.source!.isAudio, isTrue);

      expect(
        parseWatchLink('https://cdn.example.com/live/stream.m3u8').source,
        isA<WatchLinkSource>(),
      );
    });

    test('turns down what a call can not play', () {
      expect(parseWatchLink('').problem, WatchLinkProblem.notALink);
      expect(parseWatchLink('hello there').problem, WatchLinkProblem.notALink);
      expect(
        parseWatchLink('http://cdn.example.com/a.mp4').problem,
        WatchLinkProblem.notHttps,
      );
      expect(
        parseWatchLink('https://example.com/page.html').problem,
        WatchLinkProblem.unsupported,
      );
      expect(
        parseWatchLink('https://www.youtube.com/playlist?list=PL1').problem,
        WatchLinkProblem.unsupported,
      );
      expect(
        parseWatchLink('https://www.youtube.com/watch?v=short').problem,
        WatchLinkProblem.unsupported,
      );
      expect(
        parseWatchLink('https://www.bilibili.com/').problem,
        WatchLinkProblem.unsupported,
      );
      // Not a video file, even with a media word in it.
      expect(
        parseWatchLink('https://example.com/mp4').problem,
        WatchLinkProblem.unsupported,
      );
    });

    test('refuses a link that looks risky (G5)', () {
      expect(
        parseWatchLink('https://paypal.com@evil.example/film.mp4').problem,
        WatchLinkProblem.risky,
      );
      expect(
        parseWatchLink('https://paypal.secure-evil.example/film.mp4').problem,
        WatchLinkProblem.risky,
      );
    });
  });

  group('embed addresses', () {
    test('YouTube plays in the privacy-enhanced player without controls', () {
      final source = WatchEmbedSource.tryCreate(
        WatchEmbedProvider.youtube,
        'dQw4w9WgXcQ',
      )!;
      final uri = source.embedUri(origin: 'https://wecord.example');
      expect(uri.host, 'www.youtube-nocookie.com');
      expect(uri.path, '/embed/dQw4w9WgXcQ');
      expect(uri.queryParameters['enablejsapi'], '1');
      expect(uri.queryParameters['controls'], '0');
      expect(uri.queryParameters['origin'], 'https://wecord.example');
      expect(source.remoteControl, isTrue);
      expect(source.pageUri.toString(), contains('youtube.com/watch?v='));
    });

    test('Bilibili has no remote control', () {
      final source = WatchEmbedSource.tryCreate(
        WatchEmbedProvider.bilibili,
        'BV1GJ411x7h7',
      )!;
      expect(source.remoteControl, isFalse);
      expect(source.embedUri().host, 'player.bilibili.com');
      expect(source.embedUri().queryParameters['autoplay'], '0');
    });

    test('an id that is not an id makes no source', () {
      expect(
        WatchEmbedSource.tryCreate(WatchEmbedProvider.youtube, '../x'),
        isNull,
      );
      expect(
        WatchEmbedSource.tryCreate(WatchEmbedProvider.bilibili, 'BV123'),
        isNull,
      );
    });
  });

  group('sources in packets', () {
    const conversation = 'conv-lounge';
    Map<String, Object?> file({
      String bucket = 'chat-files',
      String path = 'conv-lounge/1-film.mp4',
      String name = 'film.mp4',
      String mime = 'video/mp4',
    }) => {'t': 'file', 'b': bucket, 'p': path, 'n': name, 'm': mime, 'z': 5};

    WatchSource? read(Object? json) =>
        WatchSource.fromJson(json, conversationId: conversation);

    test('a file from the call’s own chat folder is accepted', () {
      final source = read(file());
      expect(source, isA<WatchFileSource>());
      expect(source!.toJson(), file()..['z'] = 5);
      expect(read(file(name: 'song.mp3', mime: 'audio/mpeg'))!.isAudio, isTrue);
    });

    test('a file from anywhere else is not', () {
      expect(read(file(bucket: 'chat-images')), isNull);
      expect(read(file(path: 'conv-other/1-film.mp4')), isNull);
      expect(read(file(path: 'conv-lounge/../conv-other/1-film.mp4')), isNull);
      expect(read(file(path: 'conv-loungeX/1-film.mp4')), isNull);
      // A document is not something to watch.
      expect(read(file(name: 'notes.pdf', mime: 'application/pdf')), isNull);
    });

    test('a link must be a clean https media address', () {
      expect(
        read({'t': 'link', 'u': 'https://cdn.example.com/a.mp4'}),
        isA<WatchLinkSource>(),
      );
      expect(read({'t': 'link', 'u': 'http://cdn.example.com/a.mp4'}), isNull);
      expect(
        read({'t': 'link', 'u': 'https://cdn.example.com/a.html'}),
        isNull,
      );
      expect(read({'t': 'link', 'u': 'file:///etc/passwd'}), isNull);
      expect(
        read({'t': 'link', 'u': 'https://u:p@cdn.example.com/a.mp4'}),
        isNull,
      );
      expect(read({'t': 'link', 'u': 7}), isNull);
    });

    test('an embed is rebuilt from the site and id only', () {
      expect(
        read({'t': 'emb', 'pr': 'yt', 'id': 'dQw4w9WgXcQ'}),
        isA<WatchEmbedSource>(),
      );
      expect(read({'t': 'emb', 'pr': 'yt', 'id': 'nope'}), isNull);
      expect(read({'t': 'emb', 'pr': 'evil', 'id': 'dQw4w9WgXcQ'}), isNull);
      expect(read({'t': 'unknown'}), isNull);
      expect(read('x'), isNull);
    });
  });

  test('a title is tidied and cut', () {
    expect(tidyWatchTitle('  a\u0000b\u202E  c  '), 'ab c');
    expect(tidyWatchTitle('x' * 200).length, maxWatchTitleChars);
  });
}
