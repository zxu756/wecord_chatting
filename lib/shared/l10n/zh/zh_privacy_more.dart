// Chinese for disappearing messages, view-once media, devices, polls,
// double-tap reactions and profile visibility. Text shared with other
// areas (Off, 7 days, Cancel, ...) is translated there.
const zhPrivacyMore = <String, String>{
  // Disappearing messages.
  'Disappearing messages': '限时消息',
  'Opens disappearing messages': '打开限时消息设置',
  'Messages disappear after {time}': '消息将在{time}后消失',
  '24 hours': '24 小时',
  '90 days': '90 天',
  '24h': '24 小时',
  '7d': '7 天',
  '90d': '90 天',
  'Disappearing now': '即将消失',
  'Disappears in {count}m': '{count} 分钟后消失',
  'Disappears in {count}h': '{count} 小时后消失',
  'Disappears in {count}d': '{count} 天后消失',
  '{count}d': '{count}天',
  '{name} turned off disappearing messages.': '{name}关闭了限时消息。',
  '{name} set messages to disappear after {time}.': '{name}设置消息在{time}后消失。',
  'New messages in this group will be deleted for everyone after this time. Earlier messages stay.':
      '本群之后的新消息会在此时间后对所有人删除，之前的消息不受影响。',
  'New messages in this chat will be deleted for both of you after this time. Earlier messages stay.':
      '本聊天之后的新消息会在此时间后对你们双方删除，之前的消息不受影响。',
  'Only the owner and admins can change this.': '只有群主和管理员可以更改。',
  'Anyone in the chat can still copy or screenshot a message before it goes.':
      '消息消失前，聊天中的任何人仍可复制或截图。',
  'Could not save. Try again.': '无法保存，请重试。',

  // View-once photos and videos.
  'View once': '阅后即焚',
  'No caption on view-once media': '阅后即焚的内容不能加说明',
  'Each person can open it one time. Screenshots and screen recordings can\'t be blocked.':
      '每个人只能打开一次。截屏和录屏无法被阻止。',
  'Let people open each photo or video one time.': '让对方每张照片或视频只能打开一次。',
  'Open this photo once?': '要打开这张照片吗？只能看一次',
  'Open this video once?': '要打开这个视频吗？只能看一次',
  'Once you close it, it is gone and you can\'t open it again. WeCord can\'t stop screenshots or screen recordings, so the sender is trusting you with it.':
      '关闭后它就消失了，无法再次打开。WeCord 无法阻止截屏或录屏，发送者是信任你才发给你的。',
  'You already opened this one.': '你已经打开过这一个了。',
  'This can\'t be opened any more.': '这个已无法再打开。',
  'Could not open it. Try again.': '无法打开，请重试。',
  'Photo': '照片',
  'Not opened': '未打开',
  'Opened': '已打开',
  'Opened by {count}': '{count} 人已打开',
  'Tap to open · View once': '点按打开 · 仅限一次',
  '{kind}, view once, {status}': '{kind}，阅后即焚，{status}',
  'Could not play this video.': '无法播放这个视频。',
  'View-once photo': '阅后即焚照片',
  'View-once video': '阅后即焚视频',
  'Could not load this photo.': '无法加载这张照片。',
  'View once · gone when you close it': '阅后即焚 · 关闭后消失',
  'Screenshots and screen recordings can\'t be blocked.': '截屏和录屏无法被阻止。',

  // Devices.
  'Devices': '设备',
  'See where you are signed in and sign devices out': '查看你在哪些设备上登录，并退出设备',
  'Active just now': '刚刚活跃',
  'Active {count} minutes ago': '{count} 分钟前活跃',
  'Active 1 hour ago': '1 小时前活跃',
  'Active {count} hours ago': '{count} 小时前活跃',
  'Active 1 day ago': '1 天前活跃',
  'Active {count} days ago': '{count} 天前活跃',
  'Active now': '当前活跃',
  'Sign out {device}?': '要退出{device}吗？',
  'It will be signed out the next time it connects to WeCord.':
      '它下次连接 WeCord 时会被退出登录。',
  'Could not sign that device out.': '无法退出该设备。',
  'Sign out of all other devices?': '退出所有其他设备？',
  'Every device except this one will need to sign in again.':
      '除本设备外，所有设备都需要重新登录。',
  'Could not sign the other devices out.': '无法退出其他设备。',
  'Unknown device': '未知设备',
  'Could not load your devices.': '无法加载你的设备。',
  'This device': '本设备',
  'Other devices': '其他设备',
  'Signed out devices need your password (and a code, if you use two-step verification) to come back.':
      '被退出的设备需要你的密码（若启用两步验证，还需验证码）才能重新登录。',
  'No other devices are signed in.': '没有其他已登录的设备。',
  'Sign out of all other devices': '退出所有其他设备',
  'WeCord {version}': 'WeCord {version}',

  // Polls: quizzes, anonymous votes, deadlines, added answers.
  'Quiz': '测验',
  'Answer recorded': '已记录你的答案',
  'Pick the right answer': '选出正确答案',
  'Right answer': '正确答案',
  'Your answer, not right': '你的答案，不正确',
  'Anonymous': '匿名',
  'Add an answer': '添加选项',
  'Answer': '选项',
  'Add': '添加',
  'Could not add that answer. Try again.': '无法添加该选项，请重试。',
  'Mark the right answer.': '请标出正确答案。',
  'Pick a closing time in the future.': '请选择一个未来的截止时间。',
  'Mark answer {number} as right': '将选项 {number} 标为正确答案',
  'One right answer, shown with an explanation after people vote':
      '只有一个正确答案，大家投票后会连同解析一起显示',
  'Explanation (optional)': '解析（可选）',
  'Anonymous votes': '匿名投票',
  'Everyone sees the totals, nobody sees who voted': '大家都能看到总数，但看不到谁投了票',
  'Members can add answers': '成员可以添加选项',
  'Pick a day and time…': '选择日期和时间…',
  'Closes {time}': '{time}截止',
  'Fewer options': '收起选项',

  // Double-tap reaction and Settings → Chat.
  'Chat': '聊天',
  'Quick reaction': '快捷表情',
  'Added when you double-tap a message': '双击消息时添加',
  'Double-tap a message (double-click on a computer) to react with it.':
      '双击消息（电脑上为双击鼠标）即可用它回应。',
  'Back to {emoji}': '恢复为 {emoji}',
};
