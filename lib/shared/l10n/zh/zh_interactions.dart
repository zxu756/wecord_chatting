// Chinese for interactive components and interaction callbacks (roadmap I1):
// a bot's buttons, links, lists and forms, its private replies, and the
// callback address of a bot. 'Send', 'Cancel', 'Open', 'Done', 'Save', 'Copy',
// 'Remove' and 'Dismiss' already have a Chinese text elsewhere.
const zhInteractions = <String, String>{
  'Sent. Waiting for the bot…': '已发送，等待机器人回应…',
  'Sent to {bot}. Waiting for an answer…': '已发送给 {bot}，等待回应…',
  'Could not reach the bot. Try again.': '无法联系机器人，请重试。',
  'Done.': '已处理。',
  'The bot did not answer.': '机器人没有回应。',
  '{bot} did not answer.': '{bot} 没有回应。',
  'Opens a form': '打开表单',
  'Opens a website': '打开网站',
  'Opens a list': '打开列表',
  'Choose…': '请选择…',
  '{label} (optional)': '{label}（选填）',
  'This field is required.': '这一项必填。',
  'This goes to the bot, which can read it.': '这些内容会发给机器人，机器人能看到。',
  'Open this link?': '打开这个链接？',
  'A bot added this button. It goes to:': '这个按钮是机器人加的，它会打开：',
  'Too fast. Wait a moment and try again.': '点得太快了，请稍等再试。',
  'You cannot use this bot.': '你不能使用这个机器人。',
  'That answer is not valid. Check it.': '填写的内容无效，请检查。',
  'Only you can see this': '仅你可见',
  'Could not dismiss this. Try again.': '无法关闭，请重试。',
  '{name} pressed {label}': '{name} 点了「{label}」',
  // Settings of a bot
  'Callback address': '回调地址',
  'Could not load the callback. Try again.': '无法加载回调设置，请重试。',
  'Could not save the callback. Try again.': '无法保存回调设置，请重试。',
  'That address cannot be used. It must be the https address of a website (no IP addresses, no ports, no inner names).':
      '这个地址不能使用。它必须是网站的 https 地址（不能是 IP 地址、不能带端口、不能是内网名称）。',
  'The address must start with https://': '地址必须以 https:// 开头',
  "WeCord sends {name}'s button presses and slash commands to this address as they happen, signed with a secret. Without one, the bot asks for them by polling.":
      '有人点 {name} 的按钮或使用斜杠命令时，WeCord 会立刻把它发到这个地址，并用密钥签名。不设置的话，机器人要自己定时来取。',
  'https address': 'https 地址',
  'https://bots.example.com/wecord': 'https://bots.example.com/wecord',
  'Paused: too many sends failed in a row. Save the address again to turn it back on. Meanwhile the bot can poll.':
      '已暂停：连续多次发送失败。再次保存地址即可恢复。期间机器人仍可自己来取。',
  'The last send failed ({reason}). WeCord tries again.':
      '上一次发送失败（{reason}），WeCord 会再试。',
  'Working. The last send went through.': '正常。上一次发送成功。',
  'Nothing has been sent yet.': '还没有发送过。',
  'Reset secret': '重置密钥',
  'Callback secret': '回调密钥',
  'New callback secret': '新的回调密钥',
  'Copy the secret now: it is shown only once. Use it to check the X-WeCord-Signature of every request.':
      '请现在复制密钥：它只显示这一次。用它来校验每个请求的 X-WeCord-Signature。',
  'Secret copied.': '密钥已复制。',
  '{actor} set the callback address of bot {target}':
      '{actor} 设置了机器人 {target} 的回调地址',
  '{actor} reset the callback secret of bot {target}':
      '{actor} 重置了机器人 {target} 的回调密钥',
  '{actor} removed the callback of bot {target}': '{actor} 移除了机器人 {target} 的回调',
};
