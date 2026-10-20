# 给新 session 的提示词：按拓展路线图开工

> **用法**：开一个新的 Claude Code session，工作目录设为 `/Users/xelieee/wecord_chatting`，把下面「提示词正文」整段粘贴进去。也可以只说一句：「读 `docs/EXPANSION_BUILD_PROMPT.md`，照里面的提示词正文做」。
> **只做一部分**：改掉正文里「本次范围」那一行再粘贴。
> **配套文件**：`docs/EXPANSION_ROADMAP.md`（拓展路线图，2026-10-18，基线 `85b5112`）。

---

## 提示词正文

你在帮我开发 **WeCord**。
- **产品**：微信式私聊/群聊 + Discord 式「圈子」社区 + Slack 式协作工具。
- **技术栈**：Flutter（Riverpod 3、go_router）+ Supabase（Postgres + RLS + Realtime + Storage + Edge Functions + pg_cron）。
- **已上线**：网页（https://wecord.jokebear.fyi，可安装为 PWA）、iPhone、macOS。

**请全程用简体中文回复我。**

上一个 session 已经写好拓展规划 `docs/EXPANSION_ROADMAP.md`。这次的任务是**按路线图开工**。

**本次范围**：路线图第 5 节的第 1 批 → 第 2 批 → 第 3 批，按顺序做完并上线；之后按第 5 节「之后的建议顺序」继续。如果我改了这一行，以这一行为准。

### 第一步：读懂计划（不要跳过）

0. 先确认 `docs/EXPANSION_ROADMAP.md` 已经在 `wecord-foundation` 上。如果不在：
   - 路线图写在本地分支 `worktree-expansion-roadmap` 上，没有推送到 GitHub。
   - 在 `/Users/xelieee/wecord_chatting` 执行 `git merge --no-ff worktree-expansion-roadmap -m "Merge expansion roadmap"`，再 `git push origin wecord-foundation`。
   - 这一步之后，subagent `git reset --hard wecord-foundation` 才能拿到路线图。
1. 读 `docs/EXPANSION_ROADMAP.md`：
   - 第 1 节：文档和代码的不一致；
   - 第 2 节：全局约束；
   - 第 5 节：批次、文件归属、验收要点；
   - 第 8 节：开工须知；
   - 本批每个功能在第 4 节的完整说明。
2. 读 `docs/WECORD_FEATURES.md` 和 `docs/design/wecord-design-language.md`。
3. 运行 `git log --oneline 85b5112..wecord-foundation`，看路线图写好之后有没有新提交。路线图里的功能如果已经做了，跳过并告诉我。
4. 标了【需决定】【花钱】【Apple 账号】的功能，**不要自己开工**：先把要我决定的事列出来问我；同一批的其他功能照常做。

### 第二步：开工规则

**1. 并行开发**

- 用后台 subagent 并行开发：
  - 每个 subagent 用 `model: "sonnet"`、`effort: "high"`；
  - 每个都在独立的 git worktree 里工作（`isolation: "worktree"`）。
- 每个 subagent 第一步执行 `git reset --hard wecord-foundation`，从最新的主分支开始。
- 一个 subagent 负责路线图第 5 节表格里的一个「包」，按「归属的文件 / 目录」分工，不改别的包的目录。
- 每个 subagent 的任务说明里必须写进：
  - 该功能在路线图第 4 节的完整段落，以及第 5 节的验收要点；
  - 它的迁移编号段（路线图 8.1）；
  - 它归属的文件和目录；
  - 路线图 8.2–8.5 的规则原文。
- 第 1 批的 L1（拆分聊天页）**独占**聊天页的文件，同批的其他 subagent 不能改这些文件。L1 必须保证行为完全不变：全量测试通过，现有截图逐张对比无差异。

**2. 迁移规范**

- 文件名格式为 `supabase/migrations/YYYYMMDDNNNN_说明.sql`。
  - 编号必须大于线上最新的 `202610200010`。
  - 按路线图 8.1 的编号段分配，不能和已有的冲突。
- 重写已有函数时，必须基于这个函数**最新**的那一版定义，不能丢掉之前功能加进去的规则。
  - 找最新定义：`grep -lE "function public\.<名字>\(" supabase/migrations/*.sql | sort | tail -1`。
  - 容易被覆盖的有：
    - 限时消息的过期过滤；
    - AI 守护的 `review_state` 过滤；
    - 文件传输助手的规则；
    - 相册计数；
    - 资料可见范围；
    - 以及路线图 8.3 列出的其他规则。
  - 能用触发器、新函数或在 Edge Function 里过滤解决的，就不要重写旧函数。
- SQL 只能在本地库 `postgresql://postgres:postgres@127.0.0.1:54322/postgres` 的**回滚事务**里测试。
  - 行为脚本开头取 `pg_advisory_xact_lock(20261017)`。
  - 永远不要把 DDL 提交到本地库。

**3. 中文**

- 新文案放到新的 `lib/shared/l10n/zh/zh_xxx.dart`，并在 `zh.dart` 里注册。
- 同一个英文必须用已有的同一个中文翻译，`translations_test` 会检查。
- 不能有未翻译的文案，`zh_coverage_test` 会检查。
- 术语沿用：圈子、频道、朋友圈、接龙、文件传输助手、拍一拍、阅后即焚、限时消息、版主。

**4. 测试**

