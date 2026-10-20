// Public circle web pages (C8), for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool: the short
// name in a circle's Discovery settings, the /c/<slug> page in the app (the
// circle's preview, over its card) and the page for a circle that is not
// available.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_rpc.dart';

import '../features/discovery/discovery_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// The database functions behind these screens.
Future<Object?> _publicCircleRpc(
  String name,
  Map<String, dynamic> params,
) async {
  switch (name) {
    case 'get_circle_discovery':
      return {
        'is_public': true,
        'description':
            'Share pixel art, get friendly critique and join our '
            'weekly palette challenges.',
        'category': 'art',
        'language': 'en',
        'tags': ['pixel art', 'aseprite'],
        'listed_at': '2026-10-01T10:00:00Z',
      };
    case 'get_circle_slug':
      return {'slug': 'pixel-painters'};
    case 'resolve_circle_slug':
      return params['circle_slug'] == 'pixel-painters'
          ? {'circle_id': 'circle-9', 'is_member': false}
          : null;
    case 'discoverable_circle_preview':
      return {
        ...previewJson('circle-9'),
        'name': 'Pixel Painters',
        'description':
            'Share pixel art, get friendly critique and join our '
            'weekly palette challenges.',
        'category': 'art',
        'tags': ['pixel art', 'aseprite', 'weekly'],
      };
  }
  throw StateError('Supabase must be initialized first.');
}

List<Override> publicCircleOverrides() => [
  circleRpcProvider.overrideWithValue(_publicCircleRpc),
];

Future<void> _openSlugSettings(WidgetTester tester, PhoneWorld world) async {
  world.extraOverrides = publicCircleOverrides();
  await world.open(tester, '/circles/circle-1');
  await settle(tester);
  await tester.tap(find.byTooltip('Circle menu'));
  await settle(tester);
  final entry = find.text('Circle settings').last;
  await tester.ensureVisible(entry);
  await settle(tester);
  await tester.tap(entry);
  await settle(tester);
  final row = find.byKey(const ValueKey('circle-settings-discovery'));
  await tester.scrollUntilVisible(
    row,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(row);
  await settle(tester);
  final field = find.byKey(const ValueKey('discovery-slug-field'));
  await tester.scrollUntilVisible(
    field,
    200,
    scrollable: find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await settle(tester);
}

Future<void> _openPage(
  WidgetTester tester,
  PhoneWorld world,
  String location,
) async {
  world.extraOverrides = publicCircleOverrides();
  await world.open(tester, location);
  await settle(tester);
}

final publicCircleA11yScreens = <A11yScreen>[
  A11yScreen('public-circle-slug-settings', _openSlugSettings),
  A11yScreen(
    'desktop-public-circle-slug-settings',
    _openSlugSettings,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'public-circle-page',
    (tester, world) => _openPage(tester, world, '/c/pixel-painters'),
  ),
  A11yScreen(
    'desktop-public-circle-page',
    (tester, world) => _openPage(tester, world, '/c/pixel-painters'),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'public-circle-unavailable',
    (tester, world) => _openPage(tester, world, '/c/secret-club'),
  ),
];
