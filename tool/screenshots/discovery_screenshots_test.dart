// Renders Explore (public circles), the circle preview and Circle
// settings → Discovery with real fonts and writes PNGs for eyeballing. Not
// part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/discovery_screenshots_test.dart \
//     --dart-define=DISCOVERY_SCREENS_DIR=build/discovery/light
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme and
// --dart-define=PHONE_SCREENS_ZH=true for Chinese. Phone shots (390x844)
// and desktop shots (1440x900, named d…) go to the same folder.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/bootstrap/app_bootstrap.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/navigation/app_router.dart';

import '../../test/features/discovery/discovery_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'DISCOVERY_SCREENS_DIR',
  defaultValue: 'build/discovery/light',
);

const _desktop = PhoneViewport(
  name: '1440x900',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

Map<String, dynamic> _json(int index) {
  final circle = sampleDiscoverableCircles[index];
  return {
    'id': circle.id,
    'name': circle.name,
    'avatar_url': null,
    'description': circle.description,
    'category': circle.category?.value,
    'language': index == 2 ? 'zh' : 'en',
    'tags': circle.tags,
    'member_count': circle.memberCount,
    'online_count': circle.onlineCount,
    'listed_at': '2026-10-0${index + 1}T10:00:00Z',
    'last_activity_at': '2026-10-16T09:00:00Z',
    'is_member': circle.isMember,
  };
}

/// Answers the discovery calls; everything else fails like an offline
/// server, as without the fake.
class _DiscoveryRpc {
  var empty = false;
  Map<String, dynamic> settings = {
    'is_public': true,
    'description':
        'Share pixel art, get friendly critique and join our weekly palette '
        'challenges.',
    'category': 'art',
    'language': 'en',
    'tags': ['pixel art', 'aseprite', 'weekly'],
    'listed_at': '2026-10-01T10:00:00Z',
  };

  Future<Object?> call(String name, Map<String, dynamic> params) async {
    switch (name) {
      case 'list_discoverable_circles':
        if (empty) {
          return const [];
        }
        final query = (params['search_query'] as String?)?.toLowerCase();
        final category = params['category_filter'] as String?;
        final offset = params['page_offset'] as int;
        final rows = [
          for (var i = 0; i < sampleDiscoverableCircles.length; i++) _json(i),
        ];
        final filtered = rows.where((row) {
          final text =
              '${row['name']} ${row['description']} ${(row['tags'] as List).join(' ')}'
                  .toLowerCase();
          return (category == null || row['category'] == category) &&
              (query == null || text.contains(query));
        }).toList();
        if (params['sort_by'] == 'new') {
          filtered.sort(
            (a, b) =>
                (b['listed_at'] as String).compareTo(a['listed_at'] as String),
          );
        }
        return filtered.skip(offset).toList();
      case 'discoverable_circle_preview':
        final index = sampleDiscoverableCircles.indexWhere(
          (circle) => circle.id == params['target_circle_id'],
        );
        return {
          ..._json(index),
          'is_banned': false,
          'rules_enabled': true,
          'rules': [
            'Be kind. Critique the art, never the artist.',
            'Credit the original when sharing others’ work.',
            'No AI-generated pieces in #showcase.',
          ],
          'channels': [
            {'name': 'welcome', 'kind': 'announcement'},
            {'name': 'general', 'kind': 'text'},
            {'name': 'showcase', 'kind': 'text'},
            {'name': 'critique', 'kind': 'forum'},
            {'name': 'Studio', 'kind': 'voice'},
          ],
        };
      case 'get_circle_discovery':
        return settings;
    }
    throw StateError('Supabase must be initialized first.');
  }
}

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String path) async {
    await settle(tester);
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> open(
    WidgetTester tester,
    PhoneWorld world,
    _DiscoveryRpc rpc,
    String location,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...world.overrides,
          circleRpcProvider.overrideWithValue(rpc.call),
        ],
        child: const WeCordApp(),
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WeCordApp)),
    );
    final router = container.read(appRouterProvider);
    await settle(tester);
    router.go(location);
    await settle(tester);
  }

  void screen(
    String name,
    Future<void> Function(
      WidgetTester tester,
      PhoneWorld world,
      _DiscoveryRpc rpc,
    )
    run, {
    PhoneViewport viewport = notchedPhone,
  }) {
    testWidgets(name, (tester) async {
      usePhoneViewport(tester, viewport);
      final world = PhoneWorld();
      final rpc = _DiscoveryRpc();
      await run(tester, world, rpc);
      await shoot(tester, '$_outputDir/$name.png');
    });
  }

  Future<void> openPreview(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('discovery-card-pub-0')).last);
    await settle(tester);
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip(tr('Circle menu')));
    await settle(tester);
    await tester.tap(find.text(tr('Circle settings')));
    await settle(tester);
    final row = find.byKey(const ValueKey('circle-settings-discovery'));
    await tester.ensureVisible(row);
    await settle(tester);
    await tester.tap(row);
    await settle(tester);
  }

  // Phone.

  screen('01-explore', (tester, world, rpc) async {
    await open(tester, world, rpc, '/discover');
  });

  screen('02-explore-scrolled', (tester, world, rpc) async {
    await open(tester, world, rpc, '/discover');
    await tester.drag(
      find.byKey(const ValueKey('discovery-scroll')),
      const Offset(0, -520),
    );
  });

  screen('03-explore-category', (tester, world, rpc) async {
    await open(tester, world, rpc, '/discover');
    await tester.tap(find.byKey(const ValueKey('discovery-category-gaming')));
  });

  screen('04-explore-search', (tester, world, rpc) async {
    await open(tester, world, rpc, '/discover');
    await tester.enterText(
      find.byKey(const ValueKey('discovery-search')),
      'rust',
    );
    await tester.pump(const Duration(milliseconds: 400));
  });

  screen('05-preview', (tester, world, rpc) async {
    await open(tester, world, rpc, '/discover');
    await openPreview(tester);
  });

  screen('06-preview-expanded', (tester, world, rpc) async {
    await open(tester, world, rpc, '/discover');
    await openPreview(tester);
    await tester.drag(find.text(tr('Rules')), const Offset(0, -400));
  });

  screen('07-empty', (tester, world, rpc) async {
    rpc.empty = true;
    await open(tester, world, rpc, '/discover');
  });

  screen('08-settings-discovery', (tester, world, rpc) async {
    await open(tester, world, rpc, '/circles/circle-1');
    await openSettings(tester);
  });

  screen('09-settings-discovery-bottom', (tester, world, rpc) async {
    await open(tester, world, rpc, '/circles/circle-1');
    await openSettings(tester);
    await tester.drag(
      find.byKey(const ValueKey('discovery-description')),
      const Offset(0, -700),
    );
  });

  screen('10-add-circle', (tester, world, rpc) async {
    await open(tester, world, rpc, '/home');
    await tester.tap(find.byKey(const ValueKey('circle-rail-add')));
  });

  // Desktop.

  screen('d1-explore', (tester, world, rpc) async {
    await open(tester, world, rpc, '/discover');
  }, viewport: _desktop);

  screen('d2-preview', (tester, world, rpc) async {
    await open(tester, world, rpc, '/discover');
    await openPreview(tester);
  }, viewport: _desktop);

  screen('d3-search', (tester, world, rpc) async {
    await open(tester, world, rpc, '/discover');
    await tester.enterText(find.byKey(const ValueKey('discovery-search')), 'a');
    await tester.pump(const Duration(milliseconds: 400));
  }, viewport: _desktop);

  screen('d4-settings-discovery', (tester, world, rpc) async {
    await open(tester, world, rpc, '/circles/circle-1');
    await openSettings(tester);
  }, viewport: _desktop);

  screen('d5-empty', (tester, world, rpc) async {
    rpc.empty = true;
    await open(tester, world, rpc, '/discover');
  }, viewport: _desktop);
}
