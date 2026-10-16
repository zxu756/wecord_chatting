// AI features: catch-up summaries, rewriting in the composer, translating
// messages, and the controls for them.
const zhAi = <String, String>{
  // Languages.
  'English': '英语',
  'Chinese': '中文',
  'Japanese': '日语',
  'Korean': '韩语',
  'Spanish': '西班牙语',
  'French': '法语',
  // Rewrite actions.
  'Fix spelling & grammar': '修正拼写和语法',
  'Make it shorter': '精简一些',
  'Make it more polite / friendly': '更礼貌、更友好',
  'Make it more formal': '更正式',
  'Translate to…': '翻译成…',
  // Rewrite sheet.
  'Rewrite with AI': '用 AI 改写',
  'Write a message first, then use AI to polish it.': '先写好消息，再用 AI 润色。',
  'This message is too long for AI to rewrite.': '这条消息太长，AI 无法改写。',
  'Your message': '你的消息',
  'Suggestion': 'AI 建议',
  'Working on it…': '处理中…',
  'Written by AI. Nothing is sent until you send it.':
      '由 AI 生成，在你发送之前不会发出任何内容。',
  'Replace': '替换',
  'Insert below': '插入下方',
  // Translating messages.
  'Translate': '翻译',
  'Translating…': '正在翻译…',
  'Translated to {language}': '已翻译为{language}',
  'Show original': '显示原文',
  // Errors.
  "AI features aren't set up on this server yet.": '此服务器尚未设置 AI 功能。',
  "You've reached today's AI limit of {limit} requests. It resets tomorrow.":
      '你已用完今天 {limit} 次 AI 请求的额度，明天会重置。',
  "You've reached today's AI limit. It resets tomorrow.":
      '你已用完今天的 AI 额度，明天会重置。',
  'AI is busy right now. Try again in a little while.': 'AI 现在比较忙，请稍后再试。',
  'AI features are turned off in this circle.': '此圈子已关闭 AI 功能。',
  "That can't be processed.": '无法处理这条内容。',
  'Something went wrong. Try again.': '出了点问题，请重试。',
  'Try again': '重试',
  'Dismiss': '关闭',
  // Catch-up summary.
  'Summarize': '总结',
  '{count} unread messages': '{count} 条未读消息',
  'Get a short summary of what happened while you were away.': '快速了解你不在时发生了什么。',
  'Summarize what you missed': '总结你错过的内容',
  'Summarizing…': '正在总结…',
  'What you missed': '你错过的内容',
  'Recent messages': '最近的消息',
  'Nothing to summarize': '没有可总结的内容',
  'There is nothing new here to catch up on.': '这里没有需要追的新消息。',
  "Couldn't summarize": '无法总结',
  'Written by AI. Check anything important.': '由 AI 生成，重要内容请自行核对。',
  'Jump to first unread': '跳到第一条未读',
};
