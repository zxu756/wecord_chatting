import 'dart:math' as math;

/// A get_circle_insights result for [days] days ending 2026-10-18. Counts of
/// -1 are the server's "fewer than 5". [small] is a circle of fewer than 5
/// members: everything hidden.
Map<String, dynamic> insightsJson({
  int days = 30,
  bool small = false,
  bool withRetention = true,
  bool withInvites = true,
}) {
  int hide(int value) => small || (value > 0 && value < 5) ? -1 : value;
  final last = DateTime.utc(2026, 10, 18);
  final series = [
    for (var i = 0; i < days; i++)
      {
        'day': last
            .subtract(Duration(days: days - 1 - i))
            .toIso8601String()
            .substring(0, 10),
        'members': hide(40 + i ~/ 2),
        'joined': hide(i % 6),
        'left': hide(i % 4 == 0 ? 1 : 0),
        'active': hide(8 + (i * 3) % 14),
        'messages': hide(30 + (i * 17) % 90),
        'voice_minutes': hide((i * 11) % 70),
      },
  ];
  final rows = [
    for (var weekday = 0; weekday < 7; weekday++)
      [
        for (var hour = 0; hour < 24; hour++)
          hide(
            // Busy evenings, quiet nights, a few cells under 5.
            hour < 7
                ? (hour == 3 ? 2 : 0)
                : (math.max(0, 40 - (hour - 20).abs() * 5) +
                      (weekday == 5 || weekday == 6 ? 10 : 0)),
          ),
      ],
  ];
  return {
    'circle_id': 'circle-1',
    'range_days': days,
    'from': series.first['day'],
    'to': series.last['day'],
    'small': small,
    'members_now': small ? -1 : 55,
    'series': series,
    'totals': {
      'joined': hide(61),
      'left': hide(9),
      'messages': hide(2840),
      'voice_minutes': hide(940),
      'active': hide(31),
    },
    'heatmap': {'weekday_start': 0, 'rows': rows},
    'channels': [
      {'channel_id': 'ch-1', 'name': 'general', 'messages': hide(1500)},
      {
        'channel_id': 'ch-2',
        'name': 'palette-challenges',
        'messages': hide(820),
      },
      {'channel_id': 'ch-3', 'name': 'showcase', 'messages': hide(410)},
      {'channel_id': 'ch-4', 'name': 'off-topic', 'messages': hide(3)},
    ],
    'invites': withInvites
        ? [
            {
              'created_by_name': 'Bart the Bold',
              'created_at': '2026-10-02T09:00:00Z',
              'revoked': false,
              'brought': hide(18),
              'remaining': hide(15),
            },
            {
              'created_by_name': 'Ada Lovelace',
              'created_at': '2026-09-20T09:00:00Z',
              'revoked': true,
              'brought': hide(4),
              'remaining': hide(3),
            },
          ]
        : <Map<String, dynamic>>[],
    'inviters': withInvites
        ? [
            {
              'name': 'Bart the Bold',
              'brought': hide(21),
              'remaining': hide(17),
            },
            {'name': 'Ada Lovelace', 'brought': hide(6), 'remaining': hide(5)},
          ]
        : <Map<String, dynamic>>[],
    'retention': {
      'joined_kept': withRetention && !small ? 0.78 : null,
      'active_returning': withRetention && !small ? 0.64 : null,
    },
  };
}
