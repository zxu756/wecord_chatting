import 'package:wecord/features/profile/support_links.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// How a friendship, or a friend request, started. The wire names are the
/// ones `friend_requests.source` accepts.
enum FriendSource {
  /// Found by username in Add friend.
  search('search'),

  /// A scanned QR code.
  qr('qr'),

  /// A member list of a group chat.
  group('group'),

  /// A contact card sent in a chat.
  card('card'),

  /// A member list of a circle.
  circle('circle');

  const FriendSource(this.wire);

  final String wire;

  static FriendSource? fromWire(Object? value) {
    for (final source in values) {
      if (source.wire == value) {
        return source;
      }
    }
    return null;
  }

  /// "Found by username": shown beside "Source" on a profile.
  String get label => switch (this) {
    FriendSource.search => tr('Found by username'),
    FriendSource.qr => tr('Scanned a QR code'),
    FriendSource.group => tr('From a group chat'),
    FriendSource.card => tr('From a contact card'),
    FriendSource.circle => tr('From a circle'),
  };
}

/// A birthday: a month and a day, never a year.
class ProfileBirthday {
  const ProfileBirthday({required this.month, required this.day});

  static ProfileBirthday? maybeFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final month = json['month'];
    final day = json['day'];
    if (month is! int || day is! int) {
      return null;
    }
    return ProfileBirthday(month: month, day: day);
  }

  final int month;
  final int day;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// "10 月 18 日" or "October 18".
  String get label => AppStrings.isChinese
      ? '$month 月 $day 日'
      : '${_months[(month - 1).clamp(0, 11)]} $day';

  /// The last day of [month] counting February as 29 (a leap day exists).
  static int daysIn(int month) => switch (month) {
    2 => 29,
    4 || 6 || 9 || 11 => 30,
    _ => 31,
  };

  @override
  bool operator ==(Object other) =>
      other is ProfileBirthday && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(month, day);
}

/// Who sees my birthday.
enum BirthdayVisibility {
  friends('friends'),
  self('self');

  const BirthdayVisibility(this.wire);

  final String wire;

  static BirthdayVisibility fromWire(Object? value) =>
      value == 'self' ? BirthdayVisibility.self : BirthdayVisibility.friends;
}

/// Who sees my status.
enum StatusVisibility {
  everyone('everyone'),
  friends('friends'),
  starred('starred'),
  self('self');

  const StatusVisibility(this.wire);

  final String wire;

  static StatusVisibility fromWire(Object? value) {
    for (final choice in values) {
      if (choice.wire == value) {
        return choice;
      }
    }
    return StatusVisibility.everyone;
  }

  String get label => switch (this) {
    StatusVisibility.everyone => tr('Everyone'),
    StatusVisibility.friends => tr('Friends'),
    StatusVisibility.starred => tr('Starred friends'),
    StatusVisibility.self => tr('Only me'),
  };
}

/// My own birthday, its audience and my birthday reminders.
class MyBirthday {
  const MyBirthday({
    this.birthday,
    this.visibility = BirthdayVisibility.friends,
    this.reminders = true,
  });

  final ProfileBirthday? birthday;
  final BirthdayVisibility visibility;

  /// Whether I am reminded of my friends' birthdays.
  final bool reminders;
}

/// My own profile extras: birthday, status audience and support links.
class MyProfileExtras {
  const MyProfileExtras({
    this.birthday = const MyBirthday(),
    this.statusVisibility = StatusVisibility.everyone,
    this.links = const <SupportLink>[],
  });

  factory MyProfileExtras.fromJson(Object? json) {
    if (json is! Map) {
      return const MyProfileExtras();
    }
    final birthday = json['birthday'];
    return MyProfileExtras(
      birthday: birthday is Map
          ? MyBirthday(
              birthday: ProfileBirthday.maybeFromJson(birthday),
              visibility: BirthdayVisibility.fromWire(birthday['visibility']),
              reminders: birthday['reminders'] != false,
            )
          : const MyBirthday(),
      statusVisibility: StatusVisibility.fromWire(json['status_visibility']),
      links: SupportLink.listFromJson(json['links']),
    );
  }

