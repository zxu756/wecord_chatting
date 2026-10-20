// Chinese for AI guard 2.0 (polls, pictures, events, notes and tasks in the
// guard's reach, the Review queue's new cards), the anti-scam hint under a
// stranger's message, and the link-safety warning page.
const zhGuard2 = <String, String>{
  // What the guard checks (settings).
  'Also checks': '另外检查',
  'Polls': '投票',
  'The question and the options.': '问题和选项。',
  'Titles of events, notes and tasks': '活动、笔记和任务的标题',
  'Checked after they are made. What the AI flags is listed for moderators; it is never hidden.':
      '创建后再检查。AI 标记的内容会列给版主处理，不会被隐藏。',
  "Sent to the AI provider's picture model. Costs more than text.":
      '会发送给 AI 服务商的图片模型，比文字更费钱。',
  'Not set up on this server yet, so pictures are sent as usual.':
      '服务器尚未设置，所以图片会照常发送。',
  'Pictures from new members go to the AI provider only while this is on, and WeCord does not keep them. If the AI cannot read a picture, it is shown as usual and marked as not checked.':
      '只有在开启时，新成员发的图片才会发送给 AI 服务商，WeCord 不会保存。如果 AI 读不了图片，图片会照常显示，并标记为未检查。',

  // Review queue.
  'Events, notes and tasks flagged by the AI guard': 'AI 守护标记的活动、笔记和任务',
  'These are visible to everyone. Open one to deal with it, then dismiss the card.':
      '它们对所有人可见。打开处理之后，再关闭这张卡片。',
  'Task list': '任务清单',
  'Card dismissed.': '卡片已关闭。',
  "Couldn't update this card. It may already be reviewed.":
      '无法更新这张卡片，可能已经处理过了。',
  "Couldn't load the picture.": '无法加载图片。',
  'Picture waiting for review': '待审核的图片',

  // Audit log.
  'AI guard flagged an event by {target}': 'AI 守护标记了 {target} 的一个活动',
  'AI guard flagged a note by {target}': 'AI 守护标记了 {target} 的一篇笔记',
  'AI guard flagged a task by {target}': 'AI 守护标记了 {target} 的一个任务',
  'AI guard flagged something made by {target}': 'AI 守护标记了 {target} 创建的内容',
  '{actor} dismissed a flagged item by {target} from the review queue':
      '{actor} 在审核队列中关闭了 {target} 的一项被标记内容',

  // The hint under a stranger's message.
  "Watch out for scams: they aren't your friend": '谨防诈骗：对方不是你的好友',
  "They're asking about a payment or transfer. Never pay someone you can't verify.":
      '对方在提收款或转账。不要给无法核实身份的人付款。',
  "They're asking for a verification code. Never share one.":
      '对方在索要验证码。千万不要把验证码告诉任何人。',
  'Prizes and giveaways from strangers are usually scams.':
      '陌生人发来的中奖和赠品消息多半是骗局。',
  'Promises of easy returns are a common scam.': '承诺轻松高回报是常见的骗局。',
  'Nobody legitimate asks to be paid in gift cards.': '正规的人不会要求用礼品卡付款。',
  "Real support teams don't ask for passwords or codes in chat.":
      '真正的客服不会在聊天里索要密码或验证码。',
  'This link looks suspicious. Check it before you tap.': '这个链接看起来可疑，点开前请先确认。',
  'Report this message': '举报这条消息',
  'Hide warnings for this person': '不再提醒此人',

  // Link safety.
  'Be careful with this link': '小心这个链接',
  'This link looks unsafe': '这个链接看起来不安全',
  'WeCord looked at the address only, not at the page. Open it only if you trust the person who sent it.':
      'WeCord 只检查了地址，没有打开页面。只有信任发送者时才打开。',
  'This link goes to': '这个链接指向',
  'Then it redirects to {host}': '然后会跳转到 {host}',
  'Why it looks risky': '为什么看起来有风险',
  'Go back': '返回',
  'Open anyway': '仍然打开',
  'Ask AI to check this link': '让 AI 检查这个链接',
  "Sends the address (without anything after a ?) and the page's title to the AI. Nothing from your chat.":
      '会把地址（不含 ? 之后的内容）和页面标题发送给 AI，不会发送你的聊天内容。',
  'AI thinks it looks fine': 'AI 认为看起来没问题',
  'AI finds it suspicious': 'AI 觉得它可疑',
  'AI thinks it is dangerous': 'AI 认为它很危险',
  "AI can't tell": 'AI 无法判断',
  'AI can be wrong. It has not opened the link.': 'AI 也可能判断错误，它并没有打开这个链接。',
  'What comes before the @ in the address is not the website you will visit.':
      '地址里 @ 前面的部分并不是你要访问的网站。',
  'It points to a number instead of a website name.': '它指向的是一串数字，而不是网站名称。',
  'The website name uses look-alike characters.': '网站名称使用了外观相似的字符。',
  "It is a short link, so you can't see where it goes.": '这是短链接，看不出它会跳转到哪里。',
  "The name looks like a well-known site, but it isn't.": '名称看起来像知名网站，其实不是。',
  "A well-known site's name is used to hide the real address.":
      '用知名网站的名字来掩盖真实地址。',
  'It ends in an extension often used by throwaway sites.': '它的后缀常被一次性网站使用。',
  'The address asks you to log in, verify or claim something.':
      '地址在引导你登录、验证或领取东西。',
  'The address is unusually long.': '地址长得不寻常。',
  'The name is stuffed with hyphens.': '名称里塞满了连字符。',
  'It downloads an app or a program.': '它会下载应用或程序。',
  "The page isn't encrypted (http), yet it asks for something.":
      '页面没有加密（http），却在要求你提供东西。',
  'It sends you on to a riskier address.': '它会把你带到风险更高的地址。',
};
