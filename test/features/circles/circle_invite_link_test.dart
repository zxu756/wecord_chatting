import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_invite_link.dart';

void main() {
  test('circleInviteLink uses the web origin or the in-app path', () {
    expect(
      circleInviteLink(
        'abcdefgh23',
        isWeb: true,
        base: Uri.parse('https://wecord.example/some/page#/chats'),
      ),
      'https://wecord.example/invite/abcdefgh23',
    );
    expect(circleInviteLink('abcdefgh23', isWeb: false), '/invite/abcdefgh23');
  });

  test('a shared /invite/<code> address finds the invite page', () {
    expect(
      circleInviteLocationFor(
        Uri.parse('https://wecord.example/invite/ABCDEFGH23'),
      ),
      '/invite/abcdefgh23',
    );
    expect(
      circleInviteLocationFor(
        Uri.parse('https://wecord.example/invite/abcdefgh23/'),
      ),
      '/invite/abcdefgh23',
    );
    // Routes after a '#' are the app's own and are left alone.
    expect(
      circleInviteLocationFor(
        Uri.parse('https://wecord.example/invite/abcdefgh23#/chats'),
      ),
      isNull,
    );
    expect(
      circleInviteLocationFor(Uri.parse('https://wecord.example/')),
      isNull,
    );
    expect(
      circleInviteLocationFor(Uri.parse('https://wecord.example/invite/short')),
      isNull,
    );
    expect(
      circleInviteLocationFor(Uri.parse('https://wecord.example/c/abcdefgh23')),
      isNull,
    );
  });

  test('parseCircleInviteCode accepts codes, paths and links', () {
    expect(parseCircleInviteCode(' abcdefgh23 '), 'abcdefgh23');
    expect(parseCircleInviteCode('ABCDEFGH23'), 'abcdefgh23');
    expect(parseCircleInviteCode('/invite/abcdefgh23'), 'abcdefgh23');
    expect(
      parseCircleInviteCode('https://wecord.example/#/invite/abcdefgh23'),
      'abcdefgh23',
    );
    expect(
      parseCircleInviteCode('https://wecord.example/invite/abcdefgh23?x=1'),
      'abcdefgh23',
    );
    expect(parseCircleInviteCode(''), isNull);
    expect(parseCircleInviteCode('abc'), isNull);
    expect(parseCircleInviteCode('/invite/abcdefgh234'), isNull);
    expect(parseCircleInviteCode('https://example.com/other'), isNull);
  });
}
