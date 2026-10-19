// Chinese for urgent messages (加急消息), group announcements that ask for a
// confirmation (需要确认的群公告) and repeating scheduled messages (重复的定时
// 消息). 'Repeat' (重复), 'Every day' (每天), 'Done', 'Jump', 'Confirm'-style
// words already translated elsewhere are not repeated here.
const zhUrgentRecurring = <String, String>{
  // The message menu and the "Urgent" sheet.
  'Urgent': '加急',
  'Urgent message': '加急消息',
  'Make urgent': '加急',
  'Make urgent for {count}': '加急给 {count} 人',
  'Choose who must see this': '选择必须看到的人',
  'Already urgent': '已加急',
  'Confirmed': '已确认',
  'Waiting': '未确认',
  'There is nobody else to notify.': '没有其他人可以通知。',
  'Could not load the members.': '无法加载成员。',
  'Made urgent for 1 person': '已加急给 1 人',
  'Made urgent for {count} people': '已加急给 {count} 人',
  'They get a notification that gets through quiet hours and mutes, and a red banner until they confirm. If they do not confirm within 10 minutes, they are notified once more.':
      '他们会收到一条不受免打扰和静音限制的通知，并在聊天顶部看到红色横幅，直到确认。10 分钟内没确认，会再通知一次。',
  '{remaining} of {allowed} left in 24 hours': '24 小时内还剩 {remaining}/{allowed} 次',
  'You used all {allowed} urgent messages of the last 24 hours.':
      '最近 24 小时的 {allowed} 次加急已用完。',
  'You can make 5 messages urgent in 24 hours. Try again later.':
      '24 小时内最多加急 5 条消息，请稍后再试。',
  'Nobody to notify. They may have been notified already, or turned off urgent messages from you.':
      '没有可通知的人。他们可能已被通知过，或关闭了你的加急。',
  'Pick up to {count} people.': '最多选择 {count} 人。',
  'This message can not be made urgent.': '这条消息不能加急。',
  // The red banner and the Notifications cards.
  '{name} marked a message urgent': '{name} 加急了一条消息',
  '{name} marked a message urgent · {count} more':
      '{name} 加急了一条消息 · 还有 {count} 条',
  'Someone': '某人',
  'Got it': '知道了',
  'Turn off for {name}': '不再接收 {name} 的加急',
  'Urgent messages from {name} are off. You can turn them back on in Settings.':
      '已关闭 {name} 的加急消息。可以在 设置 里重新打开。',
  'To confirm': '待确认',
  'Urgent messages and announcements that ask you to confirm show up here.':
      '需要你确认的加急消息和群公告会显示在这里。',
  '{group} needs you to confirm its announcement': '{group} 的群公告需要你确认',
  'Open group': '打开群聊',
  'Group': '群聊',
  // Settings -> Notifications -> Urgent messages.
  'Urgent messages': '加急消息',
  '{count} turned off': '已关闭 {count} 人',
  'A friend or group member can mark their message urgent for you. You get a notification even in quiet hours or when the chat is muted, and a red banner in the chat until you tap Got it. At most 5 a day from each person. Blocked people can not do it.':
      '好友或群成员可以把他们的消息加急给你。即使在免打扰时段或聊天已静音，你也会收到通知，并在聊天里看到红色横幅，直到你点“知道了”。每人每天最多 5 次，被拉黑的人无法加急。',
  'Turned off': '已关闭',
  'You have not turned off anyone.': '你没有关闭任何人。',
  'Could not load the list.': '无法加载列表。',
  'Allow': '允许',
  // Announcements that ask for a confirmation.
  'Ask members to confirm': '需要成员确认',
  'Members tap Confirm; you see who has. Changing the announcement asks again.':
      '成员点“确认”，你能看到谁确认了。修改公告后需要重新确认。',
  'Confirmed {acked}/{total}': '已确认 {acked}/{total}',
  'You confirmed': '你已确认',
  'Confirm': '确认',
  'Who confirmed': '谁确认了',
  'Confirmations': '确认情况',
  'Could not load the confirmations.': '无法加载确认情况。',
  'Nobody has confirmed yet.': '还没有人确认。',
  'Everyone has confirmed.': '所有人都已确认。',
  'Remind the ones who have not': '提醒未确认的人',
  'Reminder sent': '已发出提醒',
  'You can remind again {time}.': '{time} 后可以再次提醒。',
  'Sends a notification to the members who have not confirmed. You can remind once every 6 hours.':
      '给还没确认的成员发一条通知。每 6 小时只能提醒一次。',
  'Reminded 1 person': '已提醒 1 人',
  'Reminded {count} people': '已提醒 {count} 人',
  'Write an announcement before asking for confirmations.':
      '请先写好公告，再要求成员确认。',
  'You reminded the group a short while ago. Try again later.':
      '你刚提醒过，请稍后再试。',
  'You can not do this in this group.': '你不能在这个群里这样做。',
  // Repeating scheduled messages.
  'Does not repeat': '不重复',
  'Weekdays': '工作日',
  'Every week': '每周',
  'Every month': '每月',
  'On the weekday of the first send': '按第一次发送的星期几',
  'On the day of the month of the first send': '按第一次发送的几号',
  'In a month without that day it goes out on the last day of the month.':
      '没有这一天的月份，会在该月最后一天发送。',
  'Does not end': '不结束',
  'Never stop repeating': '一直重复',
  'Every day {time}': '每天 {time}',
  'Weekdays {time}': '工作日 {time}',
  'Every month on day {day} {time}': '每月{day}号 {time}',
  'until {date}': '截止 {date}',
  'Every Monday': '每周一',
  'Every Tuesday': '每周二',
  'Every Wednesday': '每周三',
  'Every Thursday': '每周四',
  'Every Friday': '每周五',
  'Every Saturday': '每周六',
  'Every Sunday': '每周日',
  'Scheduled: {rule}. Next: {time}': '已安排：{rule}。下一次：{time}',
  'Stop repeating': '停止重复',
};
