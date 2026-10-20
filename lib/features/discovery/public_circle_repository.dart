import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Where a circle's short name stands after trying to save it.
enum CircleSlugProblem { invalid, reserved, taken, rateLimited, other }

class CircleSlugException implements Exception {
  const CircleSlugException(this.problem, [this.cause]);

  final CircleSlugProblem problem;
  final Object? cause;

  String get message => switch (problem) {
    CircleSlugProblem.invalid => tr(
      'A short name is 3 to 32 letters, digits and hyphens.',
    ),
    CircleSlugProblem.reserved => tr('That short name is reserved.'),
    CircleSlugProblem.taken => tr('That short name is taken.'),
    CircleSlugProblem.rateLimited => tr(
      'Too many changes. Try again in a while.',
    ),
    CircleSlugProblem.other => tr('Could not save the short name. Try again.'),
  };

  @override
  String toString() => 'CircleSlugException($problem, $cause)';
}

CircleSlugProblem _slugProblem(Object error) {
  final text = '$error';
  if (text.contains('23505') || text.contains('is taken')) {
    return CircleSlugProblem.taken;
  }
  if (text.contains('PB429') || text.contains('Too many')) {
    return CircleSlugProblem.rateLimited;
  }
  if (text.contains('reserved')) {
    return CircleSlugProblem.reserved;
  }
  if (text.contains('22023') || text.contains('A short name is')) {
    return CircleSlugProblem.invalid;
  }
  return CircleSlugProblem.other;
}

/// What opening `/c/<slug>` in the app leads to.
class ResolvedCircle {
  const ResolvedCircle({required this.circleId, required this.isMember});

  final String circleId;
  final bool isMember;
}

/// A circle's short name for its settings page; null when it has none.
final circleSlugProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  circleId,
) {
  return ref.watch(publicCircleRepositoryProvider).slug(circleId);
});

/// The circle behind `/c/<slug>`, or null when there is none to show.
final resolvedCircleSlugProvider = FutureProvider.autoDispose
    .family<ResolvedCircle?, String>((ref, slug) {
      return ref.watch(publicCircleRepositoryProvider).resolve(slug);
    });

final publicCircleRepositoryProvider = Provider<PublicCircleRepository>((ref) {
  return PublicCircleRepository(ref.watch(circleRpcProvider));
});

/// A circle's short name and public page (C8): setting it, reading it, and
/// finding the circle a `/c/<slug>` link points to.
class PublicCircleRepository {
  const PublicCircleRepository(this._rpc);

  final CircleRpc _rpc;

  Future<String?> slug(String circleId) async {
    final result = rpcObject(
      await _rpc('get_circle_slug', {'target_circle_id': circleId}),
    );
    final slug = result['slug'];
    return slug is String && slug.isNotEmpty ? slug : null;
  }

  /// Saves [slug] (null or empty removes it); returns what is stored.
  /// Throws a [CircleSlugException].
  Future<String?> setSlug(String circleId, String? slug) async {
    try {
      final result = rpcObject(
        await _rpc('set_circle_slug', {
          'target_circle_id': circleId,
          'new_slug': slug == null || slug.trim().isEmpty ? null : slug.trim(),
        }),
      );
      final stored = result['slug'];
      return stored is String && stored.isNotEmpty ? stored : null;
    } catch (error) {
      throw CircleSlugException(_slugProblem(error), error);
    }
  }

  Future<ResolvedCircle?> resolve(String slug) async {
    final result = await _rpc('resolve_circle_slug', {'circle_slug': slug});
    if (result is! Map) {
      return null;
    }
    final id = result['circle_id'];
    if (id is! String) {
      return null;
    }
    return ResolvedCircle(circleId: id, isMember: result['is_member'] == true);
  }
}
