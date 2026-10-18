/// A count from get_circle_insights. The server sends -1 for a number
/// between 1 and 4 ("fewer than 5"): the page shows it as "<5" and never
/// draws it as a size, so a small number says nothing about a person.
class InsightCount {
  const InsightCount(this.value);

  /// A count the server hid.
  static const hidden = InsightCount(-1);

  static const zero = InsightCount(0);

  /// The count, or -1 when it is hidden.
  final int value;

  bool get isHidden => value < 0;

  /// The count to draw: 0 for a hidden one, whose size is not known.
  int get drawn => isHidden ? 0 : value;

  /// "12", or "<5" for a hidden count.
  String get text => isHidden ? '<5' : '$value';

  static InsightCount parse(Object? raw) {
    if (raw is num) {
      final value = raw.toInt();
      return value < 0 ? hidden : InsightCount(value);
    }
    return zero;
  }

  @override
  bool operator ==(Object other) =>
      other is InsightCount && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// One day of the series.
class InsightDay {
  const InsightDay({
    required this.day,
    required this.members,
    required this.joined,
    required this.left,
    required this.active,
    required this.messages,
    required this.voiceMinutes,
  });

  factory InsightDay.fromJson(Map<String, dynamic> json) {
    return InsightDay(
      day: DateTime.parse(json['day'] as String),
      members: InsightCount.parse(json['members']),
      joined: InsightCount.parse(json['joined']),
      left: InsightCount.parse(json['left']),
      active: InsightCount.parse(json['active']),
      messages: InsightCount.parse(json['messages']),
      voiceMinutes: InsightCount.parse(json['voice_minutes']),
    );
  }

  final DateTime day;
  final InsightCount members;
  final InsightCount joined;
  final InsightCount left;
  final InsightCount active;
  final InsightCount messages;
  final InsightCount voiceMinutes;
}

class InsightTotals {
  const InsightTotals({
    required this.joined,
    required this.left,
    required this.active,
    required this.messages,
    required this.voiceMinutes,
  });

  factory InsightTotals.fromJson(Map<String, dynamic> json) {
    return InsightTotals(
      joined: InsightCount.parse(json['joined']),
      left: InsightCount.parse(json['left']),
      active: InsightCount.parse(json['active']),
      messages: InsightCount.parse(json['messages']),
      voiceMinutes: InsightCount.parse(json['voice_minutes']),
    );
  }

  final InsightCount joined;
  final InsightCount left;

  /// Distinct people active in the range.
  final InsightCount active;
  final InsightCount messages;
  final InsightCount voiceMinutes;
}

/// Messages by weekday (0 = Sunday) and hour, in the viewer's time zone.
class InsightHeatmap {
  const InsightHeatmap(this.rows);

  factory InsightHeatmap.fromJson(Map<String, dynamic> json) {
    final rows = json['rows'];
    return InsightHeatmap([
      if (rows is List)
        for (final row in rows)
          [
            if (row is List)
              for (final cell in row) InsightCount.parse(cell),
          ],
    ]);
  }

  /// Seven rows from Sunday, 24 cells each.
  final List<List<InsightCount>> rows;

  bool get isEmpty => rows.every((row) => row.every((cell) => cell.value == 0));

  /// The busiest shown cell, which the colors scale to.
  int get peak {
    var peak = 0;
    for (final row in rows) {
      for (final cell in row) {
        if (cell.value > peak) {
          peak = cell.value;
        }
      }
    }
    return peak;
  }
}

class InsightChannel {
  const InsightChannel({
    required this.channelId,
    required this.name,
    required this.messages,
  });

  factory InsightChannel.fromJson(Map<String, dynamic> json) {
    return InsightChannel(
      channelId: json['channel_id'] as String,
      name: json['name'] as String? ?? '',
      messages: InsightCount.parse(json['messages']),
    );
  }

  final String channelId;
  final String name;
  final InsightCount messages;
}

/// An invite link in the ranking, named by who made it and when, never by
/// its code.
class InsightInvite {
  const InsightInvite({
    required this.createdAt,
    required this.revoked,
    required this.brought,
    required this.remaining,
    this.createdByName,
  });

  factory InsightInvite.fromJson(Map<String, dynamic> json) {
    return InsightInvite(
      createdByName: json['created_by_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      revoked: json['revoked'] as bool? ?? false,
      brought: InsightCount.parse(json['brought']),
      remaining: InsightCount.parse(json['remaining']),
    );
  }

  final String? createdByName;
  final DateTime createdAt;
  final bool revoked;
  final InsightCount brought;
  final InsightCount remaining;
}

/// A member in the ranking of who brought people in.
class InsightInviter {
  const InsightInviter({
    required this.name,
    required this.brought,
    required this.remaining,
  });

  factory InsightInviter.fromJson(Map<String, dynamic> json) {
    return InsightInviter(
      name: json['name'] as String? ?? '',
      brought: InsightCount.parse(json['brought']),
      remaining: InsightCount.parse(json['remaining']),
    );
  }

  final String name;
  final InsightCount brought;
  final InsightCount remaining;
}

/// Ratios from 0 to 1, or null when too few people stand behind them.
class InsightRetention {
  const InsightRetention({this.joinedKept, this.activeReturning});

  factory InsightRetention.fromJson(Map<String, dynamic> json) {
    return InsightRetention(
      joinedKept: (json['joined_kept'] as num?)?.toDouble(),
      activeReturning: (json['active_returning'] as num?)?.toDouble(),
    );
  }

  /// Of the people who joined in the range, the share still here.
  final double? joinedKept;

  /// Of the people active the week before last, the share active last week.
  final double? activeReturning;
}

/// What get_circle_insights returned.
class CircleInsights {
  const CircleInsights({
    required this.rangeDays,
    required this.small,
    required this.membersNow,
    required this.series,
    required this.totals,
    required this.heatmap,
    required this.channels,
    required this.invites,
    required this.inviters,
    required this.retention,
  });

  factory CircleInsights.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic> json) parse) {
      final raw = json[key];
      return [
        if (raw is List)
          for (final item in raw)
            if (item is Map) parse(Map<String, dynamic>.from(item)),
      ];
    }

    Map<String, dynamic> object(String key) {
      final raw = json[key];
      return raw is Map ? Map<String, dynamic>.from(raw) : const {};
    }

    return CircleInsights(
      rangeDays: (json['range_days'] as num?)?.toInt() ?? 30,
      small: json['small'] as bool? ?? false,
      membersNow: InsightCount.parse(json['members_now']),
      series: list('series', InsightDay.fromJson),
      totals: InsightTotals.fromJson(object('totals')),
      heatmap: InsightHeatmap.fromJson(object('heatmap')),
      channels: list('channels', InsightChannel.fromJson),
      invites: list('invites', InsightInvite.fromJson),
      inviters: list('inviters', InsightInviter.fromJson),
      retention: InsightRetention.fromJson(object('retention')),
    );
  }

  final int rangeDays;

  /// The circle has fewer than 5 members: every number is hidden.
  final bool small;
  final InsightCount membersNow;
  final List<InsightDay> series;
  final InsightTotals totals;
  final InsightHeatmap heatmap;
  final List<InsightChannel> channels;
  final List<InsightInvite> invites;
  final List<InsightInviter> inviters;
  final InsightRetention retention;
}

/// "Brought 12 · still here 9" for one invite link.
class InviteStats {
  const InviteStats({required this.brought, required this.remaining});

  final int brought;
  final int remaining;
}
