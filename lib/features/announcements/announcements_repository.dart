import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/announcements/announcement_models.dart';
import 'package:wecord/features/circles/circle_rpc.dart';

/// The caller's official notices (`list_my_announcements` and friends,
/// migration 202610240620).
abstract interface class AnnouncementsRepository {
  /// Newest first, without the ones the person dismissed.
  Future<List<Announcement>> list();

  Future<void> markRead(String id);

  /// Takes the notice off the person's list.
  Future<void> dismiss(String id);
}

class SupabaseAnnouncementsRepository implements AnnouncementsRepository {
  const SupabaseAnnouncementsRepository(this._rpc);

  final CircleRpc _rpc;

  @override
  Future<List<Announcement>> list() async {
    final result = await _rpc('list_my_announcements', const {});
    return [
      for (final row in rpcRows(result))
        if (row['id'] is String) Announcement.fromJson(row),
    ];
  }

  @override
  Future<void> markRead(String id) async {
    await _rpc('mark_announcement_read', {'target_announcement_id': id});
  }

  @override
  Future<void> dismiss(String id) async {
    await _rpc('dismiss_announcement', {'target_announcement_id': id});
  }
}

final announcementsRepositoryProvider = Provider<AnnouncementsRepository>((
  ref,
) {
  return SupabaseAnnouncementsRepository(ref.watch(circleRpcProvider));
});
