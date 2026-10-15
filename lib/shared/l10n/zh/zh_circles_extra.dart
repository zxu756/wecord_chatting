// Chinese for the circles batch: announcement channels, circle templates,
// circle tags and bots.
const zhCirclesExtra = <String, String>{
  // Announcement channels.
  'Announcement channel': '公告频道',
  'Posts here can be published to channels that follow it.':
      '这里的帖子可以发布到关注它的频道。',
  'Turn off announcements?': '关闭公告功能？',
  'Channels that follow #{name} stop receiving its posts, and their follows are removed.':
      '关注 #{name} 的频道将不再收到它的帖子，这些关注也会被移除。',
  'Turn off': '关闭',
  'Could not change the channel. Try again.': '无法修改频道，请重试。',
  'Unfollow channel': '取消关注频道',
  'Stop receiving posts from #{channel} in {circle}?':
      '不再接收 {circle} 中 #{channel} 的帖子？',
  'Unfollow': '取消关注',
  'Could not unfollow. Try again.': '无法取消关注，请重试。',
  'Followed channels': '已关注的频道',
  'This channel follows no announcement channels. Follow one from its channel header.':
      '此频道没有关注任何公告频道。可在公告频道的顶部栏关注它。',
  'Posts published in these channels appear here.': '这些频道发布的帖子会出现在这里。',
  '{circle} · followed by {name}': '{circle} · 由 {name} 关注',
  '#{source} now posts to #{target} in {circle}.':
      '#{source} 的帖子现在会发到 {circle} 的 #{target}。',
  'Could not follow the channel. Try again.': '无法关注该频道，请重试。',
  'Follow #{name}': '关注 #{name}',
  'Choose where its published posts should appear. You need to manage webhooks in that channel.':
      '选择发布的帖子要出现在哪里。你需要在该频道拥有管理 Webhook 的权限。',
  'Could not load your channels.': '无法加载你的频道。',
  'None of your circles has a text channel where you manage webhooks.':
      '你的圈子里没有你能管理 Webhook 的文字频道。',
  'Following': '已关注',
  '{author} · from #{channel} · {circle}':
      '{author} · 来自 #{channel} · {circle}',
  'Published': '已发布',
  'Follow': '关注',
  'Publish': '发布',
  'Published. No channels follow this one yet.': '已发布。目前还没有频道关注这里。',
  'Published to 1 channel.': '已发布到 1 个频道。',
  'Published to {count} channels.': '已发布到 {count} 个频道。',
  'Could not publish the message. Try again.': '无法发布消息，请重试。',
  // Circle settings and templates.
  'Circle settings': '圈子设置',
  'Could not load the circle.': '无法加载圈子。',
  'Template': '模板',
  'Share the layout of this circle (channels, categories, roles and permissions, but no messages or members) as a code others can create a circle from.':
      '把这个圈子的布局（频道、分类、角色和权限，不含消息和成员）分享为一个代码，别人可以用它创建圈子。',
  'Could not load the template.': '无法加载模板。',
  'Create template': '创建模板',
  '{channels} channels · {roles} roles · used {count} times':
      '{channels} 个频道 · {roles} 个角色 · 已使用 {count} 次',
  'Copy code': '复制代码',
  'Template code copied.': '模板代码已复制。',
  'Sync template': '同步模板',
  'Template synced with the circle.': '模板已与圈子同步。',
  'Could not sync the template. Try again.': '无法同步模板，请重试。',
  'Could not create the template. Try again.': '无法创建模板，请重试。',
  'Delete template': '删除模板',
  'Delete "{name}"? Its code stops working. Circles already created from it stay as they are.':
      '删除"{name}"？它的代码将失效，已用它创建的圈子不受影响。',
  'Could not delete the template. Try again.': '无法删除模板，请重试。',
  'Template name is required.': '请输入模板名称。',
  'Template name': '模板名称',
  'Description (optional)': '描述（可选）',
  'Use a template code': '使用模板代码',
  'Create from a template': '从模板创建',
  'Template code': '模板代码',
  'Enter a template code.': '请输入模板代码。',
  'No template has this code.': '没有使用此代码的模板。',
  'Continue': '继续',
  'Back': '返回',
  'Create circle': '创建圈子',
  'Could not create the circle. Try again.': '无法创建圈子，请重试。',
  'From {circle}': '来自 {circle}',
  // Circle tags.
  'Circle tag': '圈子标签',
  'Members can show this tag next to their name everywhere. Leaving the circle removes it.':
      '成员可以在自己的名字旁显示这个标签。离开圈子后标签会被移除。',
  'Tag': '标签',
  '2 to 4 characters': '2 到 4 个字符',
  'Badge': '徽章',
  'Save tag': '保存标签',
  'Turn off tag': '关闭标签',
  'A tag is 2 to 4 characters.': '标签为 2 到 4 个字符。',
  'Use letters and digits only.': '只能使用字母和数字。',
  'Circle tag saved.': '圈子标签已保存。',
  'Circle tag removed.': '圈子标签已关闭。',
  'Could not save the tag. Try again.': '无法保存标签，请重试。',
  'Show the tag of one of your circles next to your name': '在你的名字旁显示一个圈子的标签',
  'Could not change your tag. Try again.': '无法更改你的标签，请重试。',
  'Only circles you are in that turned on a tag are listed. Leaving the circle removes it.':
      '这里只列出你加入且开启了标签的圈子。离开圈子后标签会被移除。',
  'Could not load your circles.': '无法加载你的圈子。',
  'No tag': '不显示标签',
  'None of your circles has a tag yet.': '你的圈子都还没有标签。',
};
