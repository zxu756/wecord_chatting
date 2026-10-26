// Chinese for the protection of chats saved on the device (roadmap G8) and the
// search through them without a connection (L3): the card at the end of the
// Storage page and the notice above offline search results.
const zhLocalData = <String, String>{
  'Protection on this device': '本机保护',
  'Saved chats are encrypted': '已保存的聊天已加密',
  'Cached messages, recognized text, drafts and the offline search index are encrypted. The key is kept in the system Keychain, not in WeCord\'s files, and is not copied to backups or other devices. Signing out deletes the key and the saved chats.':
      '缓存的消息、识别出的文字、草稿和离线搜索索引都已加密。密钥保存在系统钥匙串里，不在 WeCord 的文件中，也不会复制到备份或其他设备。退出登录会删除密钥和已保存的聊天。',
  'Encrypted in this browser, with limits': '已在此浏览器中加密，但有局限',
  'Saved messages, recognized text, drafts and the offline search index are encrypted with a key your browser makes and will not hand out. That keeps the saved data from being read as plain text, but it is weaker than on the phone or Mac: the key sits in the same browser profile, and pages or extensions running in this browser can still use it. On a shared computer, sign out when you are done; that deletes the key and the saved chats.':
      '已保存的消息、识别出的文字、草稿和离线搜索索引，用浏览器生成且不会交出的密钥加密。这样保存的数据不会以明文被读到，但保护不如手机或 Mac：密钥与数据在同一个浏览器配置文件里，运行在此浏览器中的网页或扩展仍可使用它。在共用电脑上，用完请退出登录，这会删除密钥和已保存的聊天。',
  'Encrypted for this session only': '仅在本次使用期间加密',
  'The key is not kept anywhere, so saved chats cannot be read after the app closes.':
      '密钥不会保存在任何地方，所以关闭应用后无法再读取已保存的聊天。',
  'Saved chats are switched off': '聊天保存已关闭',
  'The key that protects saved chats could not be opened on this device, so WeCord keeps no copy of your chats here and nothing is stored in plain text. You can still use WeCord while you are online.':
      '这台设备上无法打开保护已保存聊天的密钥，所以 WeCord 不会在这里保留聊天副本，也不会以明文存储任何内容。联网时仍可正常使用 WeCord。',
  'Downloaded pictures, videos and files are kept as ordinary files and are not encrypted by WeCord. Clear them above, or rely on your device\'s own protection (screen lock, FileVault).':
      '下载的图片、视频和文件以普通文件保存，WeCord 不会对它们加密。可以在上方清除它们，或依靠设备自带的保护（锁屏、FileVault）。',
  'Search without a connection': '无网络时的搜索',
  'Without a connection, search looks through the newest messages saved on this device. The search index is encrypted the same way, and is emptied as messages are deleted or expire, or when you clear cached messages.':
      '没有网络时，搜索会在这台设备上保存的最新消息里查找。搜索索引以同样的方式加密，消息被删除或过期、或你清除缓存消息时，索引也会随之清空。',
  'Offline results': '离线结果',
  'No connection. These come only from the newest messages saved on this device.':
      '当前没有网络。这些结果只来自这台设备上保存的最新消息。',
};
