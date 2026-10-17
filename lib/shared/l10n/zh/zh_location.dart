// Chinese for sending a location and sharing it live: the chat's Location and
// Share live location entries, the place picker, the map of a shared place,
// the live map, its banner and cards, and the consent sheet. Strings shared
// with other areas ("Cancel", "Close", "Zoom in", "Send", "Ended", ...) are
// not repeated here.
const zhLocation = <String, String>{
  // The chat's + menu.
  'Share live location': '共享实时位置',
  // The picker.
  'Send location': '发送位置',
  'Search for a place': '搜索地点',
  'Current location': '当前位置',
  'Dropped pin': '标记的位置',
  'Finding the address...': '正在查找地址…',
  'Nearby places': '附近的地点',
  'No places found.': '没有找到地点。',
  "Couldn't search right now. Check your connection and try again.":
      '暂时无法搜索，请检查网络后重试。',
  "Couldn't load nearby places. You can still send the pin.":
      '无法加载附近的地点，你仍然可以发送标记的位置。',
  'My location': '我的位置',
  'Allow location': '允许定位',
  'Allow location to start from where you are.': '允许定位，从你所在的位置开始选择。',
  'Open settings': '打开设置',
  'Location is off for WeCord. You can still search or move the map.':
      'WeCord 的定位已关闭。你仍然可以搜索地点或移动地图。',
  'Location services are off on this device. You can still search or move the map.':
      '这台设备的定位服务已关闭。你仍然可以搜索地点或移动地图。',
  'Map. Drag it to move the pin, or choose from the list.':
      '地图。拖动地图来移动标记，或从列表中选择。',
  "Couldn't send the location. Try again.": '无法发送位置，请重试。',
  // A shared place.
  'Shared location': '分享的位置',
  'Shared by {name}': '{name} 分享的位置',
  'Location: {place}': '位置：{place}',
  'Opens the map': '打开地图',
  'Open in Maps': '在地图中打开',
  'Open in {app}': '在 {app} 中打开',
  'Copy address': '复制地址',
  'Address copied': '地址已复制',
  'Could not open the map.': '无法打开地图。',
  'Map data: {credit}': '地图数据：{credit}',
  'Opens the copyright page': '打开版权页面',
  // Live location: consent.
  'Everyone in this chat sees where you are on a map while you share.':
      '共享期间，这个聊天里的所有人都能在地图上看到你的位置。',
  'For how long': '共享多久',
  '15 minutes': '15 分钟',
  '8 hours': '8 小时',
  'Precise location': '精确位置',
  'Shares exactly where you are.': '共享你的确切位置。',
  'Shares an approximate spot, within about 500 m.': '共享大致位置，误差约 500 米以内。',
  'Only members of this chat can see it. It is not saved: it stops when time runs out, when you tap Stop or when you leave the chat.':
      '只有这个聊天的成员能看到。位置不会被保存：时间到了、你点按“停止”或离开聊天时，共享就会结束。',
  'Sharing pauses when WeCord is closed.': '关闭 WeCord 后，共享会暂停。',
  'Start sharing': '开始共享',
  'Location is off for WeCord. Turn it on in Settings to share it.':
      'WeCord 的定位已关闭。请在“设置”中打开后再共享。',
  'Location services are off on this device.': '这台设备的定位服务已关闭。',
  'WeCord needs your location to share it.': 'WeCord 需要获取你的位置才能共享。',
  "Couldn't start sharing here.": '无法在这里开始共享。',
  "Couldn't start sharing. Try again.": '无法开始共享，请重试。',
  // Live location: banner, cards and map.
  '1 person sharing location': '1 人正在共享位置',
  '{count} people sharing location': '{count} 人正在共享位置',
  "You're sharing your location": '你正在共享位置',
  'Nobody is sharing location right now': '现在没有人在共享位置',
  'Live location': '实时位置',
  'Live location ended': '实时位置已结束',
  '{name} is sharing': '{name} 正在共享',
  '{name} stopped sharing': '{name} 已停止共享',
  'Stop': '停止',
  'Share my location': '共享我的位置',
  'Sharing': '共享中',
  'Approximate': '大致位置',
  'Updated {ago}': '{ago}更新',
  'Paused · last seen {ago}': '已暂停 · {ago}最后出现',
  'Waiting for their location...': '正在等待对方的位置…',
  "Can't see this location": '无法查看此位置',
  'Shows them on the map': '在地图上显示对方',
  'Sharing pauses when WeCord is closed. Positions are not saved.':
      '关闭 WeCord 后，共享会暂停。位置不会被保存。',
  'Until {time}': '到 {time}',
  '{minutes} min left': '还剩 {minutes} 分钟',
  '{hours} h left': '还剩 {hours} 小时',
  '{hours} h {minutes} min left': '还剩 {hours} 小时 {minutes} 分钟',
  'Less than a minute left': '不到 1 分钟',
  '{seconds} s ago': '{seconds} 秒前',
};
