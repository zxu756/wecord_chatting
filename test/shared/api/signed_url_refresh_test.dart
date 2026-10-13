import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/custom_emoji.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/shared/api/signed_url_refresh.dart';

void main() {
  test('a key is signed again at most once per cooldown', () {
    var now = DateTime.utc(2026, 10, 14, 9);
    final refresher = SignedUrlRefresher(
      cooldown: const Duration(minutes: 5),
      clock: () => now,
    );

    expect(refresher.tryRefresh('emoji:a'), isTrue);
    expect(refresher.tryRefresh('emoji:a'), isFalse);
    expect(refresher.tryRefresh('emoji:b'), isTrue);

    now = now.add(const Duration(minutes: 4));
    expect(refresher.tryRefresh('emoji:a'), isFalse);
    now = now.add(const Duration(minutes: 1));
    expect(refresher.tryRefresh('emoji:a'), isTrue);
  });

  testWidgets('an emoji image that fails to load is signed again once', (
    tester,
  ) async {
    signedUrlRefresher.reset();
    addTearDown(signedUrlRefresher.reset);
    final repository = _CountingEmojiRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          circleEmojiRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Row(
            children: [
              // The same emoji twice signs one URL between them.
              CustomEmojiImage(
                storagePath: 'circle-1/wave.png',
                size: 22,
                fallback: Text(':wave:'),
              ),
              CustomEmojiImage(
                storagePath: 'circle-1/wave.png',
                size: 22,
                fallback: Text(':wave:'),
              ),
            ],
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Test images never load: signed, failed, signed again, then left.
    expect(repository.signed, ['circle-1/wave.png', 'circle-1/wave.png']);
    expect(find.text(':wave:'), findsNWidgets(2));
  });
}

class _CountingEmojiRepository implements CircleEmojiRepository {
  final signed = <String>[];

  @override
  Future<String> createEmojiUrl(String storagePath) async {
    signed.add(storagePath);
    return 'https://emoji.test/${signed.length}/$storagePath';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
