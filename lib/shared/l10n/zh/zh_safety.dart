// Chinese for moderation and safety: AutoMod, member onboarding and
// two-step verification.
const zhSafety = <String, String>{
  // Permission.
  'Manage circle': '管理圈子',
  'Set up AutoMod and member onboarding.': '设置自动审核和新成员引导。',

  // AutoMod settings.
  'AutoMod': '自动审核',
  'Could not load AutoMod rules.': '无法加载自动审核规则。',
  "AutoMod checks messages as they are sent in this circle's channels. Members who can manage the circle are never checked.":
      '自动审核会在消息发送到本圈子的频道时进行检查。可以管理圈子的成员不受检查。',
  'Custom keywords': '自定义关键词',
  'Mention spam': '提及刷屏',
  'Block words, phrases and patterns you choose.': '拦截你指定的词语、短语和模式。',
  'Block messages that mention too many people or roles at once.':
      '拦截一次提及过多成员或角色的消息。',
  'Block members who send too many messages too quickly.': '拦截短时间内发送过多消息的成员。',
  '{count} keywords': '{count} 个关键词',
  '{count} patterns': '{count} 个模式',
  'More than {count} mentions': '超过 {count} 次提及',
  'More than {count} messages in {seconds}s': '{seconds} 秒内超过 {count} 条消息',
  'Block message': '拦截消息',
  'Send alert': '发送提醒',
  'Time out member': '禁言成员',
  'Create rule': '创建规则',
  'Edit rule': '编辑规则',
  'Delete rule': '删除规则',
  'Delete {name}? AutoMod stops checking for it.': '删除 {name}？自动审核将不再检查这条规则。',
  'Could not save the rule. Try again.': '无法保存规则，请重试。',
  'Could not delete the rule. Try again.': '无法删除规则，请重试。',
  'Give the rule a name.': '请为规则命名。',
  'Add a keyword or a pattern.': '请添加关键词或模式。',
  'Keywords are 1 to {count} characters besides *.':
      '关键词除 * 外需为 1 到 {count} 个字符。',
  'A rule holds up to {count} keywords.': '一条规则最多包含 {count} 个关键词。',
  'A rule holds up to {count} patterns of {length} characters.':
      '一条规则最多包含 {count} 个模式，每个最多 {length} 个字符。',
  'The mention limit is 1 to 50.': '提及上限为 1 到 50。',
  'The message limit is 1 to 50.': '消息上限为 1 到 50。',
  'The time window is 1 to 300 seconds.': '时间范围为 1 到 300 秒。',
  'Choose a channel for alerts.': '请选择接收提醒的频道。',
  'Choose at least one action.': '请至少选择一项操作。',
  'This pattern is not a valid regular expression: {pattern}':
      '该模式不是有效的正则表达式：{pattern}',
  'This circle has as many rules of this kind as it can.': '本圈子此类规则已达上限。',
  'Rule name': '规则名称',
  'Actions': '操作',
  'Keep the message from being sent.': '阻止消息发送。',
  'Custom message (optional)': '自定义提示（可选）',
  'Shown to members when their message is blocked.': '成员的消息被拦截时向其显示。',
  'Post who sent what, and where, in a channel you choose.':
      '在你选择的频道中发布发送者、内容和位置。',
  'Alert channel': '提醒频道',
  '{count} seconds': '{count} 秒',
  'Exempt roles': '豁免角色',
  'Exempt channels': '豁免频道',
  'Keywords': '关键词',
  'Separate with commas. Keywords match whole words; use * for parts of words: *cat matches wildcat, cat* matches catch, *cat* matches anywhere.':
      '用逗号分隔。关键词按完整单词匹配；用 * 匹配单词的一部分：*cat 匹配 wildcat，cat* 匹配 catch，*cat* 匹配任意位置。',
  'Regex patterns (optional)': '正则表达式（可选）',
  'One regular expression per line, up to {count}. Matching ignores case.':
      '每行一个正则表达式，最多 {count} 个。匹配不区分大小写。',
  'Unique mentions allowed per message': '每条消息允许的不同提及数',
  'Messages with more user and role mentions than this match.':
      '提及的成员和角色多于此数的消息将被匹配。',
  'Messages allowed': '允许的消息数',
  'Within seconds': '时间范围（秒）',
  "Sending more messages than this across the circle's channels in that time matches.":
      '在此时间内于圈子各频道发送的消息多于此数时将被匹配。',

  // Refusals and alerts.
  'AutoMod blocked your message.': '你的消息已被自动审核拦截。',
  'AutoMod blocked your message: {reason}': '你的消息已被自动审核拦截：{reason}',
  'AutoMod blocked a message from {name} in #{channel}':
      '自动审核拦截了 {name} 在 #{channel} 发送的消息',
  'AutoMod flagged a message from {name} in #{channel}':
      '自动审核标记了 {name} 在 #{channel} 发送的消息',
  'Rule: {rule}': '规则：{rule}',
  'Matched: {match}': '匹配：{match}',
  'Timed out for {minutes} min': '已禁言 {minutes} 分钟',

  // Audit log.
  '{actor} created AutoMod rule {target}': '{actor} 创建了自动审核规则 {target}',
  '{actor} renamed AutoMod rule {old} to {target}':
      '{actor} 将自动审核规则 {old} 重命名为 {target}',
  '{actor} updated AutoMod rule {target}': '{actor} 更新了自动审核规则 {target}',
  '{actor} deleted AutoMod rule {target}': '{actor} 删除了自动审核规则 {target}',
  'AutoMod blocked a message by {target}': '自动审核拦截了 {target} 的一条消息',
  'AutoMod blocked a message by {target} in {channel}':
      '自动审核拦截了 {target} 在 {channel} 的一条消息',
  'AutoMod sent an alert about {target}': '自动审核发送了关于 {target} 的提醒',
  'AutoMod sent an alert about {target} in {channel}':
      '自动审核发送了关于 {target} 在 {channel} 的提醒',
  'AutoMod timed out {target}': '自动审核禁言了 {target}',
  'Rule': '规则',
  'Enabled': '已启用',
  'Patterns': '模式',
  'Mention limit': '提及上限',
  'Message limit': '消息上限',
  'Time window': '时间范围',
  'Custom message': '自定义提示',
  'Timeout': '禁言',
  'Keywords changed': '关键词已更改',
  'Patterns changed': '模式已更改',
  'Exemptions changed': '豁免已更改',
  // Member onboarding.
  'Onboarding': '新成员引导',
  'Could not load onboarding.': '无法加载新成员引导。',
  'Could not save onboarding. Try again.': '无法保存新成员引导，请重试。',
  'Onboarding saved.': '新成员引导已保存。',
  'Members must accept the rules': '成员须接受规则',
  'New members can read channels, but cannot send messages, react or join voice until they accept. Everyone already here counts as having accepted.':
      '新成员在接受规则前可以浏览频道，但不能发送消息、添加回应或加入语音。现有成员视为已接受。',
  'Rules': '规则',
  'Rule {number}': '规则 {number}',
  'Add rule': '添加规则',
  'Remove rule': '移除规则',
  'Add at least one rule first.': '请先至少添加一条规则。',
  'Welcome message': '欢迎消息',
  'Shown once to members after they accept the rules.': '成员接受规则后向其显示一次。',
  'Read and accept the rules of {circle} to start chatting.':
      '阅读并接受 {circle} 的规则后即可开始聊天。',
  'Read rules': '阅读规则',
  'Rules of {circle}': '{circle} 的规则',
  'Accept these rules to send messages, react and join voice.':
      '接受这些规则后即可发送消息、添加回应和加入语音。',
  'I have read and agree to the rules': '我已阅读并同意这些规则',
  'Not now': '暂不',
  'Could not accept the rules. Try again.': '无法接受规则，请重试。',
  'Welcome to {circle}!': '欢迎来到 {circle}！',
  'You can now send messages, react and join voice.': '你现在可以发送消息、添加回应和加入语音了。',
  "Let's go": '开始吧',
  'Accept the circle rules to start chatting.': '请先接受圈子规则再开始聊天。',
  '{actor} updated the onboarding': '{actor} 更新了新成员引导',
  'Welcome message changed': '欢迎消息已更改',
  // Two-step verification.
  'Account': '账号',
  'Two-step verification': '两步验证',
  'Ask for a code from an authenticator app when signing in':
      '登录时要求输入身份验证器应用中的验证码',
  'Could not load two-step verification.': '无法加载两步验证。',
  'Two-step verification is on': '两步验证已开启',
  'Two-step verification is on.': '两步验证已开启。',
  'Two-step verification is off.': '两步验证已关闭。',
  'Signing in asks for a code from your authenticator app after your password.':
      '登录时，输入密码后还需要输入身份验证器应用中的验证码。',
  'Protect your account with a code': '用验证码保护你的账号',
  'After your password, signing in will also ask for a code from an authenticator app on your phone.':
      '开启后，登录时除密码外还需要输入手机上身份验证器应用中的验证码。',
  'Set up an authenticator app': '设置身份验证器应用',
  '1. Scan this QR code with your authenticator app': '1. 用身份验证器应用扫描此二维码',
  "Can't scan it? Enter this key instead:": '无法扫描？请改为输入此密钥：',
  'Copy key': '复制密钥',
  '2. Enter the 6-digit code it shows': '2. 输入应用显示的 6 位验证码',
  '6-digit code': '6 位验证码',
  'Turn on': '开启',
  'Turn off': '关闭',
  'Turn off two-step verification?': '要关闭两步验证吗？',
  'Enter a code from your authenticator app to confirm. Signing in will then only need your password.':
      '请输入身份验证器应用中的验证码以确认。关闭后登录只需要密码。',
  'Enter the {count}-digit code.': '请输入 {count} 位验证码。',
  "That code didn't work. Enter the current code from your authenticator app.":
      '验证码无效。请输入身份验证器应用中当前显示的验证码。',
  'Two-step verification is not available on this server.': '此服务器未启用两步验证。',
  'Enter the code from your authenticator app': '输入身份验证器应用中的验证码',
  'Your account asks for a code when you sign in.': '你的账号在登录时需要输入验证码。',
  '{email} asks for a code when signing in.': '{email} 登录时需要输入验证码。',
  'Verify': '验证',
};
