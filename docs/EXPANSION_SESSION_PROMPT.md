# 给新 session 的提示词：规划 WeCord 的下一步拓展

> 用法：开一个新的 Claude Code session，工作目录设为 `/Users/xelieee/wecord_chatting`，把下面「提示词正文」整段粘贴进去。

---

## 提示词正文

你在帮我规划 **WeCord** 的下一步拓展。WeCord 是我做的聊天应用：微信式私聊/群聊 + Discord 式「圈子」社区 + Slack 式协作工具，用 Flutter（Riverpod 3、go_router）和 Supabase（Postgres + RLS + Realtime + Storage + Edge Functions + pg_cron）构建，已经在网页（https://wecord.jokebear.fyi，可安装为 PWA）、iPhone 和 macOS 上运行。**请全程用简体中文回复我。**

### 第一步：先读懂现状（不要跳过）

1. 完整阅读 `docs/WECORD_FEATURES.md`。这是截至 2026-10-20 已实现的全部功能清单，包括第 23 节「已知限制 / 尚未实现」。
2. 阅读 `docs/design/wecord-design-language.md`，了解设计语言 C：暖纸色、玻璃浮层、圆角方形、`WeCordTokens`、`lib/shared/ui/` 组件。
3. 快速浏览代码结构，确认清单和代码一致，不要只信文档：
   - `lib/features/`（约 40 个功能模块）；
   - `supabase/migrations/`（147 个迁移）；
   - `supabase/functions/`（16 个 Edge Functions）。
4. 发现文档和代码不一致的地方，先列出来告诉我。

### 第二步：做拓展方案（这是这次 session 的主要产出）

请做一份**拓展路线图**，要求如下：

**1. 参考来源要广。** 至少对照这些产品，找出 WeCord 还没有、且对用户真正有价值的东西：
- 微信、QQ、Telegram、WhatsApp、Signal、iMessage、LINE、Kakao；
- Discord、Slack、飞书、钉钉、Microsoft Teams；
- Notion、Linear（协作方面）；
- 小红书、Instagram（社交内容方面）。

不要重复列已经做过的功能，清单里已有的就跳过。

**2. 方向至少覆盖下面这些**，每个方向下给出具体功能点：
- 核心聊天体验的缺口：例如消息级举报、编辑历史、消息翻译设置、免打扰时段等，请自己找；
- 社交与内容：朋友圈之后还能做什么；
- 社区（圈子）运营与增长工具；
- 协作与效率：笔记、任务、接龙、活动之后；
- 语音/视频/直播；
- AI：在现有总结、改写、翻译、转写、守护之外；
- 隐私、安全与信任，包括端到端加密的可行方案；
- 多平台：Android、Windows/Linux 桌面、原生推送、TestFlight、App Store、Mac 签名公证；
- 开发者生态：Bot API、Webhook、小程序/插件；
- 商业化：在不碰支付牌照的前提下；
- 运营与可观测性：错误报告之外的监控、统计、管理后台；
- 性能、离线、可访问性和国际化的下一步。

**3. 每个功能点写清楚以下几项：**
- 用户价值：解决什么问题、谁会用；
- 参考了哪个产品的哪个功能；
- 实现思路：客户端改哪里、要不要新表/迁移、要不要新 Edge Function、要不要第三方服务；
- 工作量：S / M / L / XL；
- 依赖与风险：例如需要付费 Apple 开发者账号、第三方费用、隐私或合规风险、对现有功能的影响；
- 和现有功能的关系：复用什么、会不会冲突。

**4. 最后给出优先级排序：**
- 建议的前 3 批、每批 4–6 个，可以并行；
- 说明为什么这样排；
- 把需要我做决定或花钱的事情单独列出来。

**5. 产出形式：** 把完整路线图写进 `docs/EXPANSION_ROADMAP.md`，然后在回复里给我一个精简版摘要。**这一步先不要写任何功能代码**，等我挑选之后再开工。

### 第三步：我确认之后再开工，开工时必须遵守的规则

**1. 并行开发。** 用后台 subagent 并行开发，每个 subagent 用 `model: "sonnet"`、`effort: "high"`，并在独立的 git worktree 里工作（`isolation: "worktree"`）。
- 每个 subagent 第一步执行 `git reset --hard wecord-foundation`，从最新主分支开始。
- 多个 subagent 同时改动时，按改的文件分组，减少冲突。

**2. 迁移规范：**
- 文件名格式为 `supabase/migrations/YYYYMMDDNNNN_说明.sql`，编号不能和已有的冲突。
- 重写已有函数时，必须基于该函数**最新**的那一版定义（在所有迁移里找最后一次定义），不能丢掉之前功能加进去的规则。容易被覆盖的有：
  - 限时消息的过期过滤；
  - AI 守护的 `review_state` 过滤；
  - 文件传输助手的规则；
  - 相册计数；
  - 资料可见范围。
