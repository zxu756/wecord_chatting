import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_rpc.dart';

/// The badges a circle tag can carry, matching `circles.tag_badge`.
enum CircleTagBadge {
  leaf('leaf', Icons.eco),
  star('star', Icons.star_rounded),
  flame('flame', Icons.local_fire_department),
  heart('heart', Icons.favorite),
  bolt('bolt', Icons.bolt),
  moon('moon', Icons.dark_mode),
  crown('crown', Icons.workspace_premium),
  shield('shield', Icons.shield),
  gem('gem', Icons.diamond),
  music('music', Icons.music_note);

  const CircleTagBadge(this.value, this.icon);

  final String value;
  final IconData icon;

  /// Unknown values (newer servers) show as a star.
  static CircleTagBadge fromJson(Object? value) {
    for (final badge in values) {
      if (badge.value == value) {
        return badge;
      }
    }
    return star;
  }
}

/// A circle's tag: 2 to 4 characters and a badge.
class CircleTag {
  const CircleTag({required this.text, required this.badge});

  /// Null when tags are off.
  static CircleTag? maybeFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final text = json['tag'];
    if (text is! String || text.isEmpty) {
      return null;
    }
    return CircleTag(text: text, badge: CircleTagBadge.fromJson(json['badge']));
  }

  static const minLength = 2;
  static const maxLength = 4;

  final String text;
  final CircleTagBadge badge;
}

/// Why [input] cannot be a tag, or null when it can (blank turns tags
/// off). Mirrors the server's check.
String? circleTagProblem(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return null;
  }
  final length = text.characters.length;
  if (length < CircleTag.minLength || length > CircleTag.maxLength) {
    return 'length';
  }
  if (RegExp(r'[\s\p{P}\p{S}]', unicode: true).hasMatch(text)) {
    return 'characters';
  }
  return null;
}

/// A circle of the current user's that has a tag, for choosing one.
class TagCircle {
  const TagCircle({
    required this.circleId,
    required this.circleName,
    required this.tag,
    this.isSelected = false,
  });

  factory TagCircle.fromJson(Map<String, dynamic> json) {
    return TagCircle(
      circleId: json['circle_id'] as String,
      circleName: json['circle_name'] as String? ?? '',
      tag: CircleTag(
        text: json['tag'] as String? ?? '',
        badge: CircleTagBadge.fromJson(json['badge']),
      ),
      isSelected: json['is_selected'] == true,
    );
  }

  final String circleId;
  final String circleName;
  final CircleTag tag;

  /// The current user shows this circle's tag.
  final bool isSelected;
}

/// What shows next to a user's name: the circle tag they chose, and a
/// BOT badge for bot accounts.
class ProfileBadges {
  const ProfileBadges({
    this.tag,
    this.tagCircleId,
    this.tagCircleName,
    this.isBot = false,
  });

  factory ProfileBadges.fromJson(Map<String, dynamic> json) {
    return ProfileBadges(
      tag: CircleTag.maybeFromJson(json),
      tagCircleId: json['circle_id'] as String?,
      tagCircleName: json['circle_name'] as String?,
      isBot: json['is_bot'] == true,
    );
  }

  static const none = ProfileBadges();

  final CircleTag? tag;
  final String? tagCircleId;
  final String? tagCircleName;

  /// A bot account, shown with a BOT badge.
  final bool isBot;

  bool get isEmpty => tag == null && !isBot;
}

final circleTagRepositoryProvider = Provider<CircleTagRepository>((ref) {
  return CircleTagRepository(ref.watch(circleRpcProvider));
});

/// A circle's tag, for its settings; null when tags are off.
final circleTagProvider = FutureProvider.autoDispose.family<CircleTag?, String>(
  (ref, circleId) {
    return ref.watch(circleTagRepositoryProvider).getCircleTag(circleId);
  },
);

