import 'package:wecord/features/announcements/announcement_models.dart';
import 'package:wecord/features/announcements/announcements_repository.dart';

Announcement notice(
  String id, {
  AnnouncementKind kind = AnnouncementKind.announcement,
  String titleEn = 'Maintenance tonight',
  String titleZh = '今晚维护',
  String bodyEn = 'We pause at 22:00 for ten minutes.',
  String bodyZh = '22:00 暂停十分钟。',
  bool read = false,
  DateTime? publishedAt,
}) => Announcement(
  id: id,
  kind: kind,
  titleEn: titleEn,
  titleZh: titleZh,
  bodyEn: bodyEn,
  bodyZh: bodyZh,
  publishedAt: publishedAt ?? DateTime.now().subtract(const Duration(hours: 2)),
  read: read,
);

/// Keeps the notices in memory, like the database does for one person.
class FakeAnnouncementsRepository implements AnnouncementsRepository {
  FakeAnnouncementsRepository([List<Announcement> items = const []])
    : items = [...items];

  List<Announcement> items;
  final reads = <String>[];
  final dismissals = <String>[];
  Object? listError;
  Object? writeError;

  @override
  Future<List<Announcement>> list() async {
    final error = listError;
    if (error != null) {
      throw error;
    }
    return [...items];
  }

  @override
  Future<void> markRead(String id) async {
    final error = writeError;
    if (error != null) {
      throw error;
    }
    reads.add(id);
    items = [
      for (final item in items)
        if (item.id == id) item.copyWith(read: true) else item,
    ];
  }

  @override
  Future<void> dismiss(String id) async {
    final error = writeError;
    if (error != null) {
      throw error;
    }
    dismissals.add(id);
    items = [
      for (final item in items)
        if (item.id != id) item,
    ];
  }
}
