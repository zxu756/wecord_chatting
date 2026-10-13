# Discord 风格功能清单（Roadmap）

参考 Discord 的公开行为，在 WeCord 现有的 Flutter + Riverpod + Supabase 架构上重写，不搬运 Discord 代码或品牌元素。
本文件即各功能的设计说明。按编号顺序实现；每项完成后：`flutter analyze` + `flutter test` 通过 → 本地 `supabase db reset` 验证 migration → 提交 → `supabase db push`（有 Edge Function 的再 `supabase functions deploy`）→ 在这里勾掉。

工作量：**S** = 一两天以内，**M** = 需要新表/新 RPC + 较多 UI，**L** = 涉及外部服务或大量客户端工作。

## 通用约定

- Migration 文件名 `2026101300NN_<feature>.sql`，每项一个文件，只追加不修改旧文件。
- 新表全部开启 RLS；读写通过 `security definer` RPC，`set search_path = public`，开头校验 `auth.uid()` 与会话 / 圈子成员身份；`grant execute ... to authenticated`。
- 需要实时刷新的表加入 `supabase_realtime` publication（用 `do $$ ... if not exists ... $$` 守卫，参照已有 migration）。
- 客户端：模型放 `lib/shared/models/`，数据访问只经过 repository（接口 + Supabase 实现 + Uninitialized 实现），widget 不直接调 Supabase。
- 测试：`test/supabase/private_chat_schema_test.dart` 断言新表 / RPC / 策略；repository 用 fake data source 测；widget 用 fake repository 测。
- 圈子权限判断统一走 SQL 辅助函数（第 16 项引入 `circle_member_has_permission`），之前的项目沿用现有 owner / admin 判断。

---

## 已完成

- [x] 宽屏圈子工作区：圈子图标栏、频道侧栏（分类可折叠、未读标记）、内嵌频道聊天、成员列表开关
- [x] 媒体页 / 成员资料页改为 push，返回后保留圈子状态

## 第一批：消息基础

- [ ] **1. 消息表情回应（Reactions）**（S）
  - 表 `message_reactions (message_id, user_id, emoji text, created_at)`，主键 `(message_id, user_id, emoji)`；emoji 长度 1–64（为第 23 项自定义表情的 `custom:<uuid>` 预留）。
  - RPC `toggle_message_reaction(target_message_id, target_emoji)`：校验是会话成员、消息未撤回；存在则删，不存在则插。
  - `list_messages` 返回的每条消息附带 `reactions: [{emoji, count, reacted_by_me}]`；表加入 realtime，线程刷新时一起更新。
  - UI：长按菜单顶部一排常用表情（👍 ❤️ 😂 😮 😢 🎉）+「更多」打开完整选择器；消息下方显示表情标签，自己点过的高亮，点击切换，长按标签看谁点了。
- [ ] **2. 「新消息」分隔线 + 跳到最新**（S）
  - 打开会话时记下当时的 `last_read_message_id`（进入后会被标记已读，所以要在标记前取），在其后的第一条他人消息前画一条「NEW」分隔线，直到离开会话。
  - 列表不在底部且有新消息时，右下角浮动「跳到最新」按钮，显示新消息数。
- [ ] **3. 固定消息（Pinned Messages）**（S）
  - 表 `pinned_messages (conversation_id, message_id, pinned_by, pinned_at)`，每个会话最多 50 条。
  - RPC `pin_message` / `unpin_message`：私聊双方都可以；群聊群主可以；圈子频道 owner / admin 可以（第 16 项后改为 `manage_messages` 权限）。`list_pinned_messages(conversation_id)`。
  - 固定时在会话里插入一条系统提示「X 固定了一条消息」（`messages.type = 'system'`）。
  - UI：长按菜单「固定 / 取消固定」，顶栏 📌 按钮打开列表，点击滚动并高亮原消息。
