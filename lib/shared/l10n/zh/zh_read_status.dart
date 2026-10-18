// Chinese for the group read list (已读名单), the read receipts switch and
// "remind unread" (提醒未读的人). 'Read' (已读), 'Unread' (未读), 'Unknown'
// (未知), 'Retry', 'Message', 'Jump', 'Dismiss' and 'Could not save privacy
// settings. Try again.' are already translated elsewhere.
const zhReadStatus = <String, String>{
  // Under the newest message of a group, and the message menu.
  '{count} read': '{count} 人已读',
  'Shows who has read it': '查看谁已读',
  'Message info': '消息信息',
  // The sheet.
  'Nobody else is in this group yet.': '群里还没有其他人。',
  'Nobody has read this yet.': '还没有人读过。',
  'Everyone has read this.': '所有人都已读。',
  'They turned off read receipts.': '他们关闭了已读回执。',
  'Remind unread': '提醒未读的人',
  'Reminder sent': '已发出提醒',
  'You can remind once for each message.': '每条消息只能提醒一次。',
  'Sends a reminder to the people who have not read this. You can do it once for each message.':
      '给还没读的人发一条提醒。每条消息只能提醒一次。',
  'You already reminded about this message.': '你已经提醒过这条消息了。',
  'Nobody needs a reminder.': '没有需要提醒的人。',
  'You have sent many reminders today. Try again tomorrow.':
      '你今天发出的提醒太多了，明天再试。',
  'Turn on read receipts in Settings to use this.': '请先在设置里打开已读回执。',
  'Could not send the reminder. Try again.': '无法发出提醒，请重试。',
  'Read receipts are off. Turn them on in Settings → Privacy & Safety to see who has read your messages.':
      '已读回执已关闭。请在 设置 → 隐私与安全 里打开，才能看到谁读了你的消息。',
  'There is no read list for this message.': '这条消息没有已读名单。',
  'Could not load who has read this.': '无法加载已读名单。',
  // Settings → Privacy & Safety.
  'Send read receipts': '发送已读回执',
  'When off, others see you as unknown in read lists, and you do not see their read receipts either.':
      '关闭后，别人在已读名单里看到你是“未知”，你也看不到别人的已读回执。',
  // The card in Notifications.
  'asked you to read this': '提醒你查看这条消息',
};
