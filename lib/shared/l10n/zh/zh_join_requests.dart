// Chinese for circle join requests (入圈申请): the join mode and questions in
// circle settings, the applicant's form and waiting states, the moderators'
// "Join requests" on the Review page, Notifications, the audit log and the
// invite sheet's "Skip review".
// "Request" reads 申请 here (a request to join), not 请求; moderators 版主;
// "turn down" and "Deny" 拒绝.
const zhJoinRequests = <String, String>{
  // Join mode and the questions editor.
  'Join mode': '入圈方式',
  'Open, apply to join, or invite only': '开放、申请加入或仅限邀请',
  'join mode|Open': '开放',
  'Apply to join': '申请加入',
  'Invite only': '仅限邀请',
  'Anyone with an invite link, or from Explore if the circle is public, joins at once.':
      '任何人通过邀请链接，或在圈子公开时从探索页加入，都会立即进圈。',
  'Everyone who tries to join sends a request. Members who can remove members approve or deny it.':
      '每个想加入的人都要提交申请，由有移除成员权限的成员批准或拒绝。',
  'Nobody joins from Explore. Invite links and invites from members still work.':
      '不能从探索页加入。邀请链接和成员发出的邀请仍然有效。',
  'Questions': '问题',
  'Up to {count} questions people answer when they ask to join. Moderators read the answers before they decide.':
      '最多 {count} 个问题，申请加入的人需要回答。版主会先看回答再决定。',
  'Add question': '添加问题',
  'Question {number}': '问题 {number}',
  'Remove question': '删除问题',
  'Why do you want to join?': '你为什么想加入？',
  'Answer type': '回答方式',
  'Written answer': '文字回答',
  'Pick one': '单选',
  'Option {number}': '选项 {number}',
  'Add option': '添加选项',
  'Remove option': '删除选项',
  'Required': '必答',
  'Optional': '选填',
  'Every question needs its words, and a choice needs two or more options.':
      '每个问题都要写内容，单选题至少要有两个选项。',
  'Could not load join settings.': '无法加载入圈设置。',
  'Could not save join settings. Try again.': '无法保存入圈设置，请重试。',
  'Join settings saved.': '入圈设置已保存。',
  // The applicant.
  'Send request': '提交申请',
  'join request|Request sent': '申请已提交',
  'Cancel request': '撤回申请',
  'Try again tomorrow': '明天再试',
  'Not taking new members': '暂不接收新成员',
  'Waiting for review': '等待审核',
  'A member invited you. The moderators decide whether you join, and you will be told here.':
      '有成员邀请了你。版主会决定你能否加入，结果会通知你。',
  'The moderators have your request. You will be told here when they decide.':
      '版主已收到你的申请，决定后会在这里通知你。',
  'Your request was turned down': '你的申请未通过',
  'Their note: {note}': '对方留言：{note}',
  'You can ask again tomorrow.': '明天可以再次申请。',
  'This circle is invite only.': '这个圈子仅限邀请。',
  'Ask a member for an invite to join this circle.': '向圈子成员要一个邀请，才能加入这个圈子。',
  'This circle is not taking new members.': '这个圈子暂不接收新成员。',
  'Your request was turned down. You can ask again tomorrow.':
      '你的申请未通过，明天可以再次申请。',
  'You have too many requests waiting. Wait for an answer first.':
      '你有太多申请在等待回复，请先等结果。',
  'Answer the required questions first.': '请先回答必答问题。',
  'The moderators of this circle approve everyone who joins.':
      '这个圈子的版主会审核每一位加入的人。',
  'The moderators of this circle approve everyone who joins. Answer their questions to send your request.':
      '这个圈子的版主会审核每一位加入的人。回答他们的问题后即可提交申请。',
  'Your answer': '你的回答',
  // The Review page.
  'Join requests': '入圈申请',
  'Could not load join requests.': '无法加载入圈申请。',
  '{name} can join now.': '{name} 现在可以加入了。',
  'Request turned down.': '已拒绝这条申请。',
  "Couldn't update this request. It may already be decided.":
      '无法更新这条申请，可能已经有人处理了。',
  'Invited by {name}': '由 {name} 邀请',
  'No answers.': '没有回答。',
  'Account created {time}': '账号注册于 {time}',
  'Turn down {name}?': '拒绝 {name} 的申请？',
  'They are told. You can add a reason they will read. They can ask again after a day.':
      '对方会收到通知。你可以写一条理由，对方会看到。一天后对方可以再次申请。',
  // Notifications.
  'Your request to join {circle} is waiting for review':
      '你加入 {circle} 的申请正在等待审核',
  '{circle} approved your request to join': '{circle} 通过了你的入圈申请',
  '{circle} turned down your request to join': '{circle} 拒绝了你的入圈申请',
  'Open it to read the rules and say hello.': '打开圈子，阅读规则并打个招呼。',
  'Got it': '知道了',
  'Answers to your requests to join circles show up here.': '你的入圈申请的结果会显示在这里。',
  // The invite sheet.
  'Skip review': '免审核',
  'skips review': '免审核',
  'People who use this link join at once, even when the circle reviews who joins.':
      '通过此链接加入的人会立即进圈，即使圈子需要审核。',
  // The audit log.
  '{actor} approved the request of {target} to join':
      '{actor} 通过了 {target} 的入圈申请',
  '{actor} turned down the request of {target} to join':
      '{actor} 拒绝了 {target} 的入圈申请',
  '{actor} made the circle apply to join': '{actor} 将圈子设为申请加入',
  '{actor} made the circle invite only': '{actor} 将圈子设为仅限邀请',
  '{actor} opened the circle to everyone': '{actor} 将圈子设为开放加入',
  '{actor} updated the join questions': '{actor} 更新了入圈问题',
  '{actor} made invite {target} skip review': '{actor} 将邀请 {target} 设为免审核',
};
