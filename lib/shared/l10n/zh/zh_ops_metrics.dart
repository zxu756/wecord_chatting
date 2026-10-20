// Chinese for the admin console's Stats and Alerts tabs (K2 product stats,
// K3 monitoring and alerts, K5 error reports 2.0) and for the alert cards in
// Notifications. 'Warning', 'Unknown', 'Text', 'Files', 'Notes', 'Tasks',
// 'Moments', 'Dailies', 'Stickers', 'Web', 'Close', '{count} days', '7 days'
// and '30 days' are already translated elsewhere. 'Open', 'Closed', 'Day'
// and 'New' mean something else there, so the words here are worded in their
// own contexts ('Alerts|Open', 'Stats|Day', ...).
const zhOpsMetrics = <String, String>{
  // The two tabs of the console.
  'Stats': '数据',
  'Alerts': '告警',

  // Stats: the tiles and charts.
  'Could not load the stats.': '无法加载数据。',
  'Active today': '今日活跃',
  'Active this week': '本周活跃',
  'Active this month': '本月活跃',
  'New people': '新注册',
  'Active people': '活跃用户',
  'No numbers to show yet.': '还没有可显示的数据。',
  'Active people per day, {days} days. Busiest day: {top}.':
      '近 {days} 天每天的活跃用户数，最高一天 {top} 人。',
  'Coming back': '留存',
  'Nobody new yet in this range.': '这段时间内还没有新注册的人。',
  'Of the people who joined on a day, the share who were active again 1, 7 and 30 days later.':
      '某一天注册的人里，1 天、7 天和 30 天后又活跃的比例。',
  'Next day': '次日',
  '{day}: {new} new, {d1} next day, {d7} after 7 days, {d30} after 30 days':
      '{day}：新增 {new} 人，次日 {d1}，7 天后 {d7}，30 天后 {d30}',
  'Stats|Day': '日期',
  'Stats|New': '新增',
  'Messages per day, {days} days. {total} in all.':
      '近 {days} 天每天的消息数，共 {total} 条。',
  'No messages in this range.': '这段时间内没有消息。',
  'Photos': '图片',
  'Voice messages': '语音消息',
  'Polls': '投票',
  'System notices': '系统通知',
  'What people use': '功能使用量',
  'Circle posts': '圈子帖子',
  'Chat events': '聊天活动',
  'Voice channel minutes': '语音频道分钟数',
  'AI requests': 'AI 请求数',
  'Voice minutes are counted from a look every 15 minutes, so they are close, not exact.':
      '语音分钟数每 15 分钟抽样一次，数字接近实际，但不精确。',
  'Health': '运行状况',
  'Pushes delivered': '推送送达',
  'Pushes failed': '推送失败',
  'Dead push subscriptions removed': '已清除的失效推送订阅',
  'Error reports': '错误报告',
  'Storage in use': '存储用量',
  'Storage added': '新增存储',
  'App versions, last 7 days': '各版本，近 7 天',
  'No version has reported yet.': '还没有版本上报。',
  '{version} on {platform}': '{platform} 上的 {version}',
  '{count} active': '{count} 人活跃',
  '{percent}% crash-free': '{percent}% 无崩溃',
  'unknown': '未知',
  'Crash-free is the share of active people who did not hit a crash. Reports from signed-out people are not counted here.':
      '“无崩溃”指活跃用户中没有遇到崩溃的比例。未登录用户的报告不计入这里。',
  'Only counts are kept. Nothing is measured on devices, no message is read, and people are counted from a scrambled key that is deleted after 45 days. Days are UTC.':
      '只保存数量。设备上不做任何统计，也不读取任何消息；统计人数用的是一个打乱后的标识，45 天后就会删除。日期按 UTC 计算。',

  // Alerts: the checks.
  'Checks': '检查项',
  'Could not load the checks.': '无法加载检查结果。',
  'The checks have not run yet.': '检查还没有运行过。',
  'The checks have not run for {minutes} minutes. If this goes on, scheduled tasks may have stopped.':
      '检查已有 {minutes} 分钟没有运行。如果一直这样，定时任务可能已经停了。',
  'The checks ran a moment ago.': '检查刚刚运行过。',
  'The checks ran {minutes} minutes ago.': '检查在 {minutes} 分钟前运行过。',
  'Check|OK': '正常',
  'Failing': '故障',
  'Scheduled tasks': '定时任务',
  'Failed cron jobs': '失败的定时任务',
  'Edge Function calls': '边缘函数调用',
  'Push delivery': '推送送达',
  'AI limits': 'AI 额度',
  'App versions': '应用版本',
  'New kinds of error': '新的错误类型',
  'Cannot be checked right now.': '现在无法检查。',
  'Last good run {minutes} min ago': '上次成功运行在 {minutes} 分钟前',
  'No good run on record': '没有成功运行的记录',
  '{count} failed runs in 30 min': '30 分钟内失败 {count} 次',
  '{failed} of {calls} calls failed in 15 min':
      '15 分钟内 {calls} 次调用中失败 {failed} 次',
  '{failed} of {attempts} pushes failed in an hour':
      '一小时内 {attempts} 条推送中失败 {failed} 条',
  '{count} reports in the last hour': '最近一小时 {count} 条报告',
  '{circles} circles and {people} people at their limit':
      '{circles} 个圈子和 {people} 个人用完了额度',
  'No version has enough people yet': '还没有版本达到足够的人数',
  '{version}: {crashed} of {active} people crashed':
      '{version}：{active} 人中有 {crashed} 人遇到崩溃',
  '{count} new groups': '{count} 个新分组',

  // Alerts: the list.
  'Alerts|Open': '未处理',
  'Alerts|Closed': '已关闭',
  'Could not load the alerts.': '无法加载告警。',
  'No open alerts.': '没有未处理的告警。',
  'No closed alerts yet.': '还没有已关闭的告警。',
  'Anything that goes wrong shows up here.': '出了问题会显示在这里。',
  'Since {time}': '自 {time}',
  '{time} · {how}': '{time} · {how}',
  'closed by @{name}': '由 @{name} 关闭',
  'recovered': '已恢复',
  'New error': '新错误',
  'Seen by @{name}': '@{name} 已知晓',
  'Reopened {count} times': '已复发 {count} 次',
  'I have seen it': '我知道了',

  // Alerts: the error groups.
  'Errors in the last day': '最近一天的错误',
  'Could not load the errors.': '无法加载错误。',
  'No error reports in the last day.': '最近一天没有错误报告。',
  'Errors|New': '新出现',
  '{count} times': '{count} 次',
  'first in {version}': '最早出现在 {version}',
  'Grouped by kind, type and the first line of WeCord’s own code in the stack. To read a stack, use tool/errors_report.sh.':
      '按报告类型、错误类型和调用栈里第一行 WeCord 自己的代码分组。要查看调用栈，请用 tool/errors_report.sh。',
  'The checks run every 5 minutes inside WeCord’s own database. Nothing is sent to a third-party service.':
      '检查每 5 分钟在 WeCord 自己的数据库里运行一次，不会把任何内容发给第三方服务。',

  // The audit log and the cards in Notifications.
  '{actor} acknowledged the alert “{title}”': '{actor} 确认已知晓告警“{title}”',
  '{actor} closed the alert “{title}”': '{actor} 关闭了告警“{title}”',
  'Monitoring': '监控',
  'Alert': '告警',
};
