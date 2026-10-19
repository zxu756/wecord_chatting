// Chinese for the daily digest (每日速览): the card in Notifications and
// Settings -> AI -> Daily digest. 'Chat', 'Time', 'Off', '1 message' and
// '{count} messages' are already translated elsewhere.
const zhDigest = <String, String>{
  // The card and the Notifications chip.
  'Daily digest': '每日速览',
  'Digest': '速览',
  '1 chat had news': '1 个聊天有新动态',
  '{count} chats had news': '{count} 个聊天有新动态',
  'Show all {count} chats': '显示全部 {count} 个聊天',
  'Show less': '收起',
  'Mark as read': '标为已读',
  'Your daily digest shows up here. Set it up in Settings, under AI.':
      '你的每日速览会显示在这里。请在“设置”的 AI 里开启。',
  // Settings.
  'A short summary of the chats you follow, once a day, only when there is news.':
      '每天一次，简要总结你关注的聊天里发生了什么；没有新动态就不发。',
  'Send me a daily digest': '每天给我发速览',
  'It appears in Notifications and you get a push when it is ready.':
      '生成后会出现在通知页，并推送提醒你。',
  'WeCord AI reads only the messages you can see in the chats you follow, and only when something new was said. Recalled, disappearing and view-once messages and messages from people you blocked are never sent. Each digest counts as one AI request.':
      'WeCord AI 只读取你在所关注聊天里能看到的消息，而且只在有新消息时才读取。已撤回、限时消息、阅后即焚的消息，以及你拉黑的人发的消息，都不会发送。每份速览算 1 次 AI 请求。',
  'AI features are off in Settings, so no digest is made until you turn them on.':
      '你在设置里关闭了 AI 功能，打开之前不会生成速览。',
  'Delivery': '送达',
  'Deliver the digest at': '速览送达时间',
  'Time zone': '时区',
  'The digest uses the time zone your devices report, so it follows you when you travel.':
      '速览按你设备上报的时区计时，出差旅行时会跟着你走。',
  'Chats you follow ({count} of {max})': '关注的聊天（{count}/{max}）',
  'Groups and circle channels you are in. Private chats are not included.':
      '你所在的群聊和圈子频道，不包括私聊。',
  'You follow {max} chats, the most you can. Unfollow one to follow another.':
      '你已关注 {max} 个聊天，这是上限。取消一个才能关注新的。',
  'You can follow at most {max} chats. Unfollow one first.':
      '最多关注 {max} 个聊天，请先取消一个。',
  'No groups or channels yet': '还没有群聊或频道',
  'Could not load. Try again.': '无法加载，请重试。',
};