- [ ] **4. 圈子邀请链接**（S–M）
  - 表 `circle_invites (code text primary key, circle_id, created_by, created_at, expires_at null, max_uses null, use_count, revoked_at null)`，code 为 10 位随机字符。
  - RPC：`create_circle_invite(circle_id, expires_in_hours, max_uses)`（owner / admin）、`list_circle_invites`、`revoke_circle_invite`、`get_circle_invite_preview(code)`（任何登录用户，返回圈子名、头像、成员数，失效时返回原因）、`accept_circle_invite(code)`（校验过期 / 次数 / 撤销 / 被封禁，加入圈子和所有频道会话，use_count + 1）。
  - 路由 `/invite/:code`：预览卡片 +「加入圈子」按钮，加入后跳到该圈子；未登录时登录后回到该页。
  - 圈子菜单「邀请」页增加链接区：生成、复制、查看已有链接、撤销。

## 第二批：增强圈子

- [ ] **5. 连续消息合并**（S）
  - 同一发送者、间隔 ≤ 7 分钟、中间没有日期分隔线 / 新消息线 / 系统消息时合并：后续消息不显示头像和名字，行距收紧。纯前端。
- [ ] **6. 成员列表按在线状态分组**（S）
  - 复用现有在线状态数据（`chat_status`），宽屏成员列表分成「在线 — n」「离线 — n」，在线组内再按角色排序；头像右下角状态点。
- [ ] **7. 圈子内昵称**（S）
  - `circle_members.nickname text null`（1–32 字）。RPC `set_circle_nickname(circle_id, nickname)` 改自己；owner / admin 可改他人（第 16 项后为 `manage_nicknames`）。
  - 圈子频道消息、成员列表、@提及候选里优先显示昵称。
- [ ] **8. 圈子级通知设置**（S）
  - 表 `circle_notification_settings (circle_id, user_id, level text check in ('all','mentions','none'), muted_until null)`。
  - 本地通知协调器在决定是否提醒频道消息时读取：`none` 不提醒；`mentions` 只在被 @ 时提醒；静音期间不提醒。
  - 圈子菜单加「通知设置」页。
- [ ] **9. 圈子图标栏未读点**（S）
  - `list_circle_summaries` 增加 `unread_count` 与 `mention_count`（汇总该圈子所有频道）。
  - 图标栏：有未读显示左侧 8px 小竖条；有 @ 时右下角红色数字徽标。
- [ ] **10. 频道分类 + 拖拽排序**（M）
  - 表 `circle_channel_categories (id, circle_id, name, position)`；`circle_channels.category_id null`。没有分类的频道显示在最上面。
  - RPC：`create_channel_category`、`rename_channel_category`、`delete_channel_category`（频道移到无分类）、`reorder_circle_channels(circle_id, layout jsonb)`（一次提交所有分类和频道的位置）。
  - 侧栏：每个分类可以独立折叠（折叠状态存本地 `shared_preferences`）；管理员可以拖拽频道（跨分类）和分类排序。
- [ ] **11. 窄屏 / 手机版圈子布局**（M）
  - 宽度 < 1000 时：左边圈子图标栏 + 频道列表组成「圈子首页」；点频道进入全屏聊天，返回回到频道列表；成员列表从聊天页右上角按钮以抽屉方式打开。

## 第三批：消息体验

- [ ] **12. 简单 Markdown**（M）
  - 支持：`**粗体**`、`*斜体*`、`__下划线__`、`~~删除线~~`、`` `行内代码` ``、```` ```代码块``` ````、`> 引用`、`||剧透||`（点击显示）、自动识别链接。
  - 自己写解析器（不引入 HTML），输出 `TextSpan` 树；@提及高亮与之共存。消息搜索仍按原文。
- [ ] **13. 链接预览**（M）
  - Edge Function `link-preview`：校验登录 → 拒绝内网 / 非 http(s) 地址 → 抓取（5 秒超时、最多 512KB）→ 解析 Open Graph / `<title>` → 写入缓存表 `link_previews (url primary key, title, description, image_url, site_name, fetched_at)`，24 小时内直接读缓存。
  - 客户端：消息里第一个链接下方显示预览卡片；发送者可以关闭该条消息的预览（`messages.suppress_embeds`）。
- [ ] **14. 自定义状态**（S）
  - `profiles.status_emoji text null`、`status_text text null`（≤ 64 字）、`status_expires_at null`。RPC `set_custom_status`。
  - 显示在成员列表、私聊顶栏、个人资料页；设置入口在「我」页面，可以选择 30 分钟 / 4 小时 / 今天 / 不清除。
