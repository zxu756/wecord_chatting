// Voice settings, push to talk, per-person volume, voice moderation and
// text chat in voice channels.
const zhVoiceMore = <String, String>{
  // Settings → Voice
  'Push to talk, noise suppression and echo cancellation': '按键说话、降噪和回声消除',
  'Input mode': '输入模式',
  'Voice activity': '语音激活',
  'Push to talk': '按键说话',
  'Hold the talk button in the voice view to speak. Your microphone stays quiet otherwise.':
      '在语音界面按住说话按钮即可发言，松开后麦克风保持静音。',
  'Hold your push to talk key to speak, anywhere in the app. Without a key, hold the talk button in the voice view.':
      '在应用内任意位置按住按键说话键即可发言。未设置按键时，可在语音界面按住说话按钮。',
  'Your microphone sends whenever you are not muted.': '未静音时，麦克风会一直发送声音。',
  'Push to talk key': '按键说话键',
  'Not set': '未设置',
  'Set key': '设置按键',
  'Change key': '更换按键',
  'Press the key to hold while talking.': '请按下说话时要按住的键。',
  'Space': '空格',
  'Key {id}': '按键 {id}',
  'Audio processing': '音频处理',
  'Noise suppression': '降噪',
  'Filters out background noise.': '过滤背景噪音。',
  'Echo cancellation': '回声消除',
  'Keeps others from hearing themselves through your speakers.':
      '避免其他人从你的扬声器里听到自己的声音。',
  'Automatic gain control': '自动增益控制',
  'Evens out how loud your voice sends.': '让你发出的音量保持平稳。',
  'User volumes': '用户音量',
  'Right-click (or long-press) someone in a voice channel or call to change how loud they are for you. Only you hear the difference.':
      '在语音频道或通话中右键（或长按）某人，即可调整你听到的对方音量。只有你会听到变化。',
  'Reset volumes for {count} people': '重置 {count} 人的音量',

  // Voice view
  'Hold to talk': '按住说话',
  'Talking…': '正在说话…',
  'User volume': '用户音量',

  // Text chat in voice channels
  'Show chat': '显示聊天',
  'Hide chat': '隐藏聊天',

  // Voice moderation
  'Mute members': '静音成员',
  'Server mute members ranked below them in voice channels.':
      '在语音频道中对身份组低于自己的成员进行服务器静音。',
  'Deafen members': '关闭成员声音',
  'Server deafen members ranked below them in voice channels.':
      '在语音频道中为身份组低于自己的成员关闭声音。',
  'Move members': '移动成员',
  'Move members ranked below them between voice channels, disconnect them, and join full channels.':
      '在语音频道之间移动身份组低于自己的成员、断开其连接，并可加入已满的频道。',
  'Server mute': '服务器静音',
  'Server deafen': '服务器关闭声音',
  'Server muted': '已被服务器静音',
  'Server deafened': '已被服务器关闭声音',
  'Move to…': '移动到…',
  'Move {name} to': '将 {name} 移动到',
  'Could not change their voice state.': '无法更改对方的语音状态。',
  'This voice channel is full.': '此语音频道已满。',
  'User limit': '人数上限',
  'How many people can be in this voice channel at once. Members who can move members can still join.':
      '此语音频道同时可容纳的人数。拥有移动成员权限的成员仍可加入。',
  'No limit': '不限',
  '1 person': '1 人',
  '{count} people': '{count} 人',
  'Could not change the user limit.': '无法更改人数上限。',
  'Full: {count} of {limit}': '已满：{count}/{limit}',
  '{count} of {limit}': '{count}/{limit}',
  '{actor} set the user limit of {target} to {limit}':
      '{actor} 将 {target} 的人数上限设为 {limit}',
  '{actor} removed the user limit of {target}': '{actor} 取消了 {target} 的人数上限',
  '{actor} server muted {target}': '{actor} 对 {target} 进行了服务器静音',
  '{actor} server unmuted {target}': '{actor} 取消了 {target} 的服务器静音',
  '{actor} server deafened {target}': '{actor} 在服务器上关闭了 {target} 的声音',
  '{actor} server undeafened {target}': '{actor} 恢复了 {target} 的服务器声音',
  '{actor} disconnected {target} from voice': '{actor} 将 {target} 断开了语音连接',
  '{actor} moved {target} to {channel}': '{actor} 将 {target} 移动到 {channel}',
  '{actor} moved {target} to another voice channel':
      '{actor} 将 {target} 移动到另一个语音频道',
};
