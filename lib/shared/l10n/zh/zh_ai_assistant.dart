// Chinese for the WeCord AI assistant (@WeCord AI in chats, 在群里召唤 AI) and
// "Extract to-dos" (从聊天提取待办): the Ask sheet, the AI answer's footer, the
// group owner's switch and the review sheet. 'Task', 'Event', 'Title', 'Assign',
// 'Due date', 'Try again' and 'Task created.' are already translated elsewhere.
const zhAiAssistant = <String, String>{
  // The group owner's switch.
  'WeCord AI in this group': '在本群使用 WeCord AI',
  'Members can mention @WeCord AI to ask a question, summarize or list to-dos. Everyone sees the answer. Turn off to stop it answering here.':
      '成员可以 @WeCord AI 提问、总结或列出待办，所有人都能看到回答。关闭后，它不会在本群回答。',
  // The Ask sheet.
  'Ask WeCord AI': '问 WeCord AI',
  'Your question': '你的问题',
  'Summarize the plan, list the to-dos, translate to English…':
      '总结方案、列出待办、翻译成英文…',
  'Summarize this': '总结一下',
  'List the to-dos': '列出待办',
  'Translate to English': '翻译成英文',
  'Explain this': '解释一下',
  'What can WeCord AI read?': 'WeCord AI 可以读取什么？',
  'This message': '仅这条消息',
  'Last 20 messages': '最近 20 条消息',
  'Last 100 messages': '最近 100 条消息',
  'Reads only your question.': '只读取你的问题。',
  'Reads your question and the message you are asking about.':
      '读取你的问题和你所问的那条消息。',
  'Also reads the last 20 messages you can see in this chat.':
      '同时读取你在此聊天里能看到的最近 20 条消息。',
  'Also reads the last 100 messages you can see in this chat.':
      '同时读取你在此聊天里能看到的最近 100 条消息。',
  'Everyone in this chat sees your question and the answer, and can report the answer. WeCord AI only reads what you can see here.':
      '此聊天里的所有人都会看到你的问题和回答，也可以举报这条回答。WeCord AI 只会读取你在这里能看到的内容。',
  'Sent. WeCord AI will answer in the chat.': '已发送，WeCord AI 会在聊天里回答。',
  // Under messages.
  'AI-generated': 'AI 生成',
  'AI-generated · asked by {name}': 'AI 生成 · {name} 提问',
  'Make tasks': '转成任务',
  'WeCord AI is thinking…': 'WeCord AI 正在思考…',
  'The group owner turned off WeCord AI here.': '群主已关闭本群的 WeCord AI。',
  'You asked too quickly. Wait a moment and try again.': '提问太频繁了，请稍等片刻再试。',
  "WeCord AI couldn't answer. Try again.": 'WeCord AI 没能回答，请重试。',
  // Extract to-dos.
  'Extract to-dos': '提取待办',
  'Pick up to {count} messages.': '最多选择 {count} 条消息。',
  'To-dos from the chat': '从聊天提取待办',
  'Reading {count} messages…': '正在阅读 {count} 条消息…',
  'Reading the message…': '正在阅读这条消息…',
  'No to-dos or events found in these messages.': '这些消息里没有找到待办或日程。',
  'WeCord AI suggests these. Change anything and untick what you do not want; nothing is created until you confirm.':
      'WeCord AI 给出了这些建议。你可以修改，也可以取消勾选不需要的；确认之前不会创建任何内容。',
  'Nothing selected': '未选择任何项',
  'Create 1 item': '创建 1 项',
  'Create {count} items': '创建 {count} 项',
  'Read {count} messages.': '已阅读 {count} 条消息。',
  '1 assigned': '已指派 1 人',
  'Include': '包含',
  'Include in the new items': '加入要创建的项目',
  'Make it a': '创建为',
  '{done} created. {failed} could not be created. Try again.':
      '已创建 {done} 项，{failed} 项创建失败，请重试。',
  'Could not create them. Try again.': '创建失败，请重试。',
  '1 task': '1 个任务',
  '{count} tasks': '{count} 个任务',
  '1 event': '1 个活动',
  '{count} events': '{count} 个活动',
  '{tasks} and {events} created.': '已创建{tasks}和{events}。',
  'Event created.': '已创建活动。',
  '{count} events created.': '已创建 {count} 个活动。',
  '{count} tasks created.': '已创建 {count} 个任务。',
};
