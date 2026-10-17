import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/image_text/image_text_cache.dart';

CachedImageText _text(String text, [int day = 1]) =>
    CachedImageText(text: text, savedAt: DateTime.utc(2026, 10, day));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the key is the message, or the file without one', () {
    expect(imageTextKey(messageId: 'm1', storagePath: 'a/b.jpg'), 'm:m1');
    expect(imageTextKey(storagePath: 'a/b.jpg'), 'f:a/b.jpg');
    expect(imageTextKey(messageId: '', storagePath: 'a/b.jpg'), 'f:a/b.jpg');
  });

  test('keeps text across a restart, per picture', () async {
    final first = SharedPreferencesImageTextCache(userId: 'user-1');
    await first.write('m:1', _text('Opening hours'));
    await first.write('m:2', _text(''));

    final restarted = SharedPreferencesImageTextCache(userId: 'user-1');
    expect((await restarted.read('m:1'))?.text, 'Opening hours');
    expect((await restarted.read('m:1'))?.savedAt, DateTime.utc(2026, 10));
    // A picture known to hold no text is remembered too.
    expect((await restarted.read('m:2'))?.text, '');
    expect(await restarted.read('m:3'), isNull);
  });

  test('is private to the signed-in user', () async {
    await SharedPreferencesImageTextCache(
      userId: 'user-1',
    ).write('m:1', _text('Mine'));
    expect(
      await SharedPreferencesImageTextCache(userId: 'user-2').read('m:1'),
      isNull,
    );
  });

  test('keeps nothing on disk without a user', () async {
    final cache = SharedPreferencesImageTextCache();
    await cache.write('m:1', _text('Gone soon'));
    expect((await cache.read('m:1'))?.text, 'Gone soon');
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('keeps the newest entries past the limit', () async {
    final cache = SharedPreferencesImageTextCache(
      userId: 'user-1',
      maxEntries: 2,
    );
    await cache.write('old', _text('old', 1));
    await cache.write('mid', _text('mid', 2));
    await cache.write('new', _text('new', 3));
    expect(await cache.read('old'), isNull);
    expect((await cache.read('mid'))?.text, 'mid');
    expect((await cache.read('new'))?.text, 'new');
  });

  test('a damaged store is ignored', () async {
    SharedPreferences.setMockInitialValues({
      'wecord.image_text.user-1': '{not json',
    });
    final cache = SharedPreferencesImageTextCache(userId: 'user-1');
    expect(await cache.read('m:1'), isNull);
    await cache.write('m:1', _text('fine'));
    expect((await cache.read('m:1'))?.text, 'fine');
  });

  test('clear forgets everything', () async {
    final cache = SharedPreferencesImageTextCache(userId: 'user-1');
    await cache.write('m:1', _text('x'));
    await cache.clear();
    expect(await SharedPreferencesImageTextCache(userId: 'user-1').read('m:1'),
        isNull);
  });

  test('the in-memory cache works the same', () async {
    final cache = InMemoryImageTextCache();
    await cache.write('m:1', _text('x'));
    expect((await cache.read('m:1'))?.text, 'x');
    await cache.clear();
    expect(await cache.read('m:1'), isNull);
  });
}