- [ ] **15. 子话题（Threads）**（M）
  - 表 `conversation_threads (id, parent_conversation_id, root_message_id null, conversation_id unique, title, created_by, created_at, archived_at null, last_message_at)`。每个子话题是一个新的 `type = 'thread'` 会话，成员 = 父会话成员（加入父会话的人自动可见）。
  - RPC：`create_thread(parent_conversation_id, root_message_id, title)`、`list_threads(parent_conversation_id)`、`archive_thread`。根消息下方显示「n 条回复 · 最后回复时间」。
  - 宽屏：子话题在聊天区右侧以侧栏打开；频道侧栏在频道下方缩进显示活跃的子话题。

## 第四批：权限与管理

- [ ] **16. 自定义角色**（M–L）
  - 表 `circle_roles (id, circle_id, name, color int, position, permissions bigint, hoist bool, is_default bool)`、`circle_member_roles (circle_id, user_id, role_id)`。创建圈子时自动建 `@everyone` 默认角色；owner 拥有全部权限。
  - 权限位：`view_channel`、`send_messages`、`manage_messages`、`manage_channels`、`manage_roles`、`kick_members`、`create_invites`、`manage_nicknames`、`mention_everyone`、`manage_events`、`manage_emojis`、`manage_webhooks`、`view_audit_log`、`connect_voice`、`administrator`。
  - SQL 辅助函数 `circle_member_permissions(circle_id, user_id)` 和 `circle_member_has_permission(circle_id, user_id, permission)`；之前所有 owner / admin 判断改为调用它（新 migration 里 `create or replace`）。现有 admin 迁移为一个带管理权限的「管理员」角色。
  - UI：圈子设置 → 角色（新建、改名、颜色、权限开关、拖拽排序）、成员 → 分配角色；成员名字显示最高角色颜色；成员列表按 `hoist` 角色分组。
- [ ] **17. 频道权限覆盖**（M–L）
  - 表 `circle_channel_overwrites (channel_id, role_id null, user_id null, allow bigint, deny bigint)`。计算顺序：基础角色权限 → @everyone 覆盖 → 角色覆盖（合并）→ 成员覆盖。
  - 没有 `view_channel` 的频道不出现在列表里，也不能读消息（`messages` 的 RLS 与读取 RPC 对频道会话额外检查）；没有 `send_messages` 的频道输入框变成只读提示。
  - UI：频道设置 → 权限：快捷开关「私密频道」「只读频道」+ 高级的逐角色设置。
- [ ] **18. 慢速模式（Slowmode）**（S）
  - `circle_channels.slowmode_seconds int default 0`（0–21600）。发送消息的 RPC 对频道会话检查该用户上一条消息时间；有 `manage_messages` 权限的人不受限制。
  - 输入框上方显示「慢速模式已开启」和倒计时。
- [ ] **19. 操作日志（Audit Log）**（M）
  - 表 `circle_audit_log (id, circle_id, actor_id, action text, target_type, target_id, changes jsonb, created_at)`；所有管理类 RPC 写入（建 / 删 / 改频道、角色、权限、邀请、踢人、昵称、慢速模式、固定消息、Webhook、表情、活动）。
  - RPC `list_circle_audit_log(circle_id, before, limit)`，需要 `view_audit_log`。UI：圈子设置 → 操作日志，可按操作类型筛选。
- [ ] **20. 踢出成员**（S）
  - RPC `kick_circle_member`（需要 `kick_members`，不能踢 owner，也不能踢角色比自己高的人），同时移出所有频道会话；写操作日志。

## 第五批：扩展频道类型

- [ ] **21. 论坛频道（Forum）**（L）
  - `circle_channels.kind text check in ('text','voice','forum') default 'text'`。论坛里的每个帖子就是一个子话题（第 15 项），`root_message_id` 为空，帖子正文是子话题的第一条消息。
  - 表 `forum_tags (id, channel_id, name, emoji)`、`thread_tags (thread_id, tag_id)`；`conversation_threads` 增加 `is_pinned`。
  - UI：论坛频道显示帖子卡片列表（标题、作者、标签、回复数、最后活动、首图缩略图），按最新活动或创建时间排序、按标签筛选；「发帖」表单填标题、正文、标签。
