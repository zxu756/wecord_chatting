// Simplified Chinese for the profile extras (lib/features/profile/):
// status bubbles and who sees a status, birthdays, mutual friends and groups,
// where a friendship started, and support links.
const zhProfileExtras = <String, String>{
  // Where a friendship started
  'Found by username': '通过用户名搜索',
  'Scanned a QR code': '扫了二维码',
  'From a group chat': '来自群聊',
  'From a contact card': '来自名片',
  'From a circle': '来自圈子',
  'Source': '来源',
  // Mutuals
  'In common': '共同点',
  'Group chat': '群聊',
  '1 mutual group': '1 个共同群聊',
  '{count} mutual groups': '{count} 个共同群聊',
  // Status bubbles
  "Reply to {name}'s status": '回复 {name} 的状态',
  '{name}: {status}. Reply to the status.': '{name}：{status}。回复这条状态。',
  'Replying to your status: "{status}"': '回复了你的状态：“{status}”',
  // Birthday
  'Birthday': '生日',
  'birthday|Month': '月',
  'Day': '日',
  'Choose a month and a day.': '请选择月份和日期。',
  'Could not save your birthday. Try again.': '无法保存生日，请重试。',
  'Only the month and the day are saved, never the year. Your friends are reminded on the day.':
      '只保存月和日，不保存年份。生日当天会提醒你的好友。',
  'Remove birthday': '移除生日',
  "Remind me of friends' birthdays": '提醒我好友的生日',
  'has a birthday today': '今天生日',
  'Send wishes': '送上祝福',
  'Happy birthday! 🎂': '生日快乐！🎂',
  // Support links
  'Support links': '支持链接',
  'support-links|Support': '支持',
  'Leaving WeCord': '即将离开 WeCord',
  'You are about to open {host}, a site outside WeCord. WeCord does not handle payments and is not responsible for what is on that page.':
      '你将打开 {host}，这是 WeCord 之外的网站。WeCord 不处理付款，也不对该页面上的内容负责。',
  '{name}, opens a page outside WeCord': '{name}，会打开 WeCord 之外的页面',
  'Only links to support pages such as {names} can be added.':
      '只能添加 {names} 等支持页面的链接。',
  'Add up to {max} links to pages where people can support you: {names}. WeCord does not handle the payment.':
      '最多可以添加 {max} 个链接，指向大家可以支持你的页面：{names}。WeCord 不处理付款。',
  "This isn't a supported support page.": '这不是受支持的赞助页面。',
  'Label (optional)': '标签（可选）',
  'Could not save your links. Try again.': '无法保存链接，请重试。',
  'Support page': '支持页面',
  'Members see a Support entry in the circle menu. WeCord does not handle the payment.':
      '成员会在圈子菜单里看到“支持这个圈子”。WeCord 不处理付款。',
  'Link saved.': '链接已保存。',
  'Link removed.': '链接已移除。',
  'Could not save the link. Try again.': '无法保存链接，请重试。',
  'Support this circle': '支持这个圈子',
};
