// Chinese for Moments 2.0 (朋友圈 2.0): 提醒谁看, 置顶 (three at most), a
// 3-minute video, sending a Moment to a chat as a card (朋友圈卡片), a picture
// or sticker on a comment, and descriptions of pictures (图片描述, shared with
// the chat's "Describe picture"). "Moment" reads 朋友圈 everywhere.
const zhMoments2 = <String, String>{
  // Reminders ("Remind who to read").
  'Remind who to read': '提醒谁看',
  'They get a notification. Only friends who can see this Moment are listed.':
      '对方会收到通知。这里只列出能看到这条朋友圈的好友。',
  'Nobody can see this Moment.': '没有人能看到这条朋友圈。',
  'You can remind up to {count} friends.': '最多可以提醒 {count} 位好友。',
  'Reminded: {names}': '已提醒：{names}',
  'Reminded you to read this': '提醒你看',
  'reminded you to read their Moment': '提醒你看TA的朋友圈',

  // Pinning.
  'Pin to my page': '置顶到我的朋友圈',
  'Unpin from my page': '取消置顶',
  'Pinned to your page': '已置顶到你的朋友圈',
  'Unpinned from your page': '已取消置顶',
  'You can pin up to {count} Moments. Unpin one first.':
      '最多只能置顶 {count} 条朋友圈，请先取消一条。',
  'Could not update the pin. Try again.': '无法更改置顶，请重试。',

  // A longer video.
  'That video is longer than 3 minutes. Choose a shorter one.':
      '这段视频超过 3 分钟，请选择更短的视频。',
  'Or add one video of up to 3 minutes and 50 MB.':
      '也可以添加一段不超过 3 分钟、50 MB 的视频。',

  // Sending a Moment to a chat.
  'Share to a chat': '发送到聊天',
  'Moment sent': '朋友圈已发送',
  'Could not send the Moment. Try again.': '无法发送这条朋友圈，请重试。',
  'Moment from {name}': '{name}的朋友圈',
  'Moment from {name}: {text}': '{name}的朋友圈：{text}',
  'Opens the Moment': '打开这条朋友圈',
  'Open Moment': '打开朋友圈',
  "Can't view this Moment": '无法查看这条朋友圈',
  'Photos': '照片',

  // A picture or sticker on a comment.
  'Add a picture or sticker': '添加图片或表情',
  'Described: {description}': '描述：{description}',
  '{name} replied to {other}': '{name}回复了{other}',
  '{name} sent a picture': '{name}发了一张图片',
  '{name} sent a picture: {description}': '{name}发了一张图片：{description}',
  '[Picture]': '[图片]',

  // Describing the photos of a Moment.
  'Describe photo {number}': '描述第 {number} 张照片',
  'Photo {number} described: {description}': '第 {number} 张照片，描述：{description}',
  '{label}: {description}': '{label}：{description}',
};
