import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/announcements/announcement_models.dart';
import 'package:wecord/features/announcements/announcements_repository.dart';

/// The person's official notices, newest first. A failed lookup (offline, or
/// a server that does not have the function yet) is an empty list: Notifications
/// carries on with everything else.
final announcementsProvider = FutureProvider.autoDispose<List<Announcement>>((
  ref,
) async {
  try {
    return await ref.watch(announcementsRepositoryProvider).list();
  } catch (_) {
    return const [];
  }
});

/// Official notices not read yet, for the Notifications badge.
final announcementsUnreadProvider = Provider.autoDispose<int>((ref) {
  return ref
          .watch(announcementsProvider)
          .value
          ?.where((notice) => !notice.read)
          .length ??
      0;
});
