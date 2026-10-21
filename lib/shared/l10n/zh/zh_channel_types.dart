// Chinese for media channels and Q&A channels (roadmap C9): the picture wall,
// the questions with their solved mark and accepted answer, and the audit
// log entries. 'Media', 'Question', 'Details' and the others that already have
// a Chinese text elsewhere are not repeated here.
const zhChannelTypes = <String, String>{
  'Q&A': '问答',
  'Solved': '已解决',
  'Unsolved': '未解决',
  'Ask a question': '提问',
  'Ask in {channel}': '在 {channel} 提问',
  'Accepted answer': '已采纳的回答',
  'Accept as answer': '采纳为答案',
  'Remove accepted answer': '取消采纳',
  'Mark as solved': '标记为已解决',
  'Reopen question': '重新打开问题',
  'Answer accepted.': '已采纳这个回答。',
  'Marked as solved.': '已标记为已解决。',
  'Question reopened.': '问题已重新打开。',
  'Could not change the accepted answer. Try again.': '无法修改采纳的回答，请重试。',
  'Could not mark the question solved. Try again.': '无法把问题标记为已解决，请重试。',
  'Could not reopen the question. Try again.': '无法重新打开问题，请重试。',
  'Could not load questions.': '无法加载问题。',
  'No questions yet': '还没有问题',
  'No solved questions': '没有已解决的问题',
  'No open questions': '没有未解决的问题',
  'Ask the first question with Ask a question.': '点「提问」问第一个问题。',
  'You cannot ask in this channel.': '你不能在这个频道提问。',
  'No pictures yet': '还没有图片',
  'Share the first picture with New post.': '点「新帖子」分享第一张图片。',
  'You cannot post in this media channel.': '你不能在这个媒体频道发帖。',
  'A wall of pictures: every post needs a picture.': '图片墙：每个帖子都要带一张图片。',
  'Members ask questions and mark them solved with an answer.':
      '成员提问，并用一个回答把问题标记为已解决。',
  'Add a picture to post here.': '在这里发帖需要添加一张图片。',
  'Helps people who cannot see the picture.': '方便看不到图片的人了解图片内容。',
  'Posted by {name}': '发布者：{name}',
  '{actor} marked question {target} as solved': '{actor} 把问题 {target} 标记为已解决',
  '{actor} marked question {target} in {channel} as solved':
      '{actor} 把 {channel} 里的问题 {target} 标记为已解决',
  '{actor} reopened question {target}': '{actor} 重新打开了问题 {target}',
  '{actor} reopened question {target} in {channel}':
      '{actor} 重新打开了 {channel} 里的问题 {target}',
};
