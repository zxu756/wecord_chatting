// Chinese for the developer page, event subscriptions (outgoing webhooks), the
// bot search and the bots of a group. 'Bots', 'BOT', 'API address', 'Reset
// token', 'Revoke token', 'Description', 'Message', 'Add', 'Remove', 'Copy',
// 'Done', 'Save', 'Cancel', 'Reset', 'Revoke', 'Refresh', 'Waiting', 'Sending'
// and 'Just now' already have a Chinese text elsewhere.
const zhDeveloper = <String, String>{
  'Developer': '开发者',
  'Bots, event subscriptions and the bot API': '机器人、事件订阅和机器人 API',
  'Bot API documentation': '机器人 API 文档',
  'Endpoints, events and examples': '接口、事件和示例',
  'Bots are programs that act in your circles. Each bot has a token to call the bot API and can get events as they happen. Only people who manage a circle can see this page.':
      '机器人是在你的圈子里行动的程序。每个机器人都有一个令牌来调用机器人 API，还可以实时收到事件。只有管理圈子的人才能看到这个页面。',
  'Your bots': '你的机器人',
  'Only people who manage a circle can use this page.': '只有管理圈子的人才能使用这个页面。',
  'Could not load your bots.': '无法加载你的机器人。',
  'Tap to try again.': '点按重试。',
  'No bots yet. Make one in a circle: Circle settings, Bots, New bot.':
      '还没有机器人。在圈子里创建：圈子设置，机器人，新建机器人。',
  'Events: not set': '事件：未设置',
  'Events: on': '事件：已开启',
  'Events: paused': '事件：已暂停',
  '{count} calls in the last day': '最近一天调用 {count} 次',
  'Bot': '机器人',
  'This bot is not available.': '这个机器人不可用。',
  'Token': '令牌',
  'API address copied.': 'API 地址已复制。',
  'Make a new token; the current one stops working': '生成新令牌；当前令牌将立即失效',
  'Token revoked. Make a new one to use the bot.': '令牌已吊销。生成新令牌后才能使用这个机器人。',
  'Event address': '事件地址',
  'Not set. The bot can still ask for things by polling.': '未设置。机器人仍可通过轮询获取内容。',
  'Send a test event': '发送测试事件',
  'A test event is on its way.': '测试事件已在发送途中。',
  'Could not send the test event. Try again.': '无法发送测试事件，请重试。',
  'Reset event secret': '重置事件密钥',
  'Events signed with the old secret stop being accepted by your program once it uses the new one.':
      '你的程序改用新密钥后，用旧密钥签名的事件将不再被接受。',
  'Could not reset the secret. Try again.': '无法重置密钥，请重试。',
  'Remove event address': '移除事件地址',
  '{name} stops getting events. Events that are still waiting are dropped.':
      '{name} 将不再收到事件，仍在等待发送的事件会被丢弃。',
  'Could not remove the event address. Try again.': '无法移除事件地址，请重试。',
  'Where button presses and slash commands go': '按钮点击和斜杠命令发送到的地方',
  'Events tell your program what happens in the bot\'s chats without polling. They are signed, so your program can check they come from WeCord.':
      '事件无需轮询，就能告诉你的程序机器人所在的聊天里发生了什么。事件带有签名，你的程序可以确认它们来自 WeCord。',
  'Paused: too many events failed in a row, or the person who set this up no longer manages the circle. Save the address again to turn it back on.':
      '已暂停：连续多个事件发送失败，或者设置它的人不再管理这个圈子。再次保存地址即可重新开启。',
  '{count} events were skipped because the bot was too busy.':
      '机器人太忙，有 {count} 个事件被跳过。',
  'Recent events': '最近的事件',
  'Delivered': '已送达',
  'Failed': '失败',
  'Skipped': '已跳过',
  'Could not load the events.': '无法加载事件。',
  'Availability': '可用范围',
  'Open bots can be found by anyone who searches for them. They only see the chats they are in.':
      '开放的机器人任何人都能搜到。它们只能看到自己所在的聊天。',
  'People can message this bot': '任何人都可以给这个机器人发消息',
  'Anyone can start a direct chat with it': '任何人都可以与它开始私聊',
  'Group owners can add this bot': '群主可以添加这个机器人',
  'A group owner can bring it into a group chat': '群主可以把它拉进群聊',
  'Bot description': '机器人简介',
  'What the bot does. People see it when they find the bot.':
      '机器人的用途。人们找到它时会看到这段话。',
  'Recent API calls': '最近的 API 调用',
  'Could not load the calls.': '无法加载调用记录。',
  'This bot has not called the API yet.': '这个机器人还没有调用过 API。',
  'New messages': '新消息',
  'Messages that mention the bot': '提到机器人的消息',
  'Edited messages': '被编辑的消息',
  'Deleted messages': '被删除的消息',
  'Reactions added': '新增的表情回应',
  'Members who joined': '加入的成员',
  'Members who left': '离开的成员',
  'Button presses and slash commands': '按钮点击和斜杠命令',
  'Choose at least one kind of event.': '请至少选择一种事件。',
  'WeCord sends the chosen events of {name}\'s chats to this address as they happen, signed with a secret. Only chats the bot is in and messages it may read are included.':
      'WeCord 会把 {name} 所在聊天里你选择的事件实时发送到这个地址，并用密钥签名。只包含机器人所在的聊天，以及它有权读取的消息。',
  'https://bots.example.com/events': 'https://bots.example.com/events',
  'Events to send': '要发送的事件',
  'Could not save the event address. Try again.': '无法保存事件地址，请重试。',
  'Event secret': '事件密钥',
  'New event secret': '新的事件密钥',
  'Copy the secret now: it is shown only once. Use it to check the X-WeCord-Signature of every event.':
      '请现在复制密钥：它只显示一次。用它来校验每个事件的 X-WeCord-Signature。',
  'Find a bot': '查找机器人',
  'Chat with bots made by others': '与其他人做的机器人聊天',
  'Search bots by name': '按名称搜索机器人',
  'Type at least 2 letters of a bot\'s name. Only bots whose makers opened them to everyone are listed.':
      '请输入机器人名称的至少 2 个字。只列出作者向所有人开放的机器人。',
  'No bots found.': '没有找到机器人。',
  'Could not start the chat. Try again.': '无法开始聊天，请重试。',
  'Add a bot': '添加机器人',
  'Add a bot to this group': '给这个群添加机器人',
  'Could not add the bot. A group can have up to 5 bots, and some chats do not allow bots.':
      '无法添加机器人。一个群最多可以有 5 个机器人，有些聊天不允许机器人。',
  'Bots in this group': '本群的机器人',
  'A bot in a group reads the messages of this group and can write in it. Everyone in the group can see which bots are here.':
      '群里的机器人可以读取本群的消息，也可以在群里发言。群里所有人都能看到有哪些机器人。',
  'Remove bot': '移除机器人',
  '{name} leaves this group and sees nothing more of it.':
      '{name} 将离开这个群，之后看不到群里的任何内容。',
  'Could not remove the bot. Try again.': '无法移除机器人，请重试。',
  'No bots in this group.': '本群没有机器人。',
  '{actor} set the event address of bot {target}':
      '{actor} 设置了机器人 {target} 的事件地址',
  '{actor} reset the event secret of bot {target}':
      '{actor} 重置了机器人 {target} 的事件密钥',
  '{actor} removed the event address of bot {target}':
      '{actor} 移除了机器人 {target} 的事件地址',
  '{actor} changed who can use bot {target}': '{actor} 更改了谁可以使用机器人 {target}',
};