- 单元、组件、SQL 行为、Deno 测试都要写；新页面要加进 `test/accessibility/a11y_screens.dart`。
- 每次提交前跑 `flutter analyze`，必须没有问题。
- 每次提交前跑完整的 `flutter test`。
- 每个功能都要写截图测试，输出到 `build/<功能名>/`（手机和电脑、浅色和深色）。**要真的看截图**，把看到的问题修掉。

**5. 设计**

- 遵守设计语言 C，用 `context.tokens` 和 `lib/shared/ui/` 里的组件。
- 红色只用于需要用户处理的事（@提及、好友请求、审核、逾期、错误、加急）；普通未读用灰色。

**6. 提交**

- 提交信息格式为 `feat: ...` / `fix: ...` / `perf: ...`，结尾加：

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

- 永远不要暂存 `analysis_options.yaml`。
- subagent 不要 push。

**7. 合并与上线**

主 session 负责，我已授权连续推进，不用每步问我：

1. `git merge --no-ff <分支>`。冲突一般出在 `zh.dart`、`a11y_screens.dart`、`chat_thread_screen.dart`（L1 拆分后是各个部件文件），按「两边都保留」解决。
2. 跑完整测试。
3. 数据库：`supabase db push --linked --yes`。如果有迁移编号早于线上最新的，加 `--include-all`。
4. 函数：`supabase functions deploy <名字>`。不带登录令牌的新函数，先在 `supabase/config.toml` 里设 `verify_jwt = false`（路线图 8.5）。
5. 网页：`sh tool/deploy_web.sh`，然后对比线上和本地 `main.dart.js` 的哈希。
6. iPhone：
   - 构建：`V=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml); flutter build ios --release --dart-define-from-file=.env --dart-define=APP_VERSION=$V --split-debug-info=build/symbols/$V/ios`（符号文件留在 `build/symbols/`，不提交，见 `docs/error-reports.md`）。
   - 安装：`xcrun devicectl device install app --device 00008120-000208820A44C01E build/ios/iphoneos/Runner.app`。
   - 手机锁屏时会报 4016 错误，等我解锁。
7. Mac：`V=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml); flutter build macos --release --dart-define-from-file=.env --dart-define=APP_VERSION=$V --split-debug-info=build/symbols/$V/macos`。
8. `git push origin wecord-foundation`。
9. 更新文档（路线图 8.6）：
   - 把新功能写进 `docs/WECORD_FEATURES.md`；
   - 改正路线图第 1 节列出的、已经被新功能修正的说法；
   - 在路线图第 3 节总表里标「✅ 日期」。
10. 用中文告诉我结果，附上截图。

**8. 安全红线（绝对不能做）**

- 不要读取或打印 `.env`，不要把任何密钥写进代码、提交或聊天。
- 不要运行 `supabase secrets set`、`supabase migration repair`、`supabase db reset --linked`、`supabase config push`。需要设置密钥时，给我一条 `! ...` 命令，让我自己运行。
- 对线上只允许：`supabase db push`、`supabase functions deploy`、只读的 `supabase db query --linked`（用于排查）。
  - 需要往线上写数据的事，给我 `!` 命令，我自己运行。比如 K1 要把我设为第一个平台管理员。
  - 迁移里不要写死任何用户 ID。
- 不要改 DNS 或自定义域名，不要对线上跑端到端测试或探测脚本。
  - 只加 Cloudflare Worker 的路由（例如 C8、H10 的 `/.well-known/` 文件）是允许的。
- 不要从 subagent 启动或退出我正在使用的 WeCord 应用。
- 如果某个操作被权限系统拒绝，不要绕过，告诉我。

**9. 节奏**

- 一批 subagent 做完、上线后，马上开始下一批，不要闲着等我。
- 只有需要我做决定、花钱或操作账号时才停下来问我。路线图第 7 节列出了这些事；遇到时一次性问清楚。

### 背景信息（供参考）

| 项目 | 内容 |
|---|---|
| Supabase 项目 | `zpfternchrwboweellka` |
| 主分支 | `wecord-foundation` |
| GitHub | https://github.com/zxu756/wecord_chatting.git |
| 网页托管 | Cloudflare Worker（`wrangler.jsonc`），域名 wecord.jokebear.fyi |
| 语音 | LiveKit Cloud |
| AI | OpenCode Go（`deepseek-v4.1-flash`，OpenAI 兼容），可以通过 `AI_BASE_URL`、`AI_API_KEY`、`AI_MODEL` 切换 |
| Office 预览 | Gotenberg，部署在 Google Cloud Run |
| 路线图基线 | `85b5112`（2026-10-18） |

- **后台调度**：pg_cron 每分钟运行 `run_later_dispatch()`，它会唤醒 `scheduled-dispatch` 函数。新的「到点推送」类功能接到这里，不要另开 cron。
  - 现在一共有 7 个 cron 任务，见路线图 1.2。
  - 每天一次的统计聚合，可以在调度里按「每天一次」守卫执行。
- **私聊只限好友**：`get_or_create_direct_conversation` 要求双方是好友。这是现有的强约束，除了路线图 I3 写明的机器人例外，不要放开。
- **测试规模**：约 3200 个测试定义，全量跑一次 5–15 分钟。机器负载高时，个别测试偶尔会超时；单独重跑通过就算正常。
- **Apple 开发者账号**：我还没有付费账号。需要它的功能放在路线图第 5 节的「开通 Apple 开发者账号之后」那一批。
