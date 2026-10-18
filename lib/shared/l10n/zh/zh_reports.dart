// Simplified Chinese for message reports (lib/features/reports/), the policy
// pages, the sign-up agreement and the About page (lib/features/legal/), and
// the message-report parts of the admin console.
const zhReports = <String, String>{
  // Policy pages and About
  'Community Guidelines': '社区准则',
  'Privacy Policy': '隐私政策',
  'Terms of Service': '服务条款',
  'Could not load this page.': '无法加载这个页面。',
  'About WeCord': '关于 WeCord',
  'Terms, privacy and licences': '条款、隐私和开源许可',
  'WeCord': 'WeCord',
  'Legal': '法律信息',
  'Open-source licences': '开源许可',
  'The legal texts are drafts and may still change.': '这些法律文本是草稿，可能还会修改。',
  // Sign-up and the prompt for existing accounts
  'I am at least {age} and agree to the [Terms of Service] and the [Community Guidelines].':
      '我已年满 {age} 岁，并同意[服务条款]和[社区准则]。',
  'Agree to the terms': '同意条款',
  'Please confirm your age and agree to the Terms and Community Guidelines.':
      '请确认你的年龄，并同意服务条款和社区准则。',
  'Please review our terms': '请查看我们的条款',
  'We have written down the Terms of Service and Community Guidelines. Please read them and confirm once.':
      '我们写好了服务条款和社区准则。请阅读，并确认一次。',
  'Not now': '暂不',
  'Agree': '同意',
  'Could not save that. Try again.': '无法保存，请重试。',
  // Reporting a message
  'Report': '举报',
  'Report message': '举报消息',
  'Report sent. Thank you for helping keep WeCord safe.':
      '举报已发送，感谢你帮助维护 WeCord 的安全。',
  'the sender': '发送者',
  "This goes to this circle's moderators. The person you report won't know it was you.":
      '举报会交给本圈的版主。被举报的人不会知道是你。',
  "This goes to the WeCord team. The person you report won't know it was you.":
      '举报会交给 WeCord 团队。被举报的人不会知道是你。',
  'Include context': '附带上下文',
  'Shares up to 5 messages before and after it, as you see them. They are deleted 90 days after the report is handled.':
      '同时提交它前后各最多 5 条你能看到的消息。举报处理完 90 天后会删除。',
  'Also block {name}': '同时拉黑 {name}',
  "You won't see each other's messages.": '你们将看不到对方的消息。',
  'Read the Community Guidelines': '阅读社区准则',
  'You have sent too many reports today. Try again tomorrow.':
      '你今天提交的举报太多了，请明天再试。',
  'This message is no longer available.': '这条消息已经不存在了。',
  'This message cannot be reported.': '这条消息不能举报。',
  'View-once photo or video (not kept)': '阅后即焚的照片或视频（不保存）',
  // The circle's Review queue
  'User reports': '用户举报',
  'Held or flagged by the AI guard': 'AI 守护扣留或标记的消息',
  'Messages the AI guard holds back or flags, and messages people report, show up here.':
      'AI 守护扣留或标记的消息，以及被举报的消息，会出现在这里。',
  'No text.': '没有文字。',
  'Reported by {name}': '{name} 举报',
  'Reported by {name} and {count} others': '{name} 等 {count} 人举报',
  'Show context ({count})': '查看上下文（{count}）',
  'Hide context': '隐藏上下文',
  'Dismiss report': '忽略举报',
  'Time out': '禁言',
  'Time out {name}': '禁言 {name}',
  '{name} was timed out.': '{name} 已被禁言。',
  '{count} hour': '{count} 小时',
  '{count} day': '{count} 天',
  '{count} week': '{count} 周',
  'Ban': '封禁',
  'Ban {name}?': '封禁 {name}？',
  'They are removed from the circle and cannot join again.': '对方会被移出圈子，无法再加入。',
  '{name} was banned.': '{name} 已被封禁。',
  'Delete this message?': '删除这条消息？',
  'It is deleted for everyone.': '它会对所有人删除。',
  'Delete message': '删除消息',
  'Message deleted.': '消息已删除。',
  "You don't have permission to do that.": '你没有权限这样做。',
  "Couldn't update this report. It may already be handled.": '无法更新这条举报，可能已被处理。',
  // Admin console: reports of messages
  'It is deleted for everyone in the chat.': '会对聊天里的所有人删除。',
  'The message was deleted.': '消息已删除。',
  'Message deleted': '消息已删除',
  'Message is live': '消息仍然存在',
  'Sender': '发送者',
  'Chat': '聊天',
  'Group {name}': '群聊 {name}',
  'Direct chat': '私聊',
  'Sent': '发送时间',
  'Messages around it': '前后的消息',
  'Suspend sender': '封禁发送者',
  '{actor} deleted a reported message: {title}': '{actor} 删除了被举报的消息：{title}',
  '{actor} suspended the sender of a reported message': '{actor} 封禁了被举报消息的发送者',
  '{actor} dismissed a message report': '{actor} 忽略了一条消息举报',
};
