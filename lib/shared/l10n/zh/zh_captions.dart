// Chinese for call captions and the call recap (E1). 'Summary', 'Decisions',
// 'Action items', 'Title', 'You', 'Someone', 'Allow', 'Not now', 'Try again',
// 'Cancel' and 'Turn off' are already translated elsewhere.
const zhCaptions = <String, String>{
  // The button and the sheets.
  'Captions': '字幕',
  'Caption settings': '字幕设置',
  'Turn on captions': '开启字幕',
  'Turn on captions?': '开启字幕？',
  'Turn off captions': '关闭字幕',
  'Turn off captions?': '关闭字幕？',
  'Captions are off.': '字幕已关闭。',
  'Everyone in the call sees that captions are on.': '通话里的所有人都会看到字幕已开启。',
  "Each person's device turns what they say into text. Only the text is shared with the call.":
      '每个人的设备只把自己说的话转成文字，通话里共享的只有文字。',
  'Anyone can choose not to share their captions.': '每个人都可以选择不共享自己的字幕。',
  'Nothing is recorded and no audio is saved. The words stay in memory on the devices until the call ends, unless you write a recap.':
      '不录音，也不保存任何音频。文字只留在各设备的内存里，通话结束就没了；除非你生成纪要。',
  'Share my captions': '共享我的字幕',
  'Your device turns what you say into text and shares the text with the call. Your voice is not recorded.':
      '你的设备会把你说的话转成文字，并把文字共享给通话。你的声音不会被录下来。',
  "Your device can't make captions in this language.": '你的设备不支持这种语言的字幕。',
  'Language I speak': '我说的语言',
  'Hide captions on my screen': '在我的屏幕上隐藏字幕',
  'Show captions on my screen': '在我的屏幕上显示字幕',
  'Transcript': '文字记录',
  'Nothing has been said yet.': '还没有人说话。',
  'This transcript is only on your device, in memory. It is gone when the call ends.':
      '这份文字记录只在你的设备内存里，通话结束就没了。',

  // The caption bar.
  'Captions are on': '字幕已开启',
  'Captions are on · {name}': '字幕已开启 · {name}',
  'Captions are on, but hidden here': '字幕已开启，但在这里隐藏了',
  'Show': '显示',
  'Waiting for someone to speak…': '等人说话…',
  "You're not sharing your captions.": '你没有共享自己的字幕。',
  "Your device can't make captions in this language. You still see everyone else's.":
      '你的设备不支持这种语言的字幕，但你仍能看到别人的字幕。',
  'Speech recognition or the microphone is turned off for WeCord, so your captions are not shared. Turn it on in Settings, then try again.':
      '“语音识别”或麦克风对 WeCord 是关闭的，所以你的字幕没有共享。请在设置里打开后再试。',
  'To make captions of you, your browser sends what you say to its speech service. Allow that to share your captions.':
      '要生成你的字幕，浏览器会把你说的话发给它的语音服务。允许后才会共享你的字幕。',
  "To make captions of you in this language, Apple's speech service listens to what you say. Allow that to share your captions.":
      '要生成这种语言的字幕，需要 Apple 的语音服务来听你说的话。允许后才会共享你的字幕。',
  "{name}'s device doesn't support captions": '{name} 的设备不支持字幕',
  "{names}: their devices don't support captions": '{names} 的设备不支持字幕',
  "{names} and {count} more: their devices don't support captions":
      '{names} 等 {count} 人的设备不支持字幕',

  // Turning off, leaving and the recap.
  'Write a recap before you leave?': '离开前生成纪要吗？',
  'The words from the captions are only on your device and are gone when the call ends. A recap turns them into key points, decisions and to-dos that you can save as a note.':
      '字幕里的文字只在你的设备上，通话结束就没了。纪要会把它们整理成要点、决定和待办，可以存成笔记。',
  'Just leave': '直接离开',
  'Write a recap and leave': '生成纪要并离开',
  'Turn off and write a recap': '关闭并生成纪要',
  'Call recap': '通话纪要',
  'Call recap · {date}': '通话纪要 · {date}',
  'Writing the recap…': '正在生成纪要…',
  'There was not enough in the call to write a recap.': '通话内容太少，写不出纪要。',
  'WeCord AI wrote this from the captions people shared. Speech recognition can mishear, so check it before you share it. Nothing is saved until you save it.':
      'WeCord AI 根据大家共享的字幕写了这份纪要。语音识别可能听错，分享前请先检查。你保存之前不会存下任何东西。',
  'The call was long, so part of the middle was not read.': '通话太长，中间的一部分没有读到。',
  'Save as a note and share in the chat': '存成笔记并分享到聊天',
  'Saved and shared': '已保存并分享',
  'Make tasks from the action items': '把待办变成任务',
  'Recap saved as a note and shared in the chat.': '纪要已存成笔记并分享到聊天。',
  'Could not save the recap. Try again.': '无法保存纪要，请再试一次。',
  'The note is saved, but it could not be shared in the chat. Try again.':
      '笔记已保存，但无法分享到聊天，请再试一次。',
  'From the captions of a call on {date}, {count} people spoke.':
      '根据 {date} 的一次通话字幕整理，共有 {count} 人发言。',
  'From the captions of a call on {date}.': '根据 {date} 的一次通话字幕整理。',
};
