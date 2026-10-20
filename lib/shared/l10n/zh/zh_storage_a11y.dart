// Chinese for storage management (L2: Settings -> Storage) and accessibility
// 2.0 (L8: picture descriptions, the chat text size, captions on videos).
// 'Cancel', 'Clear', 'Close', 'Save', 'Remove', 'Off', 'Default', 'Files',
// 'Captions', 'Turn off captions' and 'Image: {name}' are already translated
// elsewhere. 'Messages' there means direct messages (私信), so the cached
// chats here are worded 'Cached messages'.
const zhStorageA11y = <String, String>{
  // Settings -> Chats.
  'Storage': '存储空间',
  'See what WeCord keeps on this device and clear it':
      '查看 WeCord 在这台设备上占了多少空间，并清理',

  // The storage page.
  'What takes space': '占用空间的内容',
  'By chat': '按聊天',
  'Automatic clean-up': '自动清理',
  'Clear all': '全部清除',
  'Clear all cached data': '清除全部缓存',
  'Clear all cached data?': '清除全部缓存？',
  'This removes the copies of chats, files and previews that WeCord keeps on this device. Nothing changes on the server or for anyone else. Anything you open again is downloaded again and uses data.':
      '这会清除 WeCord 在这台设备上保存的聊天、文件和预览图的副本。服务器和其他人那边都不会有任何变化。以后再打开的内容会重新下载，会用到流量。',
  'Clearing only removes copies on this device. Nothing changes on the server or for anyone else. Anything you open again is downloaded again and uses data.':
      '清理只会删除这台设备上的副本，服务器和其他人那边都不会有任何变化。以后再打开的内容会重新下载，会用到流量。',
  'Freed {size}.': '已释放 {size}。',
  'Nothing to clear.': '没有可清理的内容。',
  'WeCord keeps {size} on this device': 'WeCord 在这台设备上占用了 {size}',
  'This browser lets WeCord use up to {quota}; it uses {usage} now, including the app itself.':
      '这个浏览器最多允许 WeCord 使用 {quota}，现在已用 {usage}（包括应用本身）。',
  'A chat': '一个聊天',
  'Messages {size}': '消息 {size}',
  'Files {size}': '文件 {size}',
  'Files not tied to a chat': '不属于任何聊天的文件',
  'Kept before WeCord took note of where they came from':
      '在 WeCord 开始记录来源之前保存的',
  'Clear what is kept for {name}?': '清除「{name}」的本机缓存？',
  'This removes the cached messages, downloaded files and previews of this chat from this device. Nothing changes on the server or for anyone else. Files you open again are downloaded again and use data.':
      '这会从这台设备上清除这个聊天缓存的消息、已下载的文件和预览图。服务器和其他人那边都不会有任何变化。再打开的文件会重新下载，会用到流量。',

  // The kinds of data.
  'Cached messages': '缓存的消息',
  'Downloaded files': '已下载的文件',
  'Previews': '预览图',
  'Recognized text and captions': '识别的文字和字幕',
  'Wallpaper photos': '壁纸照片',
  'Waiting to send': '等待发送',
  'The chat list and the newest messages, to read offline': '聊天列表和最新的消息，用于离线查看',
  'Pictures, videos, voice messages and files you opened': '你打开过的图片、视频、语音消息和文件',
  'Small pictures of PDFs and videos': 'PDF 和视频的小预览图',
  'Text read from pictures, voice messages and videos, kept only here':
      '从图片、语音消息和视频中识别出的文字，只保存在这台设备上',
  'Photos you chose as chat wallpaper': '你选作聊天壁纸的照片',
  'Attachments that are still being sent. They are not cleared.':
      '还在发送中的附件，不会被清除。',
  'Clear cached messages?': '清除缓存的消息？',
  'Clear downloaded files?': '清除已下载的文件？',
  'Clear previews?': '清除预览图？',
  'Clear recognized text and captions?': '清除识别的文字和字幕？',
  'Clear wallpaper photos?': '清除壁纸照片？',
  'Chats are loaded from the server again the next time you open them. Until then you cannot read them offline. Messages waiting to be sent are kept.':
      '下次打开聊天时会重新从服务器加载。在那之前无法离线查看。等待发送的消息会保留。',
  'Pictures, videos and files you open again are downloaded again, which uses data.':
      '再次打开的图片、视频和文件会重新下载，会用到流量。',
  'Previews are drawn again the next time you see the file, which uses data.':
      '下次看到这个文件时会重新生成预览图，会用到流量。',
  'Text read from pictures, voice messages and videos is made again the next time you ask for it.':
      '下次需要时，会重新识别图片、语音消息和视频里的文字。',
  'Wallpaper photos are downloaded again the next time a chat shows them, which uses data.':
      '下次有聊天用到壁纸时会重新下载，会用到流量。',

  // Automatic clean-up.
  'Remove media not opened for': '清理这么久没打开过的媒体',
  '{days} days': '{days} 天',
  'Downloaded files, previews and recognized text you have not opened for this long are removed by themselves. Messages stay. Files you open again are downloaded again.':
      '这么久没打开过的已下载文件、预览图和识别的文字会被自动清理。消息会保留。再打开的文件会重新下载。',
  'Files, previews and recognized text not opened for {days} days are removed by themselves, at most once a day. Messages stay. Files you open again are downloaded again.':
      '超过 {days} 天没打开过的文件、预览图和识别的文字会被自动清理，每天最多一次。消息会保留。再打开的文件会重新下载。',

  // Picture descriptions.
  'ALT': '描述',
  'Describe picture': '描述图片',
  'Describe pictures': '描述图片',
  'Described': '已描述',
  '{done} of {total} described': '已描述 {done}/{total} 张',
  'Describe this picture': '描述这张图片',
  'Describe these pictures': '描述这些图片',
  'Say what is in the picture for people who cannot see it, such as someone using a screen reader. Mention who or what it shows and any text in it.':
      '为看不到图片的人写下图片里有什么，比如使用读屏软件的人。说说图片里是谁或什么，以及图中的文字。',
  'Description of picture {number}': '第 {number} 张图片的描述',
  'picture-description|Description': '描述',
  'A dog asleep on a red sofa': '一只狗睡在红色沙发上',
  'Picture description': '图片描述',

  // Chat text size.
  'Chat text size': '聊天字号',
  'The size of messages in chats, on top of the text size in your device settings.':
      '聊天里消息的字号，在设备设置的字号基础上再调整。',
  'This is how messages look.': '消息就是这个样子。',
  'chat-text-size|Small': '小',
  'chat-text-size|Large': '大',
  'chat-text-size|Larger': '更大',
  'chat-text-size|Largest': '最大',

  // Captions on videos.
  'Making captions on this device…': '正在这台设备上生成字幕…',
  'There is no speech in this video.': '这段视频里没有人说话。',
  'Speech recognition is turned off for WeCord. Turn it on in Settings to get captions.':
      'WeCord 的语音识别已关闭。到系统设置里打开后才能生成字幕。',
  "This device can't make captions in this language without sending the sound away, so there are none.":
      '这台设备不把声音发到别处就无法为这种语言生成字幕，所以没有字幕。',
  "The sound of this video can't be read here.": '这段视频的声音在这里无法读取。',
  'Captions could not be made.': '无法生成字幕。',
};
