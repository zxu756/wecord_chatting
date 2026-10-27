// Chinese for the whiteboard (roadmap D10): the composer entry, the board and
// its toolbar, the list view for screen readers, the versions sheet, the list
// of boards in a chat, the group tab and the guard / audit lines.
const zhWhiteboard = <String, String>{
  'Whiteboard': '白板',
  'Whiteboards': '白板',
  'New whiteboard': '新建白板',
  'Whiteboard name': '白板名称',
  'Untitled whiteboard': '未命名白板',
  'Name this whiteboard': '给白板起个名字',
  'Pick a whiteboard': '选择一块白板',
  'This chat has no whiteboards yet. Start one from the + menu first.':
      '这个聊天还没有白板。请先从“+”菜单新建一块。',
  'No whiteboards yet. Start one to sketch, plan or brainstorm together.':
      '还没有白板。新建一块，一起画图、做计划或头脑风暴。',
  'This chat already has {max} whiteboards. Delete one to make another.':
      '这个聊天已经有 {max} 块白板。删除一块后才能再新建。',
  'Could not make a whiteboard.': '无法新建白板。',
  'Only managers can draw': '仅管理者可画',

  // Colors and kinds, as read out by a screen reader.
  'black': '黑色',
  'red': '红色',
  'orange': '橙色',
  'yellow': '黄色',
  'green': '绿色',
  'blue': '蓝色',
  'purple': '紫色',
  'gray': '灰色',
  'white': '白色',
  'pink': '粉色',
  'Rectangle': '矩形',
  'Ellipse': '椭圆',
  'Triangle': '三角形',
  'Diamond': '菱形',
  'Line': '直线',
  'Arrow': '箭头',
  'Highlighter line': '荧光笔线条',
  'Pen line': '钢笔线条',
  'Sticky note': '便签',
  '{kind}, {color}, empty': '{kind}，{color}，空白',
  '{kind}, empty': '{kind}，空白',
  '{kind}, {color}: {words}': '{kind}，{color}：{words}',
  '{kind}: {words}': '{kind}：{words}',
  '{kind}, {color}': '{kind}，{color}',
  'At {x} across, {y} down': '位于横向 {x}、纵向 {y} 处',

  // The toolbar.
  'Pen': '钢笔',
  'Highlighter': '荧光笔',
  'Eraser': '橡皮',
  'Shapes': '形状',
  'Move the view': '移动视图',
  'Filled': '填充',
  'Line width {width}': '线条宽度 {width}',

  // The board.
  'Show the drawing': '显示画板',
  'Show as a list': '以列表显示',
  'Show everything': '显示全部内容',
  'Export as picture': '导出为图片',
  'Earlier versions': '以前的版本',
  'Let everyone draw': '允许所有人绘制',
  'Clear whiteboard': '清空白板',
  'Delete whiteboard': '删除白板',
  'Only managers can draw on this whiteboard.': '这块白板只有管理者可以绘制。',
  'Offline. What you draw is kept on this device and sent when you are back.':
      '已离线。你画的内容会保留在这台设备上，恢复联网后自动发送。',
  'This whiteboard was deleted.': '这块白板已被删除。',
  'Whiteboard drawing, {count} items. Use the list view to read or change it without drawing.':
      '白板画面，共 {count} 个元素。可以用列表视图阅读或修改，无需绘制。',
  '{count} others here: {names}': '另有 {count} 人在场：{names}',
  'Offline, kept on this device': '已离线，保存在这台设备上',
  'This whiteboard is full ({max} items). Delete something to add more.':
      '这块白板已满（{max} 个元素）。删除一些内容后才能继续添加。',
  'This whiteboard holds as much as it can. Delete something to add more.':
      '这块白板的容量已到上限。删除一些内容后才能继续添加。',
  'A whiteboard can hold {max} pictures.': '一块白板最多放 {max} 张图片。',
  'You can look at this whiteboard but not change it.': '你可以查看这块白板，但不能修改。',
  'The picture could not be added. Try again.': '无法添加图片，请重试。',
  'The whiteboard did not accept that change.': '白板没有接受这次改动。',
  'That picture could not be used.': '这张图片无法使用。',
  'Could not rename the whiteboard.': '无法重命名白板。',
  'There is nothing to export yet.': '还没有可导出的内容。',
  'Could not export the whiteboard.': '无法导出白板。',
  'Clear this whiteboard?': '清空这块白板？',
  'Everything on it is removed for everyone. The board is saved as an earlier version first, so you can go back to it.':
      '上面的所有内容会对所有人删除。白板会先存为一个以前的版本，之后可以回到它。',
  'Could not clear the whiteboard.': '无法清空白板。',
  'Delete this whiteboard?': '删除这块白板？',
  'It and its earlier versions are deleted for everyone. This cannot be undone.':
      '它和它以前的版本会对所有人删除，且无法恢复。',
  'Could not delete the whiteboard.': '无法删除白板。',

  // The list view for screen readers.
  'Write here': '在这里输入',
  'Nothing on this whiteboard yet.': '这块白板上还没有内容。',
  '{count} items on this whiteboard, top to bottom.':
      '这块白板上共有 {count} 个元素，按从上到下排列。',
  'Add a sticky note': '添加便签',
  'Add text': '添加文字',
  'Edit words': '修改文字',
  'Bring to front': '置于顶层',
  'Send to back': '置于底层',

  // Versions.
  'Saved by hand': '手动保存',
  'Before a restore or clear': '恢复或清空之前',
  'Saved automatically': '自动保存',
  'Could not save a version.': '无法保存版本。',
  'WeCord keeps the latest versions of this whiteboard. Going back to one first saves the board as it is now.':
      'WeCord 会保留这块白板最近的几个版本。回到某个版本之前，会先把现在的白板存为一个版本。',
  'No earlier versions yet.': '还没有以前的版本。',
  'Could not go back to this version.': '无法回到这个版本。',
  'This version was empty.': '这个版本是空白的。',
  'Preview of this version': '这个版本的预览',
  'Go back to this version': '回到这个版本',

  // Guard and audit log.
  'AI guard flagged a whiteboard name by {target}': 'AI 守护标记了 {target} 的一个白板名称',
};
