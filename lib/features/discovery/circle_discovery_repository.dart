import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/join_requests/join_gate.dart';
import 'package:wecord/features/circles/join_requests/join_request_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/report_reason.dart';

/// What a public circle is about, matching `circles.discovery_category`
/// (see `202610160040_public_circles.sql`).
enum DiscoveryCategory {
  gaming('gaming', 'Gaming', Icons.sports_esports_outlined),
  music('music', 'Music', Icons.music_note_outlined),
  education('education', 'Education', Icons.school_outlined),
  scienceTech('science_tech', 'Science & Tech', Icons.science_outlined),
  entertainment('entertainment', 'Entertainment', Icons.movie_outlined),
  art('art', 'Art', Icons.palette_outlined),
  sports('sports', 'Sports', Icons.sports_basketball_outlined),
  travelOutdoors('travel_outdoors', 'Travel & Outdoors', Icons.hiking),
  food('food', 'Food', Icons.restaurant_outlined),
  local('local', 'Local', Icons.place_outlined),
  other('other', 'Other', Icons.interests_outlined);

  const DiscoveryCategory(this.value, this._label, this.icon);

  final String value;
  final String _label;
  final IconData icon;

  String get label => trIn('discovery', _label);

  static DiscoveryCategory? fromJson(Object? value) {
    for (final category in values) {
      if (category.value == value) {
        return category;
      }
    }
    return null;
  }
}

/// The languages a circle can say it speaks, by code.
abstract final class DiscoveryLanguages {
  /// Codes in the order the picker shows them, with their own names.
  static const names = <String, String>{
    'en': 'English',
    'zh': '中文',
    'ja': '日本語',
    'ko': '한국어',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
    'pt': 'Português',
    'ru': 'Русский',
    'it': 'Italiano',
    'vi': 'Tiếng Việt',
    'th': 'ไทย',
    'id': 'Bahasa Indonesia',
  };

  /// The language's own name, or the code for unknown ones.
  static String label(String code) => names[code] ?? code;
}

/// How the discovery list is ordered.
enum DiscoverySort {
  /// Members, members online and recent messages.
  popular('popular'),

  /// Newest listed first.
  newest('new'),

  /// Best match for the search first.
  relevance('relevance');

  const DiscoverySort(this.value);

  final String value;
}

/// Limits the server enforces.
abstract final class DiscoveryLimits {
  static const descriptionLength = 300;
  static const tags = 5;
  static const tagLength = 24;
  static const pageSize = 24;
}

/// Why [input] cannot be a discovery tag, or null when it can.
String? discoveryTagProblem(String input) {
  final tag = normalizeDiscoveryTag(input);
  if (tag.isEmpty) {
    return 'empty';
  }
  if (tag.characters.length > DiscoveryLimits.tagLength) {
    return 'length';
  }
  if (tag.contains(',') || tag.contains('#')) {
    return 'characters';
  }
  return null;
}

/// A tag as the server stores it: trimmed, no leading '#', lower case.
String normalizeDiscoveryTag(String input) =>
    input.trim().replaceFirst(RegExp(r'^#+'), '').trim().toLowerCase();

List<String> _stringList(Object? value) =>
    value is List ? [for (final item in value) '$item'] : const [];

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

int _int(Object? value) => value is num ? value.toInt() : 0;

/// A public circle as discovery lists it.
class DiscoverableCircle {
  const DiscoverableCircle({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.description,
    this.category,
    this.language,
    this.tags = const [],
    this.memberCount = 0,
    this.onlineCount = 0,
    this.listedAt,
    this.lastActivityAt,
    this.isMember = false,
  });

  factory DiscoverableCircle.fromJson(Map<String, dynamic> json) {
    return DiscoverableCircle(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      description: json['description'] as String?,
      category: DiscoveryCategory.fromJson(json['category']),
      language: json['language'] as String?,
      tags: _stringList(json['tags']),
      memberCount: _int(json['member_count']),
      onlineCount: _int(json['online_count']),
      listedAt: _time(json['listed_at']),
      lastActivityAt: _time(json['last_activity_at']),
      isMember: json['is_member'] == true,
    );
  }

  final String id;
  final String name;
  final String? avatarUrl;
  final String? description;
  final DiscoveryCategory? category;
  final String? language;
  final List<String> tags;
  final int memberCount;
  final int onlineCount;
  final DateTime? listedAt;
  final DateTime? lastActivityAt;

