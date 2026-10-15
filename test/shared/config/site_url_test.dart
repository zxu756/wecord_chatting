import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/config/site_url.dart';

void main() {
  test('a configured site URL wins, without a trailing slash', () {
    expect(
      authRedirectUrl(
        configured: ' https://chat.example.com/ ',
        isWeb: true,
        isRelease: false,
        pageUri: Uri.parse('http://localhost:5000/chats'),
      ),
      'https://chat.example.com',
    );
  });

  test('web debug builds return to their own page', () {
    expect(
      authRedirectUrl(
        configured: '',
        isWeb: true,
        isRelease: false,
        pageUri: Uri.parse('http://localhost:5000/circles/1?x=y'),
      ),
      'http://localhost:5000',
    );
  });

  test('release builds and the apps return to the deployed web app', () {
    expect(
      authRedirectUrl(
        configured: '',
        isWeb: true,
        isRelease: true,
        pageUri: Uri.parse('https://preview.example.com/'),
      ),
      defaultSiteUrl,
    );
    expect(
      authRedirectUrl(configured: '', isWeb: false, isRelease: false),
      'https://wecord.jokebear.fyi',
    );
    expect(
      authRedirectUrl(
        configured: '',
        isWeb: true,
        isRelease: false,
        pageUri: Uri.parse('file:///tmp/index.html'),
      ),
      defaultSiteUrl,
    );
  });
}
