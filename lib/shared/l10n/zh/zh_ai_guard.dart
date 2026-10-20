// Chinese for the AI guard for new members: its setting, the author's
// "Checking…" / "Held for review" line, the moderators' Review queue and
// its audit log entries.
const zhAiGuard = <String, String>{
  // The setting.
  'AI guard': 'AI 守护',
  'AI guard for new members': '新成员 AI 守护',
  'Check new members\' first messages': '检查新成员发出的头几条消息',
  'Could not load the AI guard.': '无法加载 AI 守护。',
  "Couldn't save the AI guard. Try again.": '无法保存 AI 守护设置，请重试。',
  'Checks the first messages of new members with AI before everyone else sees them. Messages the AI finds fine appear within moments.':
      '在其他人看到之前，用 AI 检查新成员发出的头几条消息。AI 认为没问题的消息会很快显示出来。',
  'AI features are turned off in this circle, so the guard does nothing. Turn on "Allow AI features in this circle" in Circle settings to use it.':
      '这个圈子已关闭 AI 功能，所以守护不会起作用。请在圈子设置中打开“允许在此圈子使用 AI 功能”。',
  'Only the text of messages from new members is sent to the AI provider, and only while this is on. Files are not sent. If the AI is unavailable, messages are shown as usual and marked as not checked.':
      '只有新成员所发消息的文字会发送给 AI 服务商，并且仅在开启时发送。文件不会发送。如果 AI 不可用，消息会照常显示，并标记为未检查。',
  'On, but AI is off in this circle': '已开启，但此圈子关闭了 AI',
  'Who counts as new': '谁算新成员',
  'Recently joined': '刚加入的',
  'Few messages': '消息很少的',
  'Joined less than': '加入时间少于',
  'Fewer than': '消息少于',
  'Members who joined less than a day ago. Moderators and managers are never checked.':
      '加入不满一天的成员。版主和管理者不会被检查。',
  'Members who joined less than {count} days ago. Moderators and managers are never checked.':
      '加入不满 {count} 天的成员。版主和管理者不会被检查。',
  'Members who have sent fewer than {count} messages in this circle. Moderators and managers are never checked.':
      '在此圈子发送的消息少于 {count} 条的成员。版主和管理者不会被检查。',
  'When the AI flags a message': 'AI 标记了消息时',
  'Hold for review': '扣留待审',
  'Hidden from everyone but the author until a moderator approves or removes it.':
      '除作者外对所有人隐藏，直到版主批准或移除。',
  'Flag only': '仅标记',
  'Shown to everyone as usual, and listed for moderators to look at.':
      '照常显示给所有人，并列出来供版主查看。',
  'Moderation': '管理',
  'Nothing is waiting': '没有待处理的',
  '{count} waiting': '{count} 条待处理',
  'Circle menu, {count} waiting for review': '圈子菜单，{count} 条待审核',

  // Under a message.
  'Held for review': '待审核',
  'Removed': '已移除',
  'Removed by a moderator': '已被版主移除',
  'Only you and moderators can see this until it is checked.':
      '检查完成之前，只有你和版主能看到。',
  'Only you and moderators can see this until a moderator approves.':
      '版主批准之前，只有你和版主能看到。',
  'Only moderators and its author can see this.': '只有版主和作者能看到。',
  'Only you and moderators can see this.': '只有你和版主能看到。',

  // The Review queue.
  'Review': '审核',
  'Could not load the review queue.': '无法加载审核队列。',
  'Nothing to review': '没有需要审核的内容',
  'Messages the AI guard holds back or flags show up here.':
      'AI 守护扣留或标记的消息会显示在这里。',
  'Held messages are hidden from everyone but their author until you approve them. Flagged messages are already visible.':
      '被扣留的消息除作者外对所有人隐藏，直到你批准。被标记的消息已经对所有人可见。',
  'Held': '已扣留',
  'Flagged': '已标记',
  'Approve': '批准',
  'Remove this message?': '移除这条消息？',
  'It is deleted and nobody else will ever see it.': '它会被删除，其他人永远不会看到。',
  'It is deleted for everyone.': '它会对所有人删除。',
  'Message approved.': '已批准这条消息。',
  'Message removed.': '已移除这条消息。',
  "Couldn't update this message. It may already be reviewed.":
      '无法更新这条消息，可能已经被审核过了。',
  'Scam or phishing': '诈骗或钓鱼',
  'Sexual content': '色情内容',

  // The audit log.
  '{actor} updated the AI guard': '{actor} 更新了 AI 守护',
  'AI guard held a message by {target}': 'AI 守护扣留了 {target} 的一条消息',
  'AI guard held a message by {target} in {channel}':
      'AI 守护扣留了 {target} 在 {channel} 的一条消息',
  'AI guard flagged a message by {target}': 'AI 守护标记了 {target} 的一条消息',
  'AI guard flagged a message by {target} in {channel}':
      'AI 守护标记了 {target} 在 {channel} 的一条消息',
  '{actor} approved a message by {target} from the review queue':
      '{actor} 在审核队列中批准了 {target} 的一条消息',
  '{actor} removed a message by {target} from the review queue':
      '{actor} 在审核队列中移除了 {target} 的一条消息',
  'AI found': 'AI 判断',
  'Joined less than (days)': '加入少于（天）',
  'Fewer than (messages)': '消息少于（条）',
  'When flagged': '标记时',
};
