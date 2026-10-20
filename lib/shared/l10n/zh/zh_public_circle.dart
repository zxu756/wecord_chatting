// Chinese for public circle web pages (C8): the circle's short name in its
// Discovery settings, and the /c/<slug> page in the app. 'Circle', 'Try
// again', 'Back to home', 'Copy link', 'Link copied' and 'This circle is not
// available' are already translated elsewhere. The web pages the Cloudflare Worker draws (worker/src/render.ts)
// carry their own English and Chinese text.
const zhPublicCircle = <String, String>{
  // Circle settings -> Discovery.
  'Web page': '网页',
  'Short name, e.g. pixel-painters': '短名，例如 pixel-painters',
  'A short name is 3 to 32 letters, digits and hyphens.':
      '短名由 3 到 32 个字母、数字或连字符组成。',
  'That short name is reserved.': '这个短名已被保留。',
  'That short name is taken.': '这个短名已被占用。',
  'Too many changes. Try again in a while.': '修改太频繁，请稍后再试。',
  'Could not save the short name. Try again.': '无法保存短名，请重试。',
  'While the circle is public, anyone with this link can see its name, picture, description, tags and a rounded member count on a web page, without an account, and link previews show the same. Never the members.':
      '圈子公开期间，任何拿到这个链接的人，不用账号就能在网页上看到圈子的名称、头像、简介、标签和大致的成员数，链接预览里显示的也是这些。成员不会被显示。',
  "{actor} changed the circle's short link": '{actor} 修改了圈子的短链接',

  // The /c/<slug> page in the app.
  'Could not load this circle': '无法加载这个圈子',
  'The link may be wrong, or the circle may not be public.':
      '链接可能有误，或者这个圈子并未公开。',
};
