import 'package:wecord/features/discovery/circle_discovery_repository.dart';

/// A public circle's row as list_discoverable_circles returns it.
Map<String, dynamic> discoverableJson(
  String id, {
  String? name,
  String category = 'gaming',
  int members = 10,
  int online = 2,
  bool isMember = false,
  List<String> tags = const ['pixel', 'retro'],
  String? description,
}) => {
  'id': id,
  'name': name ?? 'Circle $id',
  'avatar_url': null,
  'description': description ?? 'All about $id.',
  'category': category,
  'language': 'en',
  'tags': tags,
  'member_count': members,
  'online_count': online,
  'listed_at': '2026-10-01T10:00:00Z',
  'last_activity_at': '2026-10-15T10:00:00Z',
  'is_member': isMember,
  'rank': 0,
};

/// A preview as discoverable_circle_preview returns it.
Map<String, dynamic> previewJson(
  String id, {
  bool isMember = false,
  bool isBanned = false,
  List<String> rules = const ['Be kind', 'No spam'],
}) => {
  ...discoverableJson(id, isMember: isMember),
  'is_banned': isBanned,
  'rules_enabled': rules.isNotEmpty,
  'rules': rules,
  'channels': [
    {'name': 'general', 'kind': 'text'},
    {'name': 'Lounge', 'kind': 'voice'},
  ],
};

/// Public circles for screenshots and widget tests.
final sampleDiscoverableCircles = [
  for (final (index, (name, category, description, tags)) in const [
    (
      'Pixel Painters',
      'art',
      'Share pixel art, get friendly critique and join our weekly '
          'palette challenges.',
      ['pixel art', 'aseprite', 'weekly'],
    ),
    (
      'Night Owls Gaming',
      'gaming',
      'Late-night co-op sessions, speedrun talk and a very serious '
          'Mario Kart league.',
      ['co-op', 'speedrun'],
    ),
    (
      'Rust 爱好者',
      'science_tech',
      '一起学习 Rust：所有权、异步和嵌入式。新手问题随时欢迎。',
      ['rust', '编程', 'embedded'],
    ),
    (
      'Sourdough Society',
      'food',
      'Starters, crumb shots and the eternal hydration debate.',
      ['baking', 'bread'],
    ),
    (
      'Trail Runners Sydney',
      'travel_outdoors',
      'Weekend trail runs around Sydney, all paces welcome.',
      ['running', 'sydney'],
    ),
    (
      'Lo-fi Lab',
      'music',
      'Beats to study to — made by members. Feedback threads every Friday.',
      ['lofi', 'production'],
    ),
  ].indexed)
    DiscoverableCircle.fromJson(
      discoverableJson(
        'pub-$index',
        name: name,
        category: category,
        description: description,
        tags: tags,
        members: [1284, 932, 410, 220, 87, 64][index],
        online: [212, 145, 38, 19, 6, 9][index],
        isMember: index == 3,
      ),
    ),
];
