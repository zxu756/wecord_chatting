// Chinese for two-step recovery codes and passkeys (roadmap G4): the recovery
// code page and the way back in from a lost authenticator app, passkeys in
// Settings and on the sign-in page, and the security record. 'Cancel',
// 'Copied', 'Done', 'Continue', 'Save', 'Remove', 'Rename', 'Later', 'It was
// me', 'Not me' and the others that already have a Chinese text elsewhere
// are not repeated here.
const zhAccountSecurity = <String, String>{
  // Recovery codes: messages.
  "That recovery code didn't work. 1 try left.": '这个恢复码无效。还剩 1 次机会。',
  "That recovery code didn't work. {count} tries left.":
      '这个恢复码无效。还剩 {count} 次机会。',
  "That recovery code didn't work.": '这个恢复码无效。',
  'Too many wrong codes. Try again in {count} minutes, or sign in with your authenticator app.':
      '输错次数过多。请 {count} 分钟后再试，或用身份验证器 App 登录。',
  'This account has no recovery codes left.': '这个账号没有可用的恢复码了。',
  'Two-step verification is already off for this account.': '这个账号的两步验证已经关闭。',
  'Enter a code from your authenticator app first.': '请先输入身份验证器 App 里的验证码。',
  'You made several sets just now. Try again in an hour.':
      '你刚刚生成了好几组恢复码，请一小时后再试。',

  // Signing in with a recovery code.
  'Enter the {count}-character recovery code.': '请输入 {count} 位恢复码。',
  'Enter a recovery code': '输入恢复码',
  'Use one of the codes you saved when you turned on two-step verification. It works once and turns two-step verification off.':
      '请使用开启两步验证时保存的恢复码之一。每个只能用一次，用后会关闭两步验证。',
  'Recovery code': '恢复码',
  'Use my authenticator app instead': '改用身份验证器 App',
  'Lost your authenticator? Use a recovery code': '身份验证器丢了？使用恢复码',
  'Two-step verification is off': '两步验证已关闭',
  'You signed in with a recovery code, so two-step verification was turned off and your other codes no longer work. Turn it on again in Settings to keep your account safe.':
      '你用恢复码登录了，所以两步验证已关闭，其他恢复码也已失效。请到「设置」里重新开启，保护账号安全。',

  // Making and saving codes.
  'Make new recovery codes?': '重新生成恢复码？',
  'Your current codes stop working. Enter a code from your authenticator app to continue.':
      '现有的恢复码会全部失效。请输入身份验证器 App 里的验证码继续。',
  'Make new codes': '生成新的恢复码',
  'Make recovery codes': '生成恢复码',
  'Recovery codes': '恢复码',
  'WeCord recovery codes': 'WeCord 恢复码',
  'Each code works once. Keep them somewhere safe.': '每个恢复码只能用一次，请妥善保管。',
  'Save these codes now': '现在保存这些恢复码',
  "If you lose your authenticator app, one of these codes gets you back into your account. Each works once. They are shown only now, and WeCord can't show them again.":
      '如果丢了身份验证器 App，用其中一个恢复码就能重新登录账号。每个只能用一次。它们只在此刻显示，WeCord 无法再次显示。',
  'Code {number}: {code}': '第 {number} 个恢复码：{code}',
  'I saved these codes somewhere safe': '我已把这些恢复码保存在安全的地方',
  'Leave without saving?': '不保存就离开？',
  "These codes can't be shown again. Without them, losing your authenticator app could lock you out.":
      '这些恢复码不会再次显示。没有它们，丢了身份验证器 App 就可能无法登录。',
  'Stay': '留下',
  'You have no recovery codes. Make a set so you can get back in if you lose your authenticator app.':
      '你还没有恢复码。生成一组，丢了身份验证器 App 时才能重新登录。',
  'You have used all of your codes. Make a new set.': '你的恢复码已全部用完，请生成新的一组。',
  'Only 1 of {total} codes is left. Make a new set.':
      '{total} 个恢复码只剩 1 个，请生成新的一组。',
  'Only {count} of {total} codes are left. Make a new set.':
      '{total} 个恢复码只剩 {count} 个，请生成新的一组。',
  '{count} of {total} codes are left. Each works once.':
      '{total} 个恢复码还剩 {count} 个，每个只能用一次。',
  'Could not load your recovery codes.': '无法加载你的恢复码。',
  'Checking your recovery codes…': '正在检查你的恢复码…',
  'Recovery is locked for a while because of wrong codes (until {time}).':
      '因为输错了恢复码，恢复功能暂时锁定（到 {time}）。',

  // Passkeys.
  'Passkey': '通行密钥',
  'Passkeys': '通行密钥',
  'Sign in with a passkey': '使用通行密钥登录',
  "This device or browser can't use passkeys for WeCord.":
      '这台设备或浏览器暂时不能为 WeCord 使用通行密钥。',
  'Passkeys are not available on this server yet.': '服务器暂时还没有开放通行密钥。',
  'No passkey for WeCord was found on this device.': '这台设备上没有找到 WeCord 的通行密钥。',
  'This device already has a passkey for your account.': '这台设备上已经有你账号的通行密钥了。',
  'Sign in with your face, fingerprint or device PIN': '用面容、指纹或设备密码登录',
  'Sign in without a password': '无需密码登录',
  "A passkey lets you sign in with your face, fingerprint or device PIN. It stays on your device or in your password manager, and it can't be phished.":
      '通行密钥让你用面容、指纹或设备密码登录。它保存在你的设备或密码管理器里，也不怕钓鱼。',
  'Add a passkey': '添加通行密钥',
  'Passkeys can be added in the WeCord web app for now. You can see and remove them here.':
      '目前只能在 WeCord 网页版添加通行密钥，在这里可以查看和移除。',
  'You have no passkeys yet.': '你还没有通行密钥。',
  'Your passkeys': '你的通行密钥',
  'An account with two-step verification still asks for its code after a passkey.':
      '开启了两步验证的账号，用通行密钥登录后仍会要求输入验证码。',
  'Could not load your passkeys.': '无法加载你的通行密钥。',
  'Added {date}': '添加于 {date}',
  'Never used to sign in': '从未用于登录',
  'Last used {date}': '上次使用 {date}',
  'Passkey added.': '已添加通行密钥。',
  'Passkey removed.': '已移除通行密钥。',
  'Remove {name}?': '移除「{name}」？',
  'You will no longer be able to sign in with it. You can still sign in with your password.':
      '之后将不能再用它登录，仍可用密码登录。',
  'Rename passkey': '重命名通行密钥',
  'Enter a name.': '请输入名称。',
  'Confirm with your authenticator app': '用身份验证器 App 确认',
  'Changing passkeys needs a current code from your authenticator app.':
      '更改通行密钥需要身份验证器 App 里当前的验证码。',

  // The security record.
  'Security log': '安全记录',
  'Recovery codes and passkeys: what changed and when': '恢复码和通行密钥：改了什么、什么时候改的',
  'Nothing to report': '一切正常',
  'Changes to your recovery codes and passkeys in the last 30 days show up here.':
      '最近 30 天里恢复码和通行密钥的变化会显示在这里。',
  'Last 30 days': '最近 30 天',
  'Each change also reached your devices as a notification.':
      '每次变化也都会作为通知发到你的设备上。',
  'Could not load the security log.': '无法加载安全记录。',
  'Waiting for your answer': '等待你的回答',
  'You confirmed it': '你确认是本人',
  'You said it was not you': '你表示不是本人',
  'New recovery codes were made': '生成了新的恢复码',
  'A recovery code was used to sign in': '有人用恢复码登录了',
  'Too many wrong recovery codes': '恢复码输错次数过多',
  'A passkey was added to your account': '你的账号新增了通行密钥',
  'A passkey was removed from your account': '你的账号删除了一个通行密钥',
  'Your old recovery codes no longer work.': '旧的恢复码已全部失效。',
  'Two-step verification was turned off.': '两步验证已关闭。',
  'Recovery is locked for 30 minutes.': '恢复功能已锁定 30 分钟。',
  'Secure your account': '保护你的账号',
  'If this was not you, someone may know your password. Change it now and sign out the devices you do not recognize.':
      '如果不是你本人，可能有人知道你的密码。请立即修改密码，并让不认识的设备退出登录。',
  'Review devices': '查看设备',
  'You confirmed this change': '你确认了这次更改',
  'You said this was not you': '你表示这不是你本人',
  'Not you? Change your password and sign out the devices you do not recognize.':
      '不是你？请修改密码，并让不认识的设备退出登录。',
  'Not you? Change your password.': '不是你？请修改密码。',
};
