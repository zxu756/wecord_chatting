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
      'https://wecord.example/#/invite/abcdefgh23',
    );
    expect(circleInviteLink('abcdefgh23', isWeb: false), '/invite/abcdefgh23');
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
