// Chinese for the app lock and chat lock (roadmap G2): the lock screen, the
// PIN keypad, locking a chat, hiding locked chats behind a secret code, and
// the Settings page.
const zhAppLock = <String, String>{
  // Settings.
  'App lock and locked chats': '应用锁与聊天锁',
  'Ask for Face ID, Touch ID or a PIN, and lock single chats':
      '用面容、指纹或密码解锁，也可以单独锁住某个聊天',
  '{count} locked': '已锁 {count} 个',
  'App lock': '应用锁',
  'Ask for a PIN when you open WeCord': '打开 WeCord 时需要输入密码',
  'Ask for Face ID, Touch ID or the passcode': '需要面容、指纹或设备密码',
  'Lock after': '锁定时间',
  'Immediately': '立即',
  'After 1 minute': '1 分钟后',
  'After 5 minutes': '5 分钟后',
  'After 15 minutes': '15 分钟后',
  'After 1 hour': '1 小时后',
  'How long WeCord may be out of sight before it asks again. On a computer, a window that is not in front counts as out of sight.':
      'WeCord 离开屏幕多久后再次要求解锁。在电脑上，不在最前面的窗口也算离开屏幕。',
  'Lock now': '立即锁定',
  'Change PIN': '修改密码',
  'Enter your current PIN': '输入当前密码',
  'PIN changed.': '密码已修改。',
  'This PIN opens WeCord after it was away.': '离开一段时间后，用这个密码重新打开 WeCord。',
  'Turn on the app lock': '开启应用锁',
  'Turn off the app lock': '关闭应用锁',
  'Set a passcode on this device first, then turn the app lock on.':
      '请先在这台设备上设置锁屏密码，再开启应用锁。',
  'WeCord asks for Face ID, Touch ID or your device passcode when you come back after the time you choose.':
      '离开超过你设定的时间后再回来，WeCord 会要求面容、指纹或设备密码。',
  'The PIN only covers the screen. It is not encryption, and it does not protect what this browser stores.':
      '这个密码只是挡住屏幕，不是加密，也保护不了浏览器里保存的数据。',
  'This device has no passcode, so WeCord keeps a PIN of its own. It only covers the screen; set a device passcode for better protection.':
      '这台设备没有设置锁屏密码，所以 WeCord 使用自己的密码。它只是挡住屏幕，建议设置设备密码以获得更好的保护。',
  'Could not change the lock. Check your connection and try again.':
      '无法修改锁定设置。请检查网络后重试。',

  // Locked chats.
  'Locked chats': '已锁定的聊天',
  'A locked chat asks to be unlocked, shows no message in the list, and its notifications show no sender and no text. WeCord AI questions and the daily digest leave it out.':
      '锁定的聊天需要解锁才能打开，列表里不显示消息，通知里不显示发送者和内容。WeCord AI 问答和每日速览也不会包含它。',
  'Hide locked chats': '隐藏已锁定的聊天',
  'Leave them out of the lists until you type the secret code in search':
      '在搜索框输入秘密代码之前，列表里不显示它们',
  'Secret code': '秘密代码',
  'Set': '已设置',
  'Not set': '未设置',
  'Change the secret code': '修改秘密代码',
  'Remove the secret code': '移除秘密代码',
  'Locked chats then stay in the list.': '之后已锁定的聊天会留在列表里。',
  'Type this code in the search box to show your hidden chats. It is kept on this device only.':
      '在搜索框输入这个代码，就能显示被隐藏的聊天。它只保存在这台设备上。',
  'Type it again': '再输入一次',
  'Use {min} to {max} characters.': '请使用 {min} 到 {max} 个字符。',
  'The two codes do not match.': '两次输入的代码不一致。',
  'No locked chats yet. Open a chat, choose More, then Lock chat. You can also press and hold a chat in the list.':
      '还没有锁定的聊天。打开聊天，点“更多”，再选“锁定聊天”；也可以在列表里长按聊天。',
  'Hidden chats': '隐藏的聊天',
  'Hide again': '重新隐藏',
  'No hidden chats.': '没有隐藏的聊天。',
  'Locked chat': '已锁定的聊天',
  'Lock chat': '锁定聊天',
  'Unlock chat': '解锁聊天',
  'Chat unlocked': '聊天已解锁',
  'Chat locked. It asks to be unlocked, and notifications hide it.':
      '聊天已锁定。打开需要解锁，通知里也不会显示内容。',

  // The lock screens.
  'WeCord is locked': 'WeCord 已锁定',
  'Unlock': '解锁',
  'Unlock WeCord': '解锁 WeCord',
  'Unlock this chat': '解锁这个聊天',
  'This chat is locked': '这个聊天已锁定',
  'Unlock with Face ID, Touch ID or your device passcode.': '用面容、指纹或设备密码解锁。',
  'Unlock it with Face ID, Touch ID or your device passcode.': '用面容、指纹或设备密码解锁。',
  'Too many tries. Use your device passcode, or wait a moment and try again.':
      '尝试次数过多。请使用设备密码，或稍等片刻再试。',
  'This device can no longer check who you are. Sign out to remove the lock, then sign in again.':
      '这台设备已经无法验证你的身份。请退出登录以移除锁定，然后重新登录。',
  'Set a PIN on this device to open your locked chats.':
      '请先在这台设备上设置密码，才能打开锁定的聊天。',
  'This PIN opens your locked chats on this device.': '这个密码用来在这台设备上打开锁定的聊天。',
  'Set a PIN': '设置密码',

  // The PIN keypad.
  'Enter your PIN': '输入密码',
  'Enter your PIN to open it.': '输入密码以打开。',
  'Choose a PIN': '设置密码',
  'Pick {count} digits you will remember.': '选择 {count} 位你记得住的数字。',
  'Enter it again': '再输入一次',
  'Type the same {count} digits to confirm.': '再输入相同的 {count} 位数字确认。',
  'The two PINs did not match. Start again.': '两次密码不一致，请重新设置。',
  'PIN: {filled} of {length} digits': '密码：已输入 {filled} / {length} 位',
  'Wrong PIN. 1 try left.': '密码错误，还剩 1 次机会。',
  'Wrong PIN. {count} tries left.': '密码错误，还剩 {count} 次机会。',
  'Too many tries. Try again in {time}.': '尝试次数过多，请在 {time} 后再试。',
  'Forgot your PIN?': '忘记密码了？',
  'Sign out to reset the lock?': '退出登录并重置锁定？',
  'Signing out removes the PIN and the lock from this device. Sign in again to set a new one. Your chats stay safe on your account.':
      '退出登录会移除这台设备上的密码和锁定。重新登录后可以设置新的密码。你的聊天仍然安全地保存在账号里。',

  // Notifications.
  'You have a new message': '你收到一条新消息',
};
