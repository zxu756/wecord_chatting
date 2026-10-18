// Chinese for edit history (编辑历史): tapping "edited" on a message, the
// history sheet and its menu entry, plus the circle's edit time limit.
// 'edited' (已编辑), 'Retry', 'No limit', '15 minutes', '1 hour' and '24 hours'
// are already translated elsewhere.
const zhEditHistory = <String, String>{
  'Edit history': '编辑历史',
  'Edited, double tap to see history': '已编辑，点两下查看历史',
  'Could not load the edit history.': '无法加载编辑历史。',
  'Current': '当前版本',
  'Original': '原文',
  'Version {number}': '第 {number} 版',
  'No earlier versions were saved for this message.': '这条消息没有保存更早的版本。',
  // Circle settings: the edit time limit.
  'Editing messages': '编辑消息',
  'Edit time limit': '编辑时限',
  'How long members can edit what they sent': '成员发出的消息可以编辑多久',
  'After this time, members can no longer edit a message they sent. Deleting stays possible. Earlier versions of an edited message stay visible to everyone in the chat.':
      '超过这个时间后，成员不能再编辑自己发出的消息，但仍可以删除。编辑过的消息的旧版本，聊天里的所有人都能看到。',
  "Couldn't save the time limit. Try again.": '无法保存时限，请重试。',
  '{actor} set the edit time limit to {time}': '{actor} 把编辑时限设为 {time}',
  '{actor} removed the edit time limit': '{actor} 取消了编辑时限',
  // Raised by the server.
  'The time to edit this message has passed': '这条消息已过了可编辑的时间',
  'Choose no limit, 15 minutes, 1 hour or 24 hours': '请选择不限、15 分钟、1 小时或 24 小时',
  'Only members who manage the circle can change the edit time limit':
      '只有管理圈子的成员才能更改编辑时限',
};