  final MyBirthday birthday;
  final StatusVisibility statusVisibility;
  final List<SupportLink> links;
}

/// A group chat, circle or friend two people have in common.
class MutualItem {
  const MutualItem({required this.id, required this.title, this.avatarUrl});

  final String id;
  final String title;
  final String? avatarUrl;
}

/// What two people have in common: always the numbers, the names only when
/// the other person is the viewer's friend (the server leaves them out).
class Mutuals {
  const Mutuals({
    this.friendCount = 0,
    this.groupCount = 0,
    this.circleCount = 0,
    this.friends = const <MutualItem>[],
    this.groups = const <MutualItem>[],
    this.circles = const <MutualItem>[],
  });

  factory Mutuals.fromJson(Object? json) {
    if (json is! Map) {
      return const Mutuals();
    }
    List<MutualItem> items(Object? value, String titleKey) => [
      if (value is List)
        for (final item in value.whereType<Map<dynamic, dynamic>>())
          if (item['id'] is String)
            MutualItem(
              id: item['id'] as String,
              title: (item[titleKey] as String?) ?? '',
              avatarUrl: item['avatar_url'] as String?,
            ),
    ];
    return Mutuals(
      friendCount: (json['friend_count'] as num?)?.toInt() ?? 0,
      groupCount: (json['group_count'] as num?)?.toInt() ?? 0,
      circleCount: (json['circle_count'] as num?)?.toInt() ?? 0,
      friends: items(json['friends'], 'display_name'),
      groups: items(json['groups'], 'title'),
      circles: items(json['circles'], 'name'),
    );
  }

  final int friendCount;
  final int groupCount;
  final int circleCount;
  final List<MutualItem> friends;
  final List<MutualItem> groups;
  final List<MutualItem> circles;

  bool get isEmpty => friendCount == 0 && groupCount == 0 && circleCount == 0;
}

/// What the profile page shows beyond the profile summary.
class ProfileInsights {
  const ProfileInsights({
    this.mutuals = const Mutuals(),
    this.birthday,
    this.links = const <SupportLink>[],
    this.source,
  });

  factory ProfileInsights.fromJson(Object? json) {
    if (json is! Map) {
      return const ProfileInsights();
    }
    return ProfileInsights(
      mutuals: Mutuals.fromJson(json['mutuals']),
      birthday: ProfileBirthday.maybeFromJson(json['birthday']),
      links: SupportLink.listFromJson(json['links']),
      source: FriendSource.fromWire(json['source']),
    );
  }

  static const empty = ProfileInsights();

  final Mutuals mutuals;
  final ProfileBirthday? birthday;
  final List<SupportLink> links;
  final FriendSource? source;
}

/// A friend's status as the bubble over their avatar shows it.
class FriendStatus {
  const FriendStatus({
    required this.userId,
    this.emoji,
    this.text,
    this.expiresAt,
  });

  final String userId;
  final String? emoji;
  final String? text;

  /// When it clears, or null when it stays until changed.
  final DateTime? expiresAt;

  /// Whether there is something to show, and it has not expired by [now]
  /// (the server never sends an expired one, but one can expire on screen).
  bool isActiveAt(DateTime now) {
    if ((emoji ?? text) == null) {
      return false;
    }
    final end = expiresAt;
    return end == null || end.isAfter(now.toUtc());
  }

  /// The bubble's text, at most [maxBubbleChars] characters, cut with an
  /// ellipsis.
  String get bubbleLabel {
    final cleaned = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) {
      return emoji ?? '';
    }
    final runes = cleaned.runes.toList();
    final cut = runes.length > maxBubbleChars
        ? '${String.fromCharCodes(runes.take(maxBubbleChars))}…'
        : cleaned;
    return emoji == null ? cut : '$emoji $cut';
  }

  /// The whole status, for a screen reader and the reply.
  String get fullLabel =>
      [emoji, text].whereType<String>().where((s) => s.isNotEmpty).join(' ');

  static const maxBubbleChars = 12;
}

/// A friend whose birthday is today, for the cards in Notifications.
class BirthdayFriend {
  const BirthdayFriend({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  factory BirthdayFriend.fromJson(Map<String, dynamic> json) {
    return BirthdayFriend(
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
}
