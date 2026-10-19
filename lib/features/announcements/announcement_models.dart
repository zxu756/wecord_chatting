import 'package:flutter/foundation.dart';

/// What kind of official notice this is.
enum AnnouncementKind {
  /// Something the team tells everybody.
  announcement('announcement'),

  /// The team's answer to the person's own feedback (K7).
  feedbackReply('feedback_reply');

  const AnnouncementKind(this.value);

  final String value;

  static AnnouncementKind parse(Object? value) {
    for (final kind in values) {
      if (kind.value == value) {
        return kind;
      }
    }
    return AnnouncementKind.announcement;
  }
}

/// An official notice from "WeCord team" in Notifications. The team is only
/// the name on the card; it is not an account and nothing was sent as a chat.
@immutable
class Announcement {
  const Announcement({
    required this.id,
    required this.kind,
    required this.titleEn,
    required this.titleZh,
    required this.bodyEn,
    required this.bodyZh,
    required this.publishedAt,
    required this.read,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    String text(String key) => json[key] is String ? json[key] as String : '';
    return Announcement(
      id: text('id'),
      kind: AnnouncementKind.parse(json['kind']),
      titleEn: text('title_en'),
      titleZh: text('title_zh'),
      bodyEn: text('body_en'),
      bodyZh: text('body_zh'),
      publishedAt:
          DateTime.tryParse(text('published_at')) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      read: json['read'] == true,
    );
  }

  final String id;
  final AnnouncementKind kind;
  final String titleEn;
  final String titleZh;
  final String bodyEn;
  final String bodyZh;
  final DateTime publishedAt;
  final bool read;

  /// The title in the language of the app, or the other one when this one
  /// was left empty.
  String title({required bool chinese}) =>
      _pick(chinese ? titleZh : titleEn, chinese ? titleEn : titleZh);

  String body({required bool chinese}) =>
      _pick(chinese ? bodyZh : bodyEn, chinese ? bodyEn : bodyZh);

  static String _pick(String wanted, String other) =>
      wanted.trim().isNotEmpty ? wanted.trim() : other.trim();

  Announcement copyWith({bool? read}) => Announcement(
    id: id,
    kind: kind,
    titleEn: titleEn,
    titleZh: titleZh,
    bodyEn: bodyEn,
    bodyZh: bodyZh,
    publishedAt: publishedAt,
    read: read ?? this.read,
  );
}
