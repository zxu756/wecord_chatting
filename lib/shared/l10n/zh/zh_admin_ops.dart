// Simplified Chinese for feature flags and the minimum version (K4), official
// notices (K6) and Feedback and help (K7): the "Please update" page, the
// Official card and filter in Notifications, the admin console's new tabs, the
// feedback page, and the messages the new database functions raise.
const zhAdminOps = <String, String>{
  // ---- Context words.
  'Feedback|Closed': '已关闭',

  // ---- The "Please update" page.
  'Please update WeCord': '请更新 WeCord',
  'A newer version is ready. Refresh to get it and carry on.':
      '有新版本了。刷新即可获取，然后继续使用。',
  'This version is too old to keep working. Update WeCord where you installed it, then open it again.':
      '这个版本太旧，无法继续使用。请在你安装 WeCord 的地方更新，然后重新打开。',
  'You have {version}. You need {minimum} or newer.':
      '你的版本是 {version}，需要 {minimum} 或更新的版本。',
  'Check again': '再检查一次',
  'Checking...': '正在检查…',

  // ---- Notifications: the Official card and filter.
  'Official': '官方',
  'WeCord team': 'WeCord 团队',
  'Notices from the WeCord team, and its answers to your feedback, show up here.':
      'WeCord 团队的通知，以及对你反馈的回复，会出现在这里。',

  // ---- The admin console's tabs.
  'Reports, flags, notices and feedback': '举报、功能开关、通知和反馈',
  'Flags': '开关',
  'Notices': '通知',
  'Feedback': '反馈',
  'Web': '网页',
  'All platforms': '所有平台',

  // ---- Flags and the minimum version.
  'Minimum version': '最低版本',
  'Apps older than this show a “Please update” page. Only an owner can change it.':
      '低于这个版本的应用会显示“请更新”页面。只有所有者能修改。',
  'No minimum': '没有最低版本',
  'Minimum version: {platform}': '最低版本：{platform}',
  'Leave it empty for no minimum.': '留空表示没有最低版本。',
  'Version': '版本',
  'The version looks like 1.2.3.': '版本号的格式如 1.2.3。',
  'Lock out older versions?': '让旧版本无法使用？',
  'People on a version older than {version} ({platform}) will only see the “Please update” page.':
      '版本低于 {version}（{platform}）的用户只会看到“请更新”页面。',
  'Set minimum': '设置最低版本',
  'Feature flags': '功能开关',
  'A flag decides what the app shows, never what is allowed.':
      '开关只决定应用显示什么，从不决定允许什么。',
  'New flag': '新建开关',
  'Change flag': '修改开关',
  'No flags yet.': '还没有开关。',
  'Could not load the flags.': '无法加载开关。',
  '{percent}% of people': '{percent}% 的用户',
  'Allow list: {count}': '白名单：{count} 人',
  'Needs {version}': '需要 {version}',
  'Key': '标识',
  'Lower-case letters, digits and underscores.': '小写字母、数字和下划线。',
  'What it does': '用途',
  'Share of people (0 to 100)': '开启比例（0 到 100）',
  'The same people stay in as it goes up. 100 is everybody.':
      '比例调高时，已开启的人保持开启。100 表示所有人。',
  'A number from 0 to 100.': '0 到 100 之间的数字。',
  'Always on for (usernames)': '始终开启的用户（用户名）',
  'Separated by spaces or commas.': '用空格或逗号分隔。',
  'Needs version (optional)': '需要的版本（选填）',
  'Delete this flag?': '删除这个开关？',
  'The app goes back to the default for “{key}” everywhere.':
      '所有地方的“{key}”都会恢复为默认值。',
  'Delete flag': '删除开关',

  // ---- Notices.
  'New notice': '新建通知',
  'No notices yet.': '还没有通知。',
  'A notice shows in every person’s Notifications.': '通知会出现在每个人的通知页里。',
  'Could not load the notices.': '无法加载通知。',
  'Load more': '加载更多',
  'Taken back': '已撤回',
  'Take back': '撤回',
  'Push sent': '已推送',
  'Push waiting': '等待推送',
  '{time} · read by {read} · dismissed by {dismissed}':
      '{time} · {read} 人已读 · {dismissed} 人已关闭',
  'Write it in both languages if you can. Each person sees the one in their app language.':
      '尽量写中英文两版。每个人看到的是和自己应用语言一致的那一版。',
  'Title (English)': '标题（英文）',
  'Text (English)': '正文（英文）',
  'Title (Chinese)': '标题（中文）',
  'Text (Chinese)': '正文（中文）',
  'Also send one push': '同时推送一次',
  'Once, and not more than one push a day.': '只推送一次，且一天最多一次推送。',
  'Publish to everybody?': '发布给所有人？',
  'Every person will see this in Notifications.': '每个人都会在通知页看到这条通知。',
  'Every person will see this in Notifications, and devices with push get one notification. You cannot send another push for a day.':
      '每个人都会在通知页看到这条通知，开启推送的设备会收到一次推送。一天之内不能再发推送。',
  'Take this notice back?': '撤回这条通知？',
  'It disappears from every Notifications page. A push that has not gone out yet is cancelled.':
      '它会从所有人的通知页消失。还没发出的推送会被取消。',

  // ---- Feedback in the console.
  'No open feedback.': '没有待处理的反馈。',
  'No feedback here.': '这里没有反馈。',
  'What people send from Settings shows up here.': '用户在设置里发来的反馈会出现在这里。',
  'Could not load the feedback.': '无法加载反馈。',
  'Could not load this feedback.': '无法加载这条反馈。',
  'Screenshot': '截图',
  'Answered': '已回复',
  'Could not load the screenshot.': '无法加载截图。',
  'Screenshot sent with the feedback': '随反馈发来的截图',
  'Only this person sees it, as a notice from the WeCord team.':
      '只有这位用户能看到，以 WeCord 团队通知的形式送达。',
  'Write a reply': '写回复',
  'Close after replying': '回复后关闭',
  'Send reply': '发送回复',
  'Reply sent.': '已发送回复。',
  'Open again': '重新打开',
  'Close without replying': '不回复直接关闭',

  // ---- The audit log.
  '{actor} created the flag {title}': '{actor} 创建了开关 {title}',
  '{actor} changed the flag {title}': '{actor} 修改了开关 {title}',
  '{actor} deleted the flag {title}': '{actor} 删除了开关 {title}',
  '{actor} removed the minimum version for {title}':
      '{actor} 取消了 {title} 的最低版本',
  '{actor} set the minimum version for {title} to {version}':
      '{actor} 把 {title} 的最低版本设为 {version}',
  '{actor} published the notice “{title}”': '{actor} 发布了通知“{title}”',
  '{actor} took back the notice “{title}”': '{actor} 撤回了通知“{title}”',
  '{actor} replied to the feedback of {title}': '{actor} 回复了 {title} 的反馈',
  '{actor} closed the feedback of {title}': '{actor} 关闭了 {title} 的反馈',
  '{actor} opened the feedback of {title} again': '{actor} 重新打开了 {title} 的反馈',

  // ---- Settings, Feedback and help.
  'Feedback and help': '反馈与帮助',
  'Tell us what went wrong or what you would like': '告诉我们哪里出了问题，或你想要什么',
  'Tell us what went wrong, or what you would like. We read everything.':
      '告诉我们哪里出了问题，或你想要什么。我们会认真阅读每一条。',
  'What happened?': '发生了什么？',
  'Add a screenshot': '添加截图',
  'Opening...': '正在打开…',
  'Your screenshot': '你的截图',
  'Cover anything private before you send it.': '发送前请遮住涉及隐私的内容。',
  'Hide private parts': '遮住隐私内容',
  'That picture could not be read. Try another.': '无法读取这张图片，换一张试试。',
  'We add your WeCord version ({version}) and your platform ({platform}). Nothing from your chats is sent.':
      '我们会附上你的 WeCord 版本（{version}）和平台（{platform}），不会发送任何聊天内容。',
  'Send feedback': '发送反馈',
  'Sending...': '正在发送…',
  'Thank you, we got it.': '谢谢，我们收到了。',
  'If we reply, the answer shows up in Notifications.': '如果我们回复了，回复会出现在通知里。',

  // ---- Messages the database functions raise.
  'A push was already sent in the last 24 hours': '过去 24 小时内已经发过一次推送',
  'A notice needs a title': '通知需要有标题',
  'That notice is too long': '这条通知太长了',
  'Notice not found or already taken back': '找不到这条通知，或它已被撤回',
  'A flag key is lower-case letters, digits and underscores':
      '开关标识只能用小写字母、数字和下划线',
  'The roll-out is a percentage from 0 to 100': '开启比例是 0 到 100 的百分数',
  'The version looks like 1.2.3': '版本号的格式如 1.2.3',
  'The description is at most 200 characters': '说明最多 200 个字',
  'Some of those usernames do not exist': '其中有些用户名不存在',
  'At most 200 people on the allow list': '白名单最多 200 人',
  'Flag not found': '找不到这个开关',
  'Unknown platform': '未知的平台',
  'Unknown status': '未知的状态',
  'Feedback not found': '找不到这条反馈',
  'Write a reply first': '请先写回复',
  'That reply is too long': '这条回复太长了',
  'Write a few words first': '请先写几句话',
  'That message is too long': '这条反馈太长了',
  'That screenshot is not there': '找不到这张截图',
  'Too many feedback messages. Try again later.': '反馈发得太频繁了，请稍后再试。',
};