- SQL 只能在本地库 `postgresql://postgres:postgres@127.0.0.1:54322/postgres` 的**回滚事务**里测试。行为脚本开头取 `pg_advisory_xact_lock(20261017)`。永远不要把 DDL 提交到本地库。

**3. 中文：** 新文案放到新的 `lib/shared/l10n/zh/zh_xxx.dart`，并在 `zh.dart` 里注册。
- 同一个英文必须用已有的同一个中文翻译（`translations_test` 会检查）。
- 不能有未翻译的文案（`zh_coverage_test` 会检查）。
- 术语沿用：圈子、频道、朋友圈、接龙、文件传输助手、拍一拍、阅后即焚、限时消息、版主。

**4. 测试：** 单元、组件、SQL 行为、Deno 测试都要写；新页面要加进 `test/accessibility/a11y_screens.dart`。
- 每次提交前跑 `flutter analyze`，必须没有问题。
- 每次提交前跑完整 `flutter test`。
- 每个功能要写截图测试，写到 `build/<功能名>/`（手机和电脑、浅色和深色），并且**要真的看截图**，把看到的问题修掉。

**5. 设计：** 遵守设计语言 C，用 `context.tokens` 和 `lib/shared/ui/` 里的组件。
- 红色只用于需要用户处理的事（@提及、好友请求、审核、逾期、错误）；普通未读用灰色。

**6. 提交：** 提交信息格式为 `feat: ...` / `fix: ...` / `perf: ...`，结尾加：
```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```
- 永远不要暂存 `analysis_options.yaml`。
- subagent 不要 push。

**7. 合并与上线**（主 session 负责，我已授权连续推进，不用每步问我）：
1. `git merge --no-ff <分支>`；冲突一般出在 `zh.dart`、`a11y_screens.dart`、`chat_thread_screen.dart`，按「两边都保留」解决。
2. 跑完整测试。
3. 数据库：`supabase db push --linked --yes`。如果迁移编号早于线上最新的，加 `--include-all`。
4. 函数：`supabase functions deploy <名字>`。
5. 网页：`sh tool/deploy_web.sh`，然后对比线上和本地 `main.dart.js` 的哈希。
6. iPhone：`flutter build ios --release --dart-define-from-file=.env --dart-define=APP_VERSION=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)`，再用 `xcrun devicectl device install app --device 00008120-000208820A44C01E build/ios/iphoneos/Runner.app` 安装。手机锁屏时会报 4016 错误，等我解锁。
7. Mac：`flutter build macos --release --dart-define-from-file=.env --dart-define=APP_VERSION=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)`。
8. `git push origin wecord-foundation`。
9. 用中文告诉我结果，附上截图。

**8. 安全红线（绝对不能做）：**
- 不要读取或打印 `.env`，不要把任何密钥写进代码、提交或聊天。
- 不要运行 `supabase secrets set`、`supabase migration repair`、`supabase db reset --linked`、`supabase config push`。需要设置密钥时，给我一条 `! ...` 命令，让我自己运行。
- 对线上只允许：`supabase db push`、`supabase functions deploy`、只读的 `supabase db query --linked`（用于排查）。
- 不要改 DNS 或自定义域名，不要对线上跑端到端测试或探测脚本。
- 不要从 subagent 启动或退出我正在使用的 WeCord 应用。
- 如果某个操作被权限系统拒绝，不要绕过，告诉我。

**9. 节奏：** 一批 subagent 做完、上线后，马上开始下一批，不要闲着等我；只有需要我做决定、花钱或操作账号时才停下来问我。

### 背景信息（供参考）

| 项目 | 内容 |
|---|---|
| Supabase 项目 | `zpfternchrwboweellka` |
| 主分支 | `wecord-foundation` |
| GitHub | https://github.com/zxu756/wecord_chatting.git |
| 网页托管 | Cloudflare Worker（`wrangler.jsonc`），域名 wecord.jokebear.fyi |
| 语音 | LiveKit Cloud |
| AI | OpenCode Go（`deepseek-v4.1-flash`，OpenAI 兼容），可通过 `AI_BASE_URL`、`AI_API_KEY`、`AI_MODEL` 切换 |
| Office 预览 | Gotenberg on Google Cloud Run |

- **后台调度：** pg_cron 每分钟运行 `run_later_dispatch()`，它唤醒 `scheduled-dispatch` 函数。新的「到点推送」类功能应该接到这里，不要另开 cron。
- **测试规模：** 约 3822 个测试，全量跑一次 5–15 分钟；机器负载高时个别测试偶尔超时，单独重跑通过就算正常。
- **我目前还没有付费的 Apple 开发者账号。** 需要它的功能（原生推送、TestFlight、通用链接、Mac 签名公证）在路线图里标出来，作为「待开通账号后」那一批。
