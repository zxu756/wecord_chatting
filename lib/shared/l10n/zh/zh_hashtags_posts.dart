// Chinese for topics and circle posts 2.0 (roadmap B8): #话题 in Moments and
// circle posts, circle posts with a title, topics and the moderators' featured
// mark (精华), the grid view, the featured tab and the search strip. A topic is
// 话题; the forum "Topic" of the circle channels stays 主题. The sentences the
// database answers with (it refuses in English) are at the end, so that
// errorText can word them.
const zhHashtagsPosts = <String, String>{
  // Topics
  'Topics': '话题',
  'Topic {tag}': '话题 {tag}',
  'Topic #{tag}': '话题 #{tag}',
  'Add a topic': '添加话题',
  'Add topic': '添加话题',
  'Add topics': '添加话题',
  'Hide topics': '收起话题',
  'Add topic {tag}': '添加话题 {tag}',
  'Remove topic {tag}': '移除话题 {tag}',
  'A post can have {count} topics at most.': '一篇帖子最多有 {count} 个话题。',
  'A topic is 1 to 30 letters, digits or characters, without spaces.':
      '话题由 1 到 30 个字、字母或数字组成，不能有空格。',
  'Topics your friends and you used lately.': '你和好友最近用过的话题。',
  'No topics yet': '还没有话题',
  'Write #something in a Moment to start one.': '在朋友圈里写上 #话题 就会有了。',
  'Could not load topics.': '无法加载话题。',
  'Only Moments you can see are listed.': '这里只列出你看得到的朋友圈。',
  'No Moments with this topic': '还没有这个话题的朋友圈',
  'Moments you can see that use #{tag} show up here.':
      '你看得到的、带有 #{tag} 的朋友圈会显示在这里。',
  '{count} Moments': '{count} 条朋友圈',
  '{count} posts': '{count} 篇帖子',

  // Circle posts
  'Edit post': '编辑帖子',
  'Saving...': '正在保存...',
  'Write something first.': '请先写点内容。',
  'Feature': '设为精华',
  'Featured': '精华',
  'Featured post': '精华帖',
  'Featured posts': '精华帖',
  'Remove from Featured': '取消精华',
  'Could not change this post. Try again.': '无法修改这篇帖子，请重试。',
  'Grid view': '宫格视图',
  'No posts match': '没有符合条件的帖子',
  'Opens the post': '打开帖子',
  '{count} likes': '{count} 个赞',
  'This post is not available.': '这篇帖子无法查看。',
  'It may have been deleted.': '它可能已被删除。',

  // The audit log and the review queue
  '{actor} featured a post by {target}': '{actor} 把 {target} 的帖子设为了精华',
  '{actor} removed a post by {target} from Featured':
      '{actor} 取消了 {target} 的帖子的精华',
  'AI guard flagged a post by {target}': 'AI 守卫标记了 {target} 的一篇帖子',

  // What the database answers with
  'Only moderators can feature posts': '只有版主可以设置精华帖。',
  'The title can be 80 characters at most': '标题最多 80 个字。',
  'New members cannot post links while the circle is locked down':
      '圈子处于防刷屏锁定期间，新成员不能发布链接。',
  'Post not found or caller cannot edit it': '找不到这篇帖子，或你不能编辑它。',
  'Post not found or caller is not a circle member': '找不到这篇帖子，或你不是这个圈子的成员。',
  'This circle is suspended': '这个圈子已被暂停。',
};
