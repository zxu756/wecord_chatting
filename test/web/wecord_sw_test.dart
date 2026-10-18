import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/later/saved_messages_screen.dart';
import 'package:wecord/features/moments/moments_screen.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('service worker', () {
    final nodeAvailable = Process.runSync('node', ['--version']).exitCode == 0;

    test('caches the shell and leaves the API alone (fake worker, node)', () {
      final result = Process.runSync('node', [
        'test/web/wecord_sw_harness.mjs',
        'web/wecord_sw.js',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }, skip: nodeAvailable ? false : 'node is not installed');

    test('carries one version placeholder for tool/deploy_web.sh', () {
      final source = read('web/wecord_sw.js');
      expect('__WECORD_VERSION__'.allMatches(source), hasLength(1));
      expect(read('tool/deploy_web.sh'), contains('__WECORD_VERSION__'));
    });

    test('does not take over push (push_sw.js keeps its own scope)', () {
      expect(read('web/wecord_sw.js'), isNot(contains("'push'")));
      expect(read('web/wecord_sw.js'), isNot(contains('showNotification')));
      final gateway = read('lib/features/push/push_gateway_web.dart');
      expect(gateway, contains("_workerUrl = 'push_sw.js'"));
      expect(gateway, contains("_scope = 'push/'"));
    });
  });

  test('push_sw.js still handles push and notification clicks', () {
    final push = read('web/push_sw.js');
    expect(push, contains("addEventListener('push'"));
    expect(push, contains("addEventListener('notificationclick'"));
    expect(push, contains('showNotification'));
    expect(push, contains('wecord-open'));
  });

  group('manifest', () {
    final manifest =
        jsonDecode(read('web/manifest.json')) as Map<String, dynamic>;

    test('is installable', () {
      expect(manifest['name'], 'WeCord');
      expect(manifest['short_name'], 'WeCord');
      expect(manifest['display'], 'standalone');
      expect(manifest['start_url'], '/');
      expect(manifest['scope'], '/');
      expect(manifest['id'], isNotEmpty);
      expect(manifest['description'], isNotEmpty);
      expect(manifest['categories'], isNotEmpty);
    });

    test('uses design C paper for its colours', () {
      expect(manifest['theme_color'], '#F5F4F1');
      expect(manifest['background_color'], '#F5F4F1');
    });

    test('has any and maskable icons at 192, 512 and 1024', () {
      final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();
      for (final purpose in ['any', 'maskable']) {
        for (final size in [192, 512, 1024]) {
          final icon = icons.singleWhere(
            (icon) =>
                icon['purpose'] == purpose && icon['sizes'] == '${size}x$size',
          );
          final file = File('web/${icon['src']}');
          expect(file.existsSync(), isTrue, reason: '${icon['src']}');
          // Reasonably small: nothing close to a megabyte.
          expect(file.lengthSync(), lessThan(200 * 1024));
        }
      }
      expect(File('web/icons/apple-touch-icon.png').existsSync(), isTrue);
    });

    test('shortcuts open real routes through the hash', () {
      final routes = {
        'New message': ContactsScreen.path,
        'Saved': SavedMessagesScreen.path,
        'Moments': MomentsScreen.path,
        'Notifications': InboxScreen.path,
      };
      final shortcuts = (manifest['shortcuts'] as List)
          .cast<Map<String, dynamic>>();
      expect(shortcuts.map((s) => s['name']), routes.keys);
      for (final shortcut in shortcuts) {
        expect(shortcut['url'], '/#${routes[shortcut['name']]}');
      }
    });
  });

  group('index.html', () {
    final html = read('web/index.html');

    test('has the installed-app and theme tags', () {
      expect(html, contains('name="apple-mobile-web-app-capable"'));
      expect(html, contains('name="apple-mobile-web-app-status-bar-style"'));
      expect(html, contains('rel="apple-touch-icon"'));
      expect(html, contains('rel="manifest"'));
      expect(
        html,
        contains('content="#F5F4F1" media="(prefers-color-scheme: light)"'),
      );
      expect(
        html,
        contains('content="#111113" media="(prefers-color-scheme: dark)"'),
      );
      expect(html, contains('<title>WeCord'));
      expect(html, contains('name="description"'));
    });

    test('has a splash that respects colour scheme and reduced motion', () {
      expect(html, contains('id="wc-splash"'));
      expect(html, contains('@media (prefers-color-scheme: dark)'));
      expect(html, contains('@media (prefers-reduced-motion: reduce)'));
      expect(html, contains("'flutter-first-frame'"));
    });

    test('registers the worker and keeps the install prompt', () {
      expect(html, contains("register('wecord_sw.js'"));
      expect(html, contains('beforeinstallprompt'));
      expect(read('web/flutter_bootstrap.js'), contains('wecordSplash'));
    });
  });
}