  /// The current user is already in the circle.
  final bool isMember;

  DiscoverableCircle copyWith({bool? isMember, int? memberCount}) {
    return DiscoverableCircle(
      id: id,
      name: name,
      avatarUrl: avatarUrl,
      description: description,
      category: category,
      language: language,
      tags: tags,
      memberCount: memberCount ?? this.memberCount,
      onlineCount: onlineCount,
      listedAt: listedAt,
      lastActivityAt: lastActivityAt,
      isMember: isMember ?? this.isMember,
    );
  }
}

/// A channel a new member would see, by name.
class DiscoveryChannel {
  const DiscoveryChannel({required this.name, this.kind = 'text'});

  final String name;

  /// text, voice, forum, stage or announcement.
  final String kind;

  IconData get icon => switch (kind) {
    'voice' => Icons.volume_up_outlined,
    'stage' => Icons.podcasts,
    'forum' => Icons.forum_outlined,
    'announcement' => Icons.campaign_outlined,
    _ => Icons.tag,
  };
}

/// One public circle in detail, before joining.
class DiscoverableCirclePreview {
  const DiscoverableCirclePreview({
    required this.circle,
    this.rules = const [],
    this.channels = const [],
    this.isBanned = false,
  });

  factory DiscoverableCirclePreview.fromJson(Map<String, dynamic> json) {
    final channels = json['channels'];
    return DiscoverableCirclePreview(
      circle: DiscoverableCircle.fromJson(json),
      rules: json['rules_enabled'] == true
          ? _stringList(json['rules'])
          : const [],
      channels: [
        if (channels is List)
          for (final channel in channels)
            if (channel is Map)
              DiscoveryChannel(
                name: '${channel['name'] ?? ''}',
                kind: '${channel['kind'] ?? 'text'}',
              ),
      ],
      isBanned: json['is_banned'] == true,
    );
  }

  final DiscoverableCircle circle;

  /// The rules new members accept first (empty when onboarding is off).
  final List<String> rules;
  final List<DiscoveryChannel> channels;

  /// The current user is banned, so cannot join.
  final bool isBanned;
}

/// One page of discovery results.
class DiscoveryPage {
  const DiscoveryPage({required this.circles, required this.hasMore});

  final List<DiscoverableCircle> circles;
  final bool hasMore;
}

/// A circle's discovery settings.
class CircleDiscoverySettings {
  const CircleDiscoverySettings({
    this.isPublic = false,
    this.description,
    this.category,
    this.language,
    this.tags = const [],
    this.listedAt,
  });

  factory CircleDiscoverySettings.fromJson(Map<String, dynamic> json) {
    return CircleDiscoverySettings(
      isPublic: json['is_public'] == true,
      description: json['description'] as String?,
      category: DiscoveryCategory.fromJson(json['category']),
      language: json['language'] as String?,
      tags: _stringList(json['tags']),
      listedAt: _time(json['listed_at']),
    );
  }

  final bool isPublic;
  final String? description;
  final DiscoveryCategory? category;
  final String? language;
  final List<String> tags;
  final DateTime? listedAt;
}

/// Thrown when joining fails for a reason worth telling the user.
enum DiscoveryJoinProblem { banned, rateLimited, notFound, other }

class DiscoveryJoinException implements Exception {
  const DiscoveryJoinException(this.problem, [this.cause]);

  final DiscoveryJoinProblem problem;
  final Object? cause;

  String get message =>
      (cause == null ? null : joinErrorMessage(cause!)) ??
      switch (problem) {
        DiscoveryJoinProblem.banned => tr("You're banned from this circle."),
        DiscoveryJoinProblem.rateLimited => tr(
          "You've joined a lot of circles. Try again in a while.",
        ),
        DiscoveryJoinProblem.notFound => tr('This circle is no longer public.'),
        DiscoveryJoinProblem.other => tr('Could not join. Try again.'),
      };

  @override
  String toString() => 'DiscoveryJoinException($problem, $cause)';
}

