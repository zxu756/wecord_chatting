// Chinese for on-device AI (roadmap F8): the "Prefer on-device AI" row in
// Settings → AI, why the device's own model is not in use, and what an error
// from it says.
const zhOnDeviceAi = <String, String>{
  'Prefer on-device AI': '优先使用本机 AI',
  "Summaries, rewriting and translation run on this device when they can, so the text never leaves it and doesn't count against today's limit. When this device can't, the server does them.":
      '总结、改写和翻译会尽量在这台设备上完成：文字不会离开设备，也不占用今天的额度。这台设备做不了时，由服务器处理。',
  "This device can't run AI on its own. AI uses the server.":
      '这台设备无法在本机运行 AI，AI 功能由服务器处理。',
  'On-device AI needs iOS 26 or macOS 26 or later. Until then, AI uses the server.':
      '本机 AI 需要 iOS 26 或 macOS 26 及以上系统。在此之前，AI 功能由服务器处理。',
  "This device doesn't support Apple Intelligence, so AI uses the server.":
      '这台设备不支持 Apple 智能，AI 功能由服务器处理。',
  'Turn on Apple Intelligence in the system Settings to use it. Until then, AI uses the server.':
      '请在系统设置中打开 Apple 智能后使用。在此之前，AI 功能由服务器处理。',
  "The on-device model isn't ready yet. Until it is, AI uses the server.":
      '本机模型还没准备好。在此之前，AI 功能由服务器处理。',
  "The on-device model isn't available right now. AI uses the server.":
      '本机模型暂时不可用，AI 功能由服务器处理。',
  'That is too long for the on-device AI. Try a shorter text.':
      '这段内容对本机 AI 来说太长了，请换短一点的文字。',
  "The on-device AI wouldn't process that text.": '本机 AI 不愿处理这段文字。',
  "The on-device AI doesn't support that language.": '本机 AI 不支持这种语言。',
  'The on-device AI is busy right now. Try again in a moment.':
      '本机 AI 正忙，请稍后再试。',
  "The on-device AI couldn't do that. Try again, or turn off Prefer on-device AI in Settings.":
      '本机 AI 没能完成。请重试，或在设置中关闭「优先使用本机 AI」。',
};
