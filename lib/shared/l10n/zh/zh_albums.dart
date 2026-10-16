// Chinese for albums: what an album holds in a conversation list, and why
// one failed to send. The counts ("3 photos") are in zh_media_send.dart;
// the reasons themselves (slowmode, AutoMod, the circle rules, the 50 MB
// limit, a timeout) are the same words text sends use.
const zhAlbums = <String, String>{
  // "2 photos, 1 video"
  '{first}, {second}': '{first}，{second}',

  // A failed attachment or album.
  'Failed to send': '发送失败',
  'Edit and resend': '修改并重新发送',
  'Discard': '放弃',
  'The file to send is no longer there.': '要发送的文件已不存在。',
};