DiscoveryJoinProblem _joinProblem(Object error) {
  final text = '$error';
  if (text.contains('Banned from this circle')) {
    return DiscoveryJoinProblem.banned;
  }
  // Refusals with a message of their own (invite only, review rules, a
  // circle that is down) are worded by DiscoveryJoinException.message.
  if (joinErrorMessage(error) != null) {
    return DiscoveryJoinProblem.other;
  }
  if (text.contains('42501')) {
    return DiscoveryJoinProblem.banned;
  }
  if (text.contains('PB429') || text.contains('Too many')) {
    return DiscoveryJoinProblem.rateLimited;
  }
  if (text.contains('P0002') || text.contains('not found')) {
    return DiscoveryJoinProblem.notFound;
  }
  return DiscoveryJoinProblem.other;
}

final circleDiscoveryRepositoryProvider = Provider<CircleDiscoveryRepository>((
  ref,
) {
  return CircleDiscoveryRepository(ref.watch(circleRpcProvider));
});

/// A circle's discovery settings, for its settings page.
final circleDiscoverySettingsProvider = FutureProvider.autoDispose
    .family<CircleDiscoverySettings, String>((ref, circleId) {
      return ref.watch(circleDiscoveryRepositoryProvider).settings(circleId);
    });

/// A public circle's preview.
final discoverableCirclePreviewProvider = FutureProvider.autoDispose
    .family<DiscoverableCirclePreview, String>((ref, circleId) {
      return ref.watch(circleDiscoveryRepositoryProvider).preview(circleId);
    });

/// Public circles: listing, previewing, joining and reporting them, and a
/// circle's discovery settings.
class CircleDiscoveryRepository {
  const CircleDiscoveryRepository(this._rpc);

  final CircleRpc _rpc;

  /// A page of public circles. [query] searches names, tags and
  /// descriptions; [category] narrows to one category.
  Future<DiscoveryPage> list({
    String query = '',
    DiscoveryCategory? category,
    DiscoverySort? sort,
    int offset = 0,
    int pageSize = DiscoveryLimits.pageSize,
  }) async {
    final trimmed = query.trim();
    // One more than asked tells whether there is another page.
    final rows = rpcRows(
      await _rpc('list_discoverable_circles', {
        'search_query': trimmed.isEmpty ? null : trimmed,
        'category_filter': category?.value,
        'sort_by': sort?.value,
        'page_size': pageSize + 1,
        'page_offset': offset,
      }),
    );
    final circles = [for (final row in rows) DiscoverableCircle.fromJson(row)];
    return DiscoveryPage(
      circles: circles.take(pageSize).toList(),
      hasMore: circles.length > pageSize,
    );
  }

  Future<DiscoverableCirclePreview> preview(String circleId) async {
    return DiscoverableCirclePreview.fromJson(
      rpcObject(
        await _rpc('discoverable_circle_preview', {
          'target_circle_id': circleId,
        }),
      ),
    );
  }

  /// Joins a public circle; returns its id. Throws a
  /// [DiscoveryJoinException].
  ///
  /// [answers] (by question id) go with the request when the circle asks
  /// questions before it lets people in.
  Future<String> join(String circleId, {Map<String, String>? answers}) async {
    try {
      final result = await _rpc('join_public_circle', {
        'target_circle_id': circleId,
        if (answers != null) 'answers': joinAnswersJson(answers),
      });
      return result is String ? result : circleId;
    } catch (error) {
      throw DiscoveryJoinException(_joinProblem(error), error);
    }
  }

  Future<void> report({
    required String circleId,
    required ReportReason reason,
    String details = '',
  }) async {
    await _rpc('report_circle', {
      'target_circle_id': circleId,
      'report_reason': reason.value,
      'report_details': details.trim(),
    });
  }

  Future<CircleDiscoverySettings> settings(String circleId) async {
    return CircleDiscoverySettings.fromJson(
      rpcObject(
        await _rpc('get_circle_discovery', {'target_circle_id': circleId}),
      ),
    );
  }

  Future<CircleDiscoverySettings> saveSettings({
    required String circleId,
    required bool isPublic,
    required String description,
    required DiscoveryCategory? category,
    required String? language,
    required List<String> tags,
  }) async {
    final about = description.trim();
    return CircleDiscoverySettings.fromJson(
      rpcObject(
        await _rpc('set_circle_discovery', {
          'target_circle_id': circleId,
          'make_public': isPublic,
          'about': about.isEmpty ? null : about,
          'category': category?.value,
          'language': language,
          'tag_list': [
            for (final tag in tags)
              if (normalizeDiscoveryTag(tag).isNotEmpty)
                normalizeDiscoveryTag(tag),
          ],
        }),
      ),
    );
  }
}