- [ ] **22. 活动日程（Events）**（M–L）
  - 表 `circle_events (id, circle_id, title, description, location_type text check in ('voice','text','external'), channel_id null, location_text null, starts_at, ends_at null, created_by, cancelled_at null)`、`circle_event_rsvps (event_id, user_id, created_at)`。
  - RPC：创建 / 编辑 / 取消（`manage_events`）、`toggle_event_interest`、`list_circle_events(circle_id)`（未来的和进行中的）。
  - UI：频道侧栏顶部「活动（n）」入口；活动列表与详情（感兴趣人数、按钮、加入日历文本）；活动开始前 15 分钟给感兴趣的人本地通知（复用通知协调器，App 打开期间生效）。
- [ ] **23. 斜杠命令、投票与 Webhook**（L）
  - **斜杠命令**：输入框以 `/` 开头时弹出命令列表，支持 `/shrug`、`/tableflip`、`/unflip`、`/me`、`/spoiler`、`/roll [面数]`、`/poll`、`/nick`（改圈子昵称）、`/status`（改自定义状态）。前三个是纯文本替换；其余调用对应功能。
  - **投票**：`messages.type = 'poll'`，attachment 存 `{question, options[], multi, ends_at}`；表 `message_poll_votes (message_id, user_id, option_index)`；RPC `vote_poll`；消息里显示进度条和票数，结束后锁定。
  - **Webhook（机器人入口）**：表 `circle_webhooks (id, channel_id, name, avatar_url, token_hash, created_by, created_at)`；`messages.webhook_id null` + `webhook_name`。Edge Function `webhook`：`POST /webhook/{id}/{token}`，body `{content, username?}`，校验 token 哈希，以创建者身份写入消息并标记 webhook，消息显示 webhook 名字和「BOT」标签。频道设置里可以新建、复制 URL、重置 token、删除（需要 `manage_webhooks`）。
- [ ] **24. 自定义表情 / 贴纸**（M）
  - 表 `circle_emojis (id, circle_id, name text check '^[a-z0-9_]{2,32}$', kind text check in ('emoji','sticker'), storage_path, created_by, created_at)`，圈子内名字唯一，每个圈子最多 50 个表情、20 个贴纸。
  - 私有 Storage 桶 `circle-emojis`，成员可读，有 `manage_emojis` 的人可写；PNG / GIF / WebP，≤ 256KB。
  - 消息里写成 `<:name:uuid>`；输入框输入 `:` 时联想；渲染成行内小图（只有表情时显示大图）。表情回应用 `custom:<uuid>`。贴纸作为 `messages.type = 'sticker'` 单独发送。
  - UI：圈子设置 → 表情与贴纸（上传、改名、删除）；表情选择器增加「本圈子」分组。
- [ ] **25. 语音频道 / 视频 / 屏幕共享**（L）
  - `circle_channels.kind = 'voice'`。表 `voice_states (channel_id, user_id, joined_at, last_seen_at, self_mute, self_deaf, video, screen)`，客户端每 20 秒心跳；超过 60 秒没有心跳视为离开。RPC `join_voice_state`、`update_voice_state`、`leave_voice_state`、`list_voice_states(circle_id)`；表加入 realtime。
  - Edge Function `livekit-token`：校验登录与频道 `connect_voice` 权限 → 用 `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` 签发 JWT（房间名 = 频道 id，identity = 用户 id，name = 显示名）→ 返回 `{url, token}`。缺少 `LIVEKIT_URL` / `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` 时返回 503 `voice_not_configured`，客户端提示「语音服务未配置」。
  - 客户端用 `livekit_client`：语音频道视图显示参与者网格（说话时头像描边）、麦克风 / 耳机 / 摄像头 / 屏幕共享 / 断开按钮；侧栏语音频道下方列出在里面的人；连接后侧栏底部显示「语音已连接」面板，切换频道不断开。
  - 平台：Web 与 macOS 支持语音、视频、屏幕共享（macOS 需要麦克风 / 摄像头权限与网络 entitlement）；iOS 支持语音与视频，不做屏幕共享（需要 Broadcast Extension）。
  - **配置（需要你操作）**：注册 LiveKit Cloud → 新建项目 → `supabase secrets set LIVEKIT_URL=wss://... LIVEKIT_API_KEY=... LIVEKIT_API_SECRET=...`。
