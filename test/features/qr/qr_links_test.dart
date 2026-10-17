import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/qr/qr_links.dart';

const _user = 'abcd2345efgh6789';
const _hosts = {'wecord.jokebear.fyi'};

void main() {
  group('links', () {
    test('a person\'s link is the site, /u/ and the code', () {
      expect(
        userQrUrl(_user, site: 'https://wecord.jokebear.fyi'),
        'https://wecord.jokebear.fyi/u/$_user',
      );
      expect(userQrPath(_user), '/u/$_user');
    });

    test('a group\'s link is the site, /g/ and the code', () {
      expect(
        groupQrUrl(_user, site: 'https://wecord.jokebear.fyi'),
        'https://wecord.jokebear.fyi/g/$_user',
      );
      expect(groupQrPath(_user), '/g/$_user');
    });

    test('a browser address finds the page of a QR link', () {
      expect(
        qrLinkLocationFor(Uri.parse('https://wecord.jokebear.fyi/u/$_user')),
        '/u/$_user',
      );
      expect(
        qrLinkLocationFor(
          Uri.parse('https://wecord.jokebear.fyi/g/${_user.toUpperCase()}'),
        ),
        '/g/$_user',
      );
      // The web app's own routes live after a #.
      expect(
        qrLinkLocationFor(
          Uri.parse('https://wecord.jokebear.fyi/u/$_user#/home'),
        ),
        isNull,
      );
      expect(
        qrLinkLocationFor(Uri.parse('https://wecord.jokebear.fyi/u/short')),
        isNull,
      );
      expect(
        qrLinkLocationFor(Uri.parse('https://wecord.jokebear.fyi/x/$_user')),
        isNull,
      );
      expect(
        qrLinkLocationFor(Uri.parse('https://wecord.jokebear.fyi/')),
        isNull,
      );
    });
  });

  group('what a scanned code means', () {
    ScannedLink parse(String text) => parseScannedText(text, hosts: _hosts);

    test('a person\'s code opens their profile', () {
      expect(
        parse('https://wecord.jokebear.fyi/u/$_user'),
        const UserQrLink(_user),
      );
      // Upper case, spaces around it and a trailing slash all read the same.
      expect(
        parse('  https://wecord.jokebear.fyi/u/${_user.toUpperCase()}/ \n'),
        const UserQrLink(_user),
      );
    });

    test('a group\'s code opens the join page', () {
      expect(
        parse('https://wecord.jokebear.fyi/g/$_user'),
        const GroupQrLink(_user),
      );
    });

    test('circle invites work as web links and as in-app paths', () {
      expect(
        parse('https://wecord.jokebear.fyi/#/invite/Ab3dEf5hJk'),
        const CircleInviteQrLink('ab3def5hjk'),
      );
      // What phones and desktops put in an invite's QR code.
      expect(
        parse('/invite/Ab3dEf5hJk'),
        const CircleInviteQrLink('ab3def5hjk'),
      );
    });

    test('call links open the call', () {
      expect(
        parse('https://wecord.jokebear.fyi/call/abcd2345efgh'),
        const CallQrLink('abcd2345efgh'),
      );
      expect(parse('/call/abcd2345efgh'), const CallQrLink('abcd2345efgh'));
    });

    test('other sites are not WeCord, however the path looks', () {
      final link = parse('https://evil.example/u/$_user');
      expect(link, isA<OtherQrText>());
      expect(
        (link as OtherQrText).url,
        Uri.parse('https://evil.example/u/$_user'),
      );
    });

    test('plain text is shown as text; web links can be opened', () {
      expect(parse('hello there'), const OtherQrText('hello there'));
      expect(
        parse('https://example.com/menu'),
        OtherQrText(
          'https://example.com/menu',
          url: Uri.parse('https://example.com/menu'),
        ),
      );
      // Not a web link: shown, not offered to open.
      expect((parse('mailto:a@b.example') as OtherQrText).url, isNull);
      expect(
        (parse('WIFI:S:home;T:WPA;P:secret;;') as OtherQrText).url,
        isNull,
      );
    });

    test('a code of the wrong length is not a WeCord link', () {
      expect(parse('https://wecord.jokebear.fyi/u/abc'), isA<OtherQrText>());
      expect(parse('/u/$_user'), const UserQrLink(_user));
      expect(parse('/invite/short'), isA<OtherQrText>());
    });

    test('the sites WeCord links can come from', () {
      expect(
        wecordHosts(
          configuredSite: 'https://staging.example.com',
          isWeb: false,
        ),
        {'wecord.jokebear.fyi', 'staging.example.com'},
      );
      expect(
        wecordHosts(
          configuredSite: 'https://wecord.jokebear.fyi',
          pageUri: Uri.parse('http://localhost:8080/'),
          isWeb: true,
        ),
        {'wecord.jokebear.fyi', 'localhost'},
      );
    });
  });
}
