// Chinese for Watch Together (roadmap E4). The feature is 一起看 (and 一起听
// for songs); the person who starts it is the 主持人. Words that already have
// a Chinese text elsewhere ('Play', 'Pause', 'Loading…', 'Try again',
// 'Someone', 'You', 'Open in browser', 'Started by {name}') are not repeated.
const zhWatchTogether = <String, String>{
  // ------------------------------------------------------------ places
  'Watch together': '一起看',
  'Watching together': '正在一起看',
  'Watching options': '一起看选项',
  'What to watch': '看什么',
  // ------------------------------------------------------------ start
  'Everyone in the call plays it on their own device, and WeCord keeps you in step. Nothing is uploaded, downloaded or shared again.':
      '通话里的每个人都在自己的设备上播放，WeCord 只负责让大家进度一致。不会上传、下载或转发任何内容。',
  'Use headphones, or the sound goes round the call.': '请戴耳机，否则声音会被麦克风收进通话里。',
  'From this chat': '来自本聊天',
  'A link': '链接',
  'Could not start. Check your connection and try again.': '没能开始，请检查网络后重试。',
  'Could not load this chat’s files.': '没能加载这个聊天里的文件。',
  'No videos or songs in this chat yet. Send one first, or paste a link.':
      '这个聊天里还没有视频或歌曲。先发一个，或者粘贴链接。',
  'That does not look like a link.': '这看起来不是一个链接。',
  'Only links that start with https work.': '只支持以 https 开头的链接。',
  'Paste the full Bilibili link (it has bilibili.com/video/ in it), not the short one.':
      '请粘贴完整的哔哩哔哩链接（带有 bilibili.com/video/），不要用短链接。',
  'This link looks risky, so it can not be played together.':
      '这个链接看起来有风险，不能一起看。',
  'This link is not something a call can play. Try a YouTube or Bilibili video, or a link to an mp4 or mp3 file.':
      '通话里播放不了这个链接。可以试试 YouTube 或哔哩哔哩的视频，或者 mp4、mp3 文件的链接。',
  'Video or song link': '视频或歌曲链接',
  'YouTube, Bilibili, or a link to an mp4 or mp3 file':
      'YouTube、哔哩哔哩，或 mp4、mp3 文件的链接',
  'YouTube plays right here and is controlled together. Bilibili can not be controlled: everyone presses play, and you can send "play now" hints.':
      'YouTube 直接在这里播放，大家一起控制。哔哩哔哩无法远程控制：每个人自己点播放，你可以发“现在一起播放”的提示。',
  'In this app YouTube and Bilibili open in your browser, and you send "play now" hints. Links to mp4 and mp3 files play here and stay in step.':
      '在这个 App 里，YouTube 和哔哩哔哩会在浏览器中打开，你可以发“现在一起播放”的提示。mp4、mp3 文件的链接可以在这里播放并保持同步。',
  'Start watching': '开始一起看',
  // ------------------------------------------------------------ manage
  'Nothing is being watched.': '现在没有在一起看。',
  'Host: {name}': '主持人：{name}',
  'Anyone in the call can play, pause and move it.': '通话里的任何人都可以播放、暂停和拖动进度。',
  'Everyone can control': '大家都能控制',
  'Choose something else': '换一个',
  'Watch again': '重新一起看',
  'Stop watching on my screen': '在我的屏幕上不看了',
  'Stop for everyone': '为所有人结束',
  // ------------------------------------------------------------ the bar
  'The call is watching together, but not on your screen': '通话正在一起看，但你的屏幕上没有显示',
  'You started this': '你发起的',
  'Audio only is on, so the video is not loaded.': '已开启仅音频，所以没有加载视频。',
  'This is a link to a file on {site}. Loading it shows that site your connection.':
      '这是 {site} 上文件的链接。加载它会让该网站看到你的网络连接。',
  'Load it anyway': '仍然加载',
  'Load it': '加载',
  'The video could not be loaded on this device.': '这台设备加载不了这个视频。',
  'This device could not load it. You may not have access to the file, or it is a format your device can not play.':
      '这台设备加载不了。可能是你没有这个文件的权限，或者格式在你的设备上无法播放。',
  'This app can not play {site} inside the call. Open it in your browser and press play when you are told to.':
      '这个 App 没法在通话里播放 {site}。请在浏览器中打开，听到提示时再点播放。',
  'Everyone presses play themselves. Use the buttons to tell the call when.':
      '每个人自己点播放。用下面的按钮告诉大家什么时候开始。',
  'Everyone presses play themselves. Wait for the host to say when.':
      '每个人自己点播放。等主持人说什么时候开始。',
  'Tell everyone to play': '提醒大家播放',
  'Tell everyone to pause': '提醒大家暂停',
  '{name}: press play now': '{name}：现在一起点播放',
  '{name}: pause for a moment': '{name}：先暂停一下',
  'You control the playback': '由你控制播放',
  'Following {name}': '跟随 {name}',
  'the host': '主持人',
  'Playback position {time}': '播放进度 {time}',
  'Catch up': '追上进度',
  'Unmute for me': '为我取消静音',
  'Mute for me': '为我静音',
};
