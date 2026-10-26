// Chinese for advanced chat privacy (G6) and screenshot alerts (G7).
const zhChatPrivacy = <String, String>{
  // Lines in the chat.
  '{name} turned on advanced chat privacy': '{name} 开启了高级聊天隐私',
  '{name} turned off advanced chat privacy': '{name} 关闭了高级聊天隐私',
  '{name} took a screenshot of a view-once photo': '{name} 对阅后即焚的照片截了屏',
  '{name} took a screenshot of a view-once video': '{name} 对阅后即焚的视频截了屏',
  '{name} was recording the screen while a view-once photo was open':
      '{name} 在打开阅后即焚照片时正在录屏',
  '{name} was recording the screen while a view-once video was open':
      '{name} 在打开阅后即焚视频时正在录屏',

  // Banner, sheet and Settings.
  'Advanced chat privacy': '高级聊天隐私',
  'Advanced chat privacy is on': '高级聊天隐私已开启',
  'Forwarding, saving, copying and AI are off here. It cannot stop screenshots.':
      '这里已关闭转发、保存、复制和 AI。它无法阻止截屏。',
  'Opens the details': '打开详情',
  'Restrict sharing in this chat': '限制此聊天的内容外传',
  'Sharing is restricted': '内容外传已受限',
  'Anyone here can forward, save or copy messages': '这里的人都可以转发、保存或复制消息',
  'Group owners and admins can turn this on or off.': '群主和管理员可以开启或关闭。',
  'Only group owners and admins can change this.': '只有群主和管理员可以更改。',
  'The other person turned this on. It stays on until they turn it off.':
      '对方开启了它，在对方关闭之前会一直保持开启。',
  'You both turned this on. It stays on until you have both turned it off.':
      '你们都开启了它，要等你们都关闭后才会关闭。',
  'Either of you can turn this on. It stays on until you have both turned it off.':
      '你们任何一方都可以开启。要等你们都关闭后才会关闭。',
  'Could not change it. Check your connection and try again.':
      '无法更改。请检查网络连接后重试。',
  'Turned off by advanced chat privacy.': '已被高级聊天隐私关闭。',
  'What this does': '它会做什么',
  'What it cannot do': '它做不到什么',
  'Messages cannot be forwarded, merged into a forward or saved for later, and nobody can save them to a group album or group files.':
      '消息无法被转发、合并转发或收藏，也不能保存到群相册或群文件。',
  'Copying, translating, reading by AI and saving pictures and files to your device are off.':
      '复制、翻译、AI 阅读，以及把图片和文件保存到设备，都会被关闭。',
  'A data export leaves this chat\'s words and files out. The server refuses these, not just the app.':
      '数据导出不会包含这个聊天的文字和文件。这些限制由服务器执行，不只是应用里藏起了按钮。',
  'It cannot stop screenshots, screen recordings, a photo of the screen, or someone typing a message out again. Anyone who can read a message can keep a copy this way.':
      '它无法阻止截屏、录屏、拍下屏幕，或把消息重新打一遍。能看到消息的人，都可以用这些办法留下副本。',
  'Messages sent before it was turned on were already shared. Things already saved or forwarded stay where they are.':
      '开启之前发出的消息已经分享出去了。之前已保存或转发的内容不会被收回。',
  'Stop forwarding, saving and AI in a chat, and screenshot alerts':
      '禁止聊天内容被转发、保存和交给 AI，并说明截屏提醒',
  'Open a chat, choose More, then Advanced chat privacy. In a direct chat either of you can turn it on; in a group an owner or admin does.':
      '打开一个聊天，选择“更多”，再选“高级聊天隐私”。单聊中你们任何一方都可以开启；群聊由群主或管理员开启。',

  // Screenshot alerts (G7).
  'Screenshot alerts work on this device': '这台设备支持截屏提醒',
  'Screenshot alerts do not work on this device': '这台设备不支持截屏提醒',
  'This iPhone or iPad tells WeCord when you take a screenshot or record the screen while a view-once photo or video is open, and the sender is told. Alerts are best effort: they come after the fact, and they are not a promise that nobody kept a copy.':
      '打开阅后即焚的照片或视频时，如果你截屏或录屏，这台 iPhone 或 iPad 会告诉 WeCord，发送者也会收到提醒。提醒只是尽力而为：它在事后才出现，并不保证没有人留下副本。',
  'This device cannot tell when a screenshot is taken or the screen is recorded, so it sends no alerts and cannot warn you about others on it. Only iPhone and iPad can. A view-once photo you open here may be kept without the sender knowing.':
      '这台设备无法得知何时截屏或录屏，所以不会发出提醒。只有 iPhone 和 iPad 可以。你在这里打开的阅后即焚照片，可能被留存而发送者并不知情。',
  'You are told when a screenshot or screen recording is noticed on an iPhone or iPad. Computers, the web and other phones cannot be noticed, so no alert is not proof that nobody kept a copy.':
      '只有在 iPhone 或 iPad 上被察觉的截屏或录屏，你才会收到提醒。电脑、网页和其他手机上的无法察觉，所以没有提醒并不能证明没人留下副本。',
  'Screenshot taken': '已被截屏',
  'Screenshots taken': '已被多次截屏',
  'Screen recorded': '已被录屏',
  'Stop recording your screen, then open it. It can only be opened once.':
      '请先停止录屏再打开，它只能打开一次。',
  'If this device notices a screenshot or a screen recording, the sender is told.':
      '如果这台设备察觉到截屏或录屏，发送者会收到提醒。',
  'This device can\'t notice screenshots, so the sender is not told about them.':
      '这台设备无法察觉截屏，所以发送者不会收到提醒。',
  'Screenshot noticed. The sender is told.': '已察觉截屏，发送者会收到提醒。',
  'Screen recording noticed. The sender is told.': '已察觉录屏，发送者会收到提醒。',
  'Hidden while your screen is being recorded.': '录屏期间已隐藏。',
  'Screenshots and screen recordings can\'t be blocked. This device tells the sender if it notices one.':
      '截屏和录屏无法被阻止。这台设备察觉到时会通知发送者。',
  'Screenshots and screen recordings can\'t be blocked, and this device can\'t notice them.':
      '截屏和录屏无法被阻止，这台设备也无法察觉它们。',
};
