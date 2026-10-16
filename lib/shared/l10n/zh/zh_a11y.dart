// Chinese for the accessibility pass: what screen readers say (labels for
// badges, messages, presence, the message list and its keyboard shortcuts).
const zhA11y = <String, String>{
  // Badges and counts.
  'Unread': '未读',
  '{count} unread': '{count} 条未读',
  '{count} new': '{count} 条新消息',

  // Controls.
  'React with {emoji}': '用 {emoji} 回应',
  'Remove {emoji} reaction': '取消 {emoji} 回应',
  'Play animation': '播放动画',
  'Shows the topic': '显示频道主题',
  'More options': '更多选项',
  'Opens the menu': '打开菜单',
  'Long press for more options': '长按显示更多选项',
  'Menu': '菜单',
  'Message actions': '消息操作',
  'New messages': '新消息',

  // Messages, read as one sentence.
  'Image from {name}': '来自 {name} 的图片',
  'Image: {name}': '图片：{name}',
  'File: {name}': '文件：{name}',
  '{count} attachments': '{count} 个附件',
  'Reply to {name}': '回复 {name}',
  'Sending': '发送中',
  '1 reaction': '1 个回应',
  '{count} reactions': '{count} 个回应',
  '1 reply in thread': '子区有 1 条回复',
  '{count} replies in thread': '子区有 {count} 条回复',

  // How long ago, spoken.
  'Just now': '刚刚',
  '1 minute ago': '1 分钟前',
  '{count} minutes ago': '{count} 分钟前',
  '1 hour ago': '1 小时前',
  '{count} hours ago': '{count} 小时前',
  '1 day ago': '1 天前',
  '{count} days ago': '{count} 天前',

  // Keyboard shortcuts.
  'Jump to the message box': '跳到消息输入框',
  'Open the menu of the message in focus': '打开当前消息的菜单',
};
