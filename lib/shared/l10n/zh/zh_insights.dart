// Chinese for circle insights (圈子数据) and invite tracking (邀请追踪):
// circle settings → Insights, and "Brought 12 · still here 9" on the invite
// links.
// "Messages" is 消息 here (the context key 'insights|Messages'), not 私信, which
// is the Messages tab. "Brought" reads 带来, "still here" 仍在圈内. Numbers
// under 5 are "<5" (少于 5).
const zhInsights = <String, String>{
  // Settings row and page.
  'Insights': '数据',
  'Members, activity and invites': '成员、活跃度与邀请',
  'Range': '时间范围',
  'Could not load insights.': '无法加载数据。',
  'insights|Messages': '消息',
  'Activity': '活跃度',
  'Active members': '活跃成员',
  'Members now': '当前成员',
  'Left': '退出',
  'Voice minutes': '语音分钟数',
  'Busiest hours': '活跃时段',
  'Retention': '留存',

  // Small circles and the "<5" rule.
  'Insights fill in once the circle has at least 5 members. Until then every number is hidden, so no one can be picked out.':
      '圈子至少有 5 位成员后，数据才会显示。在此之前所有数字都会隐藏，以免推断出某个人。',
  'Numbers under 5 show as <5, so no one can be picked out. Days are counted in UTC, and the map in your time zone.':
      '少于 5 的数字显示为“<5”，以免推断出某个人。按天统计使用 UTC 时间，活跃时段图使用你所在的时区。',
  'Hatched: fewer than 5': '斜线：少于 5',
  'Fewer than 5': '少于 5',
  'fewer than 5': '少于 5',
  'Quieter': '较少',
  'Busier': '较多',

  // Charts, for screen readers.
  'No member numbers to show yet.': '暂时没有可显示的成员数据。',
  'Members went from {from} to {to} over {days} days.':
      '{days} 天内，成员从 {from} 人变为 {to} 人。',
  '{what} per day, {days} days. Busiest day: {top}.':
      '{what}，每天一栏，共 {days} 天。最多的一天：{top}。',
  'Messages by weekday and hour: no busy hours to show yet.':
      '按星期和小时统计的消息：暂时没有活跃时段。',
  'Messages by weekday and hour. Busiest: {day} at {hour}:00.':
      '按星期和小时统计的消息。最活跃：{day} {hour}:00。',

  // Rankings.
  'No channel activity yet.': '频道里还没有动静。',
  'No one joined with an invite link in this range.': '这段时间里没有人通过邀请链接加入。',
  'Invite link': '邀请链接',
  'Link by {name}': '{name} 创建的链接',
  'revoked': '已撤销',
  'brought': '带来',
  'still here {count}': '仍在 {count}',
  'Who brought people': '谁带来了新人',
  'No one was brought in by a member in this range.': '这段时间里没有成员带来新人。',

  // Retention.
  'Newcomers still here': '新人仍在圈内',
  'Of the people who joined in this range': '这段时间内加入的人中',
  'Came back': '回访',
  'Of the people active the week before last, the share active last week':
      '前一周活跃的人中，上周仍然活跃的比例',
  'Not enough people to say yet.': '人数还不够，暂时无法统计。',
  'not enough people to say': '人数不够，暂时无法统计',

  // The invite list.
  'Brought {brought} · still here {remaining}':
      '带来 {brought} 人 · 仍在 {remaining} 人',
};
