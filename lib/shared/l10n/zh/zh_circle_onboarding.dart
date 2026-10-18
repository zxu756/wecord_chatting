// Chinese for onboarding 2.0 (引导 2.0): the questions a new member answers
// (兴趣问题), the roles they give (角色, as everywhere in the app), the
// newcomer tasks (新人任务) with their progress, the "New member guide" card
// and page, the editor in Onboarding settings, and the "joined the circle"
// card with its Say hello (打招呼) button.
const zhCircleOnboarding = <String, String>{
  // The card, the page, the menu.
  'New member guide': '新人指南',
  'Member guide': '新人指南',
  'Questions waiting': '有问题待回答',
  '{done} of {total} done': '已完成 {done}/{total}',
  'All done. Welcome aboard!': '全部完成，欢迎加入！',
  'Not done yet': '未完成',
  'Your interests': '我的兴趣',
  'Change my answers': '修改我的回答',
  'Choose what you are into': '选择你的兴趣',
  'Your answers can give you roles and show you the channels that fit.':
      '你的回答可以让你获得角色，并看到适合你的频道。',
  'Show the guide at the top of the circle': '在圈子顶部显示新人指南',
  'The guide stays in the circle menu if you hide it here.':
      '在这里隐藏后，新人指南仍保留在圈子菜单里。',
  'This circle has no guide yet.': '这个圈子还没有新人指南。',

  // The questions.
  'Tell {circle} what you are into. Your answers can give you roles and show you the channels that fit. You can change them any time.':
      '告诉 {circle} 你的兴趣。你的回答可以让你获得角色，并看到适合你的频道。你随时可以修改。',
  'Pick any': '多选',
  'Gives you: {roles}': '获得角色：{roles}',
  'Shows: {channels}': '显示频道：{channels}',
  'Answer the questions marked Required.': '请回答标有“必答”的问题。',
  'Could not save your answers. Try again.': '无法保存你的回答，请重试。',
  'You now have: {roles}': '你现在有这些角色：{roles}',

  // Tasks.
  'Read the rules': '阅读规则',
  'Visit a channel': '去一个频道看看',
  'Send a message': '发一条消息',
  'Set a profile picture': '设置头像',
  'Have a look around': '逛一逛',
  'Introduce yourself': '自我介绍',
  'Add a profile picture': '设置一张头像',

  // The editor.
  'Questions, tasks and greeting': '问题、任务和欢迎卡片',
  'Questions give new members roles, tasks show how far they have got, and the greeting announces them in a channel.':
      '问题可以让新成员获得角色，任务显示他们的进度，欢迎卡片会在频道里迎接新成员。',
  'Could not load the guide.': '无法加载新人指南。',
  'Member guide saved.': '新人指南已保存。',
  'Could not save the guide. Try again.': '无法保存新人指南，请重试。',
  'Every question needs its words.': '每个问题都要写上内容。',
  'Every question needs at least one option.': '每个问题至少要有一个选项。',
  'Every option needs its words.': '每个选项都要写上内容。',
  'Every task needs its words.': '每个任务都要写上内容。',
  'Pick the channel to visit.': '请选择要去的频道。',
  'A role you picked can no longer be given by an answer. It has management permissions, or ranks above one that does.':
      '你选的某个角色已不能通过回答发放：它有管理权限，或者排在有管理权限的角色之上。',
  'You cannot change this part of the guide.': '你无权修改新人指南的这一部分。',
  'Up to {count} questions. What a member picks can give them roles, which open channels you keep for that role. Only roles without management permissions can be given this way.':
      '最多 {count} 个问题。成员的选择可以让他们获得角色，你可以把某些频道只开放给这个角色。只有不含管理权限的角色才能这样发放。',
  'Tasks for new members': '新人任务',
  'Up to {count} tasks. New members see how many they have done.':
      '最多 {count} 个任务。新成员能看到自己完成了几个。',
  'Greeting': '欢迎卡片',
  'What are you into?': '你对什么感兴趣？',
  'Pick only one': '只能选一个',
  '{count} roles': '{count} 个角色',
  '{count} channels': '{count} 个频道',
  'Roles and channels': '角色和频道',
  'Gives these roles': '发放这些角色',
  'Points at these channels': '指向这些频道',
  'Only members who can manage roles can add roles here.':
      '只有能管理角色的成员才能在这里添加角色。',
  'Roles with a lock have management permissions and cannot be given.':
      '带锁的角色有管理权限，不能这样发放。',
  '{role}, has management permissions and cannot be given': '{role}，有管理权限，不能发放',
  'Task {number}': '任务 {number}',
  'Remove task': '删除任务',
  'What should they do?': '他们要做什么？',
  'Channel to visit': '要去的频道',
  'Channel to write in (optional)': '要发言的频道（可选）',
  'Any channel': '任意频道',
  'Greet new members': '迎接新成员',
  'A card in the channel greets each new member and has a Say hello button.':
      '频道里会出现一张卡片迎接每位新成员，卡片上有“打招呼”按钮。',
  'Sticker for Say hello': '打招呼用的贴纸',
  'A waving hand': '挥手表情',

  // The card in the channel.
  '{name} joined the circle': '{name} 加入了圈子',
  'Say hello': '打招呼',
  'Greeted': '已打招呼',
  'Welcome, {name}! 👋': '欢迎你，{name}！👋',
  'Could not say hello. Try again.': '无法打招呼，请重试。',

  // The audit log.
  '{target} chose roles through onboarding': '{target} 在新人引导中选择了角色',
};