/// The current user's circles that have a tag.
final tagCirclesProvider = FutureProvider.autoDispose<List<TagCircle>>((ref) {
  return ref.watch(circleTagRepositoryProvider).listTagCircles();
});

final profileBadgeLoaderProvider = Provider<ProfileBadgeLoader>((ref) {
  return ProfileBadgeLoader(ref.watch(circleRpcProvider));
});

/// What shows next to [userId]'s name, loaded together with every other
/// name shown at the same time and kept for the session. Failures show
/// nothing.
final profileBadgesProvider = FutureProvider.family<ProfileBadges, String>((
  ref,
  userId,
) {
  return ref.watch(profileBadgeLoaderProvider).load(userId);
});

/// Forgets [userId]'s badges, so they load again (after changing them).
void refreshProfileBadges(WidgetRef ref, String userId) {
  ref.read(profileBadgeLoaderProvider).forget(userId);
  ref.invalidate(profileBadgesProvider(userId));
}

/// Loads profile badges for every user asked about in the same frame with
/// one call.
class ProfileBadgeLoader {
  ProfileBadgeLoader(this._rpc);

  static const _batchSize = 200;

  final CircleRpc _rpc;
  final _cache = <String, ProfileBadges>{};
  final _waiting = <String, List<Completer<ProfileBadges>>>{};
  var _scheduled = false;

  Future<ProfileBadges> load(String userId) {
    final cached = _cache[userId];
    if (cached != null) {
      return Future.value(cached);
    }
    final completer = Completer<ProfileBadges>();
    _waiting.putIfAbsent(userId, () => []).add(completer);
    if (!_scheduled) {
      _scheduled = true;
      scheduleMicrotask(_flush);
    }
    return completer.future;
  }

  void forget(String userId) => _cache.remove(userId);

  Future<void> _flush() async {
    _scheduled = false;
    final batch = Map.of(_waiting);
    _waiting.clear();
    final ids = batch.keys.toList();
    for (var start = 0; start < ids.length; start += _batchSize) {
      final chunk = ids.sublist(
        start,
        start + _batchSize > ids.length ? ids.length : start + _batchSize,
      );
      Map<String, ProfileBadges>? loaded;
      try {
        final rows = await _rpc('list_profile_badges', {'user_ids': chunk});
        loaded = {
          for (final row in rpcRows(rows))
            if (row['user_id'] case final String id)
              id: ProfileBadges.fromJson(row),
        };
      } catch (_) {
        loaded = null;
      }
      for (final id in chunk) {
        final badges = loaded?[id] ?? ProfileBadges.none;
        if (loaded != null) {
          _cache[id] = badges;
        }
        for (final completer
            in batch[id] ?? const <Completer<ProfileBadges>>[]) {
          completer.complete(badges);
        }
      }
    }
  }
}

class CircleTagRepository {
  const CircleTagRepository(this._rpc);

  final CircleRpc _rpc;

  Future<CircleTag?> getCircleTag(String circleId) async {
    final result = await _rpc('get_circle_tag', {'target_circle_id': circleId});
    return CircleTag.maybeFromJson(result);
  }

  /// Sets the circle's tag; a blank [text] turns tags off.
  Future<CircleTag?> setCircleTag({
    required String circleId,
    required String text,
    required CircleTagBadge badge,
  }) async {
    final result = await _rpc('set_circle_tag', {
      'target_circle_id': circleId,
      'circle_tag': text.trim(),
      'badge': badge.value,
    });
    return CircleTag.maybeFromJson(result);
  }

  Future<List<TagCircle>> listTagCircles() async {
    final rows = await _rpc('list_tag_circles', const {});
    return rpcRows(rows).map(TagCircle.fromJson).toList();
  }

  /// Shows [circleId]'s tag next to the current user's name; null shows
  /// none.
  Future<void> setDisplayTag(String? circleId) async {
    await _rpc('set_display_circle_tag', {'target_circle_id': circleId});
  }
}
