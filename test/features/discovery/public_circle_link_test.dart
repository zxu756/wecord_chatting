import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/discovery/public_circle_link.dart';

void main() {
  group('circleSlugProblem', () {
    test('accepts valid short names and the empty one (it clears)', () {
      for (final ok in [
        '',
        '   ',
        'abc',
        'pixel-club',
        'Pixel-Club',
        ' rust2026 ',
        'a1b',
        'a' * 32,
      ]) {
        expect(circleSlugProblem(ok), isNull, reason: ok);
      }
    });

    test('names what is wrong', () {
      expect(circleSlugProblem('ab'), 'length');
      expect(circleSlugProblem('a' * 33), 'length');
      expect(circleSlugProblem('pixel club'), 'characters');
      expect(circleSlugProblem('pixel_club'), 'characters');
      expect(circleSlugProblem('café-club'), 'characters');
      expect(circleSlugProblem('像素俱乐部'), 'characters');
      expect(circleSlugProblem('-abc'), 'hyphens');
      expect(circleSlugProblem('abc-'), 'hyphens');
      expect(circleSlugProblem('a--b'), 'hyphens');
      expect(circleSlugProblem('admin'), 'reserved');
      expect(circleSlugProblem('Invite'), 'reserved');
      expect(circleSlugProblem('wecord'), 'reserved');
    });

    test('agrees with isCircleSlug', () {
      for (final value in ['abc', 'pixel-club', 'ab', 'a--b', 'admin', 'x y']) {
        expect(
          isCircleSlug(normalizeCircleSlug(value)),
          circleSlugProblem(value) == null,
          reason: value,
        );
      }
    });
  });

  test('the reserved words are the ones the server keeps', () {
    // Kept in step with circle_slug_is_reserved (202610260500).
    expect(reservedCircleSlugs, hasLength(35));
    expect(reservedCircleSlugs, containsAll(['c', 'n', 'invite', 'call']));
  });

  test('publicCircleUrl is the site plus /c/<slug>', () {
    expect(
      publicCircleUrl('pixel-club', site: 'https://wecord.example'),
      'https://wecord.example/c/pixel-club',
    );
    expect(publicCirclePath('pixel-club'), '/c/pixel-club');
  });

  test('a shared /c/<slug> address finds the circle page', () {
    expect(
      publicCircleLocationFor(Uri.parse('https://wecord.example/c/Pixel-Club')),
      '/c/pixel-club',
    );
    expect(
      publicCircleLocationFor(
        Uri.parse('https://wecord.example/c/pixel-club/'),
      ),
      '/c/pixel-club',
    );
    expect(
      publicCircleLocationFor(
        Uri.parse('https://wecord.example/c/pixel-club#/chats'),
      ),
      isNull,
    );
    expect(
      publicCircleLocationFor(Uri.parse('https://wecord.example/')),
      isNull,
    );
    expect(
      publicCircleLocationFor(Uri.parse('https://wecord.example/c/ab')),
      isNull,
    );
    expect(
      publicCircleLocationFor(Uri.parse('https://wecord.example/c/admin')),
      isNull,
    );
    expect(
      publicCircleLocationFor(Uri.parse('https://wecord.example/n/pixel-club')),
      isNull,
    );
    expect(
      publicCircleLocationFor(Uri.parse('https://wecord.example/c/a/b')),
      isNull,
    );
  });
}
