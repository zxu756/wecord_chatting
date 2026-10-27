// Chinese for webhook cards, RSS feeds and GitHub connections (roadmap I6):
// the channel settings sections, their dialogs and the audit log lines.
// 'Cancel', 'Save', 'Done', 'Pause', 'Paused', 'Name' and 'Comments' already
// have a Chinese text elsewhere.
const zhIntegrations = <String, String>{
  // Cards on a message
  'Opens {site}': '打开 {site}',
  // Channel settings: feeds
  'RSS feeds': 'RSS 订阅',
  'Follow a feed': '订阅一个 RSS',
  'Follow feed': '订阅',
  'Feed address': 'RSS 地址',
  'Feed actions': '订阅操作',
  'Stop following': '取消订阅',
  'Stop following "{name}"? Messages it posted stay.':
      '取消订阅「{name}」？它已发的消息会保留。',
  'No feeds yet.': '还没有订阅。',
  'Could not load the feeds.': '无法加载订阅。',
  'Could not follow the feed. Try again.': '无法订阅，请重试。',
  'Could not change the feed. Try again.': '无法修改订阅，请重试。',
  'Could not remove the feed. Try again.': '无法取消订阅，请重试。',
  'Use an address that starts with https://.': '请填写以 https:// 开头的地址。',
  'Use a public address that starts with https://.':
      '请填写以 https:// 开头、可公开访问的地址。',
  'This circle or channel has all it can have. Remove one first.':
      '这个圈子或频道的数量已达上限，请先移除一个。',
  'This channel already follows that feed.': '这个频道已经订阅了该 RSS。',
  'You can no longer manage this channel.': '你已无权管理这个频道。',
  'Last post {time}': '上次发布 {time}',
  'Waiting for the first read': '等待首次读取',
  'Nothing posted yet': '还没有发布内容',
  'New items of a blog or news feed are posted here, a few at a time, about '
          'every 15 minutes. Nothing is posted for what the feed already had.':
      '博客或新闻 RSS 的新内容会发到这里，大约每 15 分钟检查一次，每次只发几条。订阅之前已有的内容不会发。',
  // Why a feed could not be read
  'The feed could not be read.': '无法读取这个 RSS。',
  'The site answered with an error ({code}).': '网站返回了错误（{code}）。',
  'That address is not a feed.': '这个地址不是 RSS。',
  "The feed's text is not valid.": 'RSS 内容格式不正确。',
  'The site took too long to answer.': '网站响应太慢。',
  'The feed is too big.': 'RSS 内容太大。',
  'The site asked us to slow down.': '网站要求我们放慢访问。',
  // Paused
  'Resume': '恢复',
  'Paused: it kept failing. Resume to try again.': '已暂停：连续失败太多次。恢复后会重试。',
  'Paused: the person who added it can no longer post here.':
      '已暂停：添加它的人已不能在这里发言。',
  'Paused: the person who added it left WeCord.': '已暂停：添加它的人已离开 WeCord。',
  // Channel settings: GitHub
  'GitHub': 'GitHub',
  'Connect a repository': '连接代码仓库',
  'Connection actions': '连接操作',
  'Name and events': '名称与事件',
  'New secret': '新密钥',
  'Make a new secret': '生成新密钥',
  'Name the connection.': '请给这个连接起个名字。',
  'Choose at least one event.': '至少选择一个事件。',
  'No repositories yet.': '还没有连接仓库。',
  'Could not load the connections.': '无法加载连接。',
  'Could not connect GitHub. Try again.': '无法连接 GitHub，请重试。',
  'Could not save the changes. Try again.': '无法保存修改，请重试。',
  'Could not change the connection. Try again.': '无法修改连接，请重试。',
  'Could not make a new secret. Try again.': '无法生成新密钥，请重试。',
  'Could not disconnect. Try again.': '无法断开连接，请重试。',
  'Disconnect GitHub': '断开 GitHub',
  'Disconnect "{name}"? GitHub can no longer post here. Messages it posted '
          'stay.':
      '断开「{name}」？GitHub 将不能再在这里发消息，已发的消息会保留。',
  'The current secret of "{name}" stops working right away. GitHub needs the '
          'new one.':
      '「{name}」当前的密钥会立即失效，需要在 GitHub 里换成新密钥。',
  'Pushes': '推送',
  'Pull requests': '合并请求',
  'Issues': '议题',
  'Releases': '发行版',
  'Workflow runs': '工作流运行',
  'Nothing received yet': '还没有收到内容',
  'GitHub connected': 'GitHub 已连接',
  'Payload URL': '回调地址',
  'Secret': '密钥',
  'No secret to show.': '没有可显示的密钥。',
  'Secret copied.': '密钥已复制。',
  'Copy the secret now: it is shown only once. Anyone with it can post in '
          'this channel as GitHub.':
      '请现在复制密钥：它只显示这一次。拿到它的人可以冒充 GitHub 在这个频道发消息。',
  'In the repository: Settings, Webhooks, Add webhook. Paste the URL and the '
          'secret, set Content type to application/json, and pick the events '
          'you chose here. Press a value to copy it.':
      '在仓库里依次打开：Settings、Webhooks、Add webhook。粘贴地址和密钥，Content type 选 application/json，并勾选和这里一致的事件。点一下数值即可复制。',
  'GitHub posts pushes, pull requests, issues and releases here. You add the '
          "webhook in the repository's settings with the address and secret "
          'shown once after connecting.':
      'GitHub 会把推送、合并请求、议题和发行版发到这里。连接后会显示一次地址和密钥，请到仓库设置里添加 webhook。',
  // Audit log
  '{actor} followed feed {target}': '{actor} 订阅了 RSS {target}',
  '{actor} followed feed {target} in {channel}':
      '{actor} 在 {channel} 订阅了 RSS {target}',
  '{actor} paused feed {target}': '{actor} 暂停了 RSS {target}',
  '{actor} paused feed {target} in {channel}':
      '{actor} 暂停了 {channel} 的 RSS {target}',
  '{actor} resumed feed {target}': '{actor} 恢复了 RSS {target}',
  '{actor} resumed feed {target} in {channel}':
      '{actor} 恢复了 {channel} 的 RSS {target}',
  '{actor} stopped following feed {target}': '{actor} 取消订阅了 RSS {target}',
  '{actor} stopped following feed {target} in {channel}':
      '{actor} 取消订阅了 {channel} 的 RSS {target}',
  '{actor} connected GitHub repository {target}':
      '{actor} 连接了 GitHub 仓库 {target}',
  '{actor} connected GitHub repository {target} in {channel}':
      '{actor} 在 {channel} 连接了 GitHub 仓库 {target}',
  '{actor} changed GitHub connection {target}':
      '{actor} 修改了 GitHub 连接 {target}',
  '{actor} made a new secret for GitHub connection {target}':
      '{actor} 为 GitHub 连接 {target} 生成了新密钥',
  '{actor} paused GitHub connection {target}': '{actor} 暂停了 GitHub 连接 {target}',
  '{actor} resumed GitHub connection {target}':
      '{actor} 恢复了 GitHub 连接 {target}',
  '{actor} disconnected GitHub repository {target}':
      '{actor} 断开了 GitHub 仓库 {target}',
  '{actor} disconnected GitHub repository {target} in {channel}':
      '{actor} 断开了 {channel} 的 GitHub 仓库 {target}',
};
