# 网页 WebAssembly 构建试验报告（L5）

日期：2026-10-28（试验）。Flutter 3.47.7（Dart 3.13.5），Chrome 156，Apple M1 Pro。

## 1. 结论

- **`flutter build web --wasm` 现在就能编过**，代码几乎不用改。项目早就用 `package:web` + `dart:js_interop`，没有 `dart:html`、`dart:js`、`dart:js_util`、`package:js`。唯一一处真问题是一个条件导入（见第 3 节），已改。
- **没有跨源隔离头（COOP/COEP）也能跑**：这时 skwasm 用单线程模式。启动明显更快，滚动在慢 CPU 上更稳。
- **启动**：冷启动首帧约快 2 倍（模拟慢网络和慢 CPU 时 6.9 秒 → 3.5 秒），回访（文件已缓存）约快 3 到 4 倍（5.3 秒 → 1.6 秒，本机不限速时 1.28 秒 → 0.38 秒）。
- **体积**：首次下载多约 6%（Brotli 后 5.0 MB → 5.3 MB）。
- **滚动**：本机不限速时 JS 版和 wasm 版都是满 60 帧，分不出差别；把 CPU 放慢 10 倍后，JS 版 15 帧/秒，wasm 单线程 28 帧/秒，wasm 多线程（要 COOP/COEP）58 帧/秒。
- **不要开 COOP/COEP**：`require-corp` 会让没有 CORS 或 CORP 头的跨站图片和脚本直接加载失败（链接预览图、头像等），`credentialless` 能救图片但救不了跨站 iframe。多线程 skwasm 的收益不值得这个风险。
- **建议**：可以切换，但分两步，不要一步到位（第 9 节）。部署脚本默认仍是 JS 构建，加了可选开关 `WECORD_WEB_WASM=1`。

## 2. 怎么编、产物是什么

```sh
flutter build web --wasm --release          # 本次试验
WECORD_WEB_WASM=1 sh tool/deploy_web.sh     # 可选开关（默认关闭，不要在没读完本报告前用）
```

- 这个构建**同时**产出 wasm 和 JS 两套：`main.dart.wasm` + `main.dart.mjs`，以及原来的 `main.dart.js`（带延迟加载的分片）。`flutter_bootstrap.js` 里的 `_flutter.buildConfig` 列出两个候选，Flutter 的加载器按顺序挑第一个这个浏览器能用的：
  1. dart2wasm + skwasm：要 WasmGC 和 WebGL，并且浏览器在**允许列表**里。Flutter 默认的允许列表只有 Chromium 内核（Chrome、Edge、Opera 等）；Firefox 和 Safari 默认不用 wasm（`wasmAllowList` 可改，不建议改，见第 9 节）。
  2. dart2js + CanvasKit：现在线上这套，其他浏览器全走这里。
- **回退是自动的**：用 `WebAssembly.validate` 假装浏览器没有 WasmGC，加载器改用 `main.dart.js`（`tool/web_bench/bench.mjs --nowasmgc` 验证过）。
- 编译时间：wasm 构建约 250 秒（里面还要再编一遍 JS），JS 构建约 96 秒。
- 产物大小（`build/web`）：JS 59 MB，wasm 71 MB（含两套）。单个文件里最大的是 `main.dart.wasm` 12.4 MB（原始）；Cloudflare 静态资源单文件上限 25 MiB，够用。

## 3. 兼容性清单

### 3.1 代码（`lib/`）

| 项目 | 结果 |
|---|---|
| `dart:html`、`dart:js`、`dart:js_util`、`package:js`、`dart:indexed_db` 等旧库 | **没有**（已有测试 `test/web/wasm_compat_test.dart` 防止回退）。 |
| `dart:js_interop`、`dart:js_interop_unsafe`、`package:web` | 20 个文件在用（推送、PWA、分享目标、IndexedDB、WebCrypto、语音输入、视频消息、背景虚化、抠图、下载……），编译都过。逐个读过：`isA<>`、`as JSString`、`.toDart`、`jsify()` 等写法在 wasm 里语义相同；`Uint8List.toJS` / `JSArrayBuffer.toDart` 在 wasm 里是复制而不是共享视图，这几处代码都只读一次，不依赖共享。 |
| **条件导入 `dart.library.html`** | **一处真问题**：`lib/features/notifications/local_notification_service.dart` 用它选择网页通知实现。在 wasm 里 `dart.library.html` 是 false，会悄悄选到空实现，网页通知整个失效而且不报错。**已改成 `dart.library.js_interop`**（JS 和 wasm 里都是 true；其余 28 处条件导入本来就用这个）。`wasm_compat_test.dart` 禁止再写 `dart.library.html` / `dart.library.js`。 |
| 整数和浮点语义（wasm 是真 64 位整数，`1.0.toString()` 是 `1.0`） | 和 iPhone / Mac（Dart VM）一致，而 App 已经在这两个平台上跑并有测试，所以比 dart2js 更不容易出新问题。只在仅网页的文件里查了位运算和大整数：没有依赖 JS 32 位行为的。 |

### 3.2 依赖（`pubspec.lock` 里 249 个托管包，逐个看了 `lib/` 里的导入）

- 旧浏览器库：**没有一个包在编译图里用**。唯一提到 `dart:html` 的是 `file_selector_platform_interface` 里的 `web_helpers.dart`，它没有被任何文件引用（编译不到）。
- 已用 `dart:js_interop` / `package:web` 的网页相关包（都编过）：`supabase_flutter`、`gotrue`、`http`、`web_socket_channel`、`livekit_client`、`flutter_webrtc`、`dart_webrtc`、`livekit_noise_filter`、`pdfrx`、`mobile_scanner`、`passkeys_web`、`record_web`、`just_audio_web`、`video_player_web`、`camera_web`、`geolocator_web`、`image_picker_for_web`、`file_selector_web`、`desktop_drop`、`share_plus`、`flutter_tts`、`flutter_secure_storage_web`、`shared_preferences_web`、`url_launcher_web`、`connectivity_plus`、`device_info_plus`、`package_info_plus`、`flutter_local_notifications_web`、`app_links_web`、`cryptography`、`flutter_markdown_plus` 等。
- **编过不等于每个功能都好用**。能在无头 Chrome 里验证的只有启动路径（见 3.3）；需要登录、摄像头、麦克风、推送授权的功能没有测，列在第 8 节。

### 3.3 在无头 Chrome 里实际跑过的

| 检查 | 结果 |
|---|---|
| 登录页在 wasm（skwasm）下渲染 | 正常。启动时会打开 IndexedDB 聊天缓存、WebCrypto 密钥、Supabase 初始化、Passkey 脚本；没有任何控制台错误或未捕获异常（截图看过）；只有加载器的一条「skwasm 将以单线程运行」提示，`flutter_bootstrap.js` 里已把它关掉（`suppressMultithreadingWarning`）。 |
| 同一个包用 `?wasm=0` 走 JS | 正常，无错误。 |
| 开 COOP/COEP（`crossOriginIsolated` 为 true，skwasm 多线程） | 正常，无错误。 |
| 假装没有 WasmGC | 加载器回退到 `main.dart.js`，正常。 |
| Service Worker（盖了版本戳的 wasm 包，`?sw=1`） | 缓存了 `main.dart.wasm`、`main.dart.mjs`、`skwasm.js`、`skwasm.wasm`，**没有**多缓存一份 `main.dart.js`；断网后重新打开仍能启动并渲染，加上 COOP/COEP 后断网重开仍是跨源隔离状态。 |

### 3.4 第三方内容在 COOP/COEP 下的影响（`tool/web_bench/coep_probe.mjs` 实测）

在无头 Chrome 里用本地两个端口模拟跨站资源：

| 资源 | 现在 | `COEP: require-corp` | `COEP: credentialless` |
|---|---|---|---|
| 跨站图片，无 CORS 无 CORP（链接预览图、头像、很多图床） | 能加载 | **被拦截** | 能加载 |
| 跨站图片，只有 CORS（OSM 地图瓦片）且 `<img>` 没有 `crossorigin` | 能加载 | **被拦截** | 能加载 |
| 带 `crossorigin` 的跨站图片（有 CORS） | 能加载 | 能加载 | 能加载 |
| 跨站脚本，有 `CORP: cross-origin` | 能加载 | 能加载 | 能加载 |
| 跨站脚本，无 CORP | 能加载 | **被拦截** | 能加载 |
| 跨站 iframe，无 COEP/CORP | 能加载 | **被拦截** | **被拦截** |

再查了 WeCord 用到的几个 CDN（`curl -I`）：`unpkg.com`（扫码 zxing）、`cdn.jsdelivr.net`（MediaPipe、LiveKit 背景虚化处理器）都带 `Access-Control-Allow-Origin: *` 和 `Cross-Origin-Resource-Policy: cross-origin`；`storage.googleapis.com`（抠图模型）带 CORS；GIPHY 带 CORS 和 CORP；OSM 瓦片带 CORS，没有 CORP。Supabase Storage 的响应头**没有在线上验证**（不碰线上）。

各项影响（只在开 COOP/COEP 时才有，单线程 wasm 完全不受影响）：

| 功能 | 影响 |
|---|---|
| 第三方 iframe 嵌入 | App 本身不嵌别人的页面（网页版链接在新标签页打开，`inAppBrowserSupported` 在网页上是 false，办公文件由服务端转成 PDF）。但是 `require-corp` 和 `credentialless` 都会拦下没有 CORP 的跨站 iframe；以后如果要在 App 里嵌第三方页面，就不能开隔离。反过来，别人把 WeCord 嵌进自己的页面时，WeCord 在跨源 iframe 里多半拿不到隔离，会用单线程（没有测）。 |
| 聊天里的图片、视频、链接预览图、头像、GIF | **主要风险**：Flutter 的网络图片先用 CORS 取字节，失败再退回 `<img>`；`require-corp` 下这个退回会被拦。视频用 `<video>` 元素，Supabase 签名地址有没有 CORP 头没验证。 |
| Web Push、`push_sw.js` | 推送本身不受 COOP/COEP 影响。Service Worker 要能带着隔离头回应：已验证 `wecord_sw.js` 缓存的外壳保留了响应头，断网重开仍是隔离状态；`push_sw.js` 在 `push/` 作用域里，不回应页面请求。 |
| Service Worker 版本戳 | 没有影响；版本戳是整个构建目录的哈希，wasm 文件自动包含在内。`wecord_sw.js` 做了配套修改（第 4 节）。 |
| 扫码 CDN 库（zxing、zxing-wasm） | CDN 带 CORP，开 `require-corp` 也能加载。 |
| LiveKit 通话 | WebSocket 和 WebRTC 不受 COEP 影响；背景虚化从 jsDelivr 动态加载模块和模型，都带 CORS。通话本身没有在 wasm 下实测（没有摄像头和房间）。 |
| `COOP: same-origin` | 会切断 `window.opener`。App 里没有 OAuth 弹窗、没有靠 opener 回传的流程（登录是邮箱密码和 Passkey）；公开圈子页面（`worker/src`）已经在用 `COOP: same-origin`。 |
| 部署 | 头要写进 `web/_headers` 的 `/*`，同时会影响 `/developers/` 静态文档页；Worker 路径（`/c/*`、`/invite/*`）自己设头。 |

**结论**：不开 COOP/COEP，用单线程 skwasm。需要多线程时再单独评估（至少要先测 Supabase Storage 的图片、视频，并接受跨站 iframe 不可用）。

## 4. 改了什么

| 文件 | 改动 |
|---|---|
| `lib/features/notifications/local_notification_service.dart` | 条件导入从 `dart.library.html` 改成 `dart.library.js_interop`（wasm 下网页通知才会生效）。 |
| `web/flutter_bootstrap.js` | 加 `?wasm=0`：强制用 JS 版（出问题时判断是不是 wasm 引起的，也是用户的逃生口）；加 `suppressMultithreadingWarning: true`，关掉单线程 skwasm 的控制台提示。纯 JS 构建里这两项都无效。 |
| `web/wecord_sw.js` | ① `APP_FILES` 加 `main.dart.mjs`、`main.dart.wasm`（原来的正则只认 `main.dart.js`，wasm 构建断网打不开）；② 安装时看 `flutter_bootstrap.js` 里有没有 `"dart2wasm"`：有就预缓存 `main.dart.wasm`、`main.dart.mjs`，不再预缓存 `main.dart.js`（不让 wasm 浏览器多下一份 12 MB）；不支持 wasm 的浏览器仍会按页面报告的清单和旧缓存带过来缓存 `main.dart.js`；③ 可选文件如果被站点的单页应用兜底返回成 HTML（Cloudflare 对不存在的路径返回 `index.html`，状态 200），不当成文件缓存。 |
| `tool/deploy_web.sh` | 可选开关 `WECORD_WEB_WASM=1`：构建加 `--wasm`，并检查 `build/web/main.dart.wasm` 存在。不设变量时命令行和以前完全一样。版本戳、`wrangler deploy` 不变。 |
| `test/web/wecord_sw_harness.mjs`、`test/web/wecord_sw_test.dart` | Service Worker 假环境加 wasm 构建、HTML 兜底的检查；测试确认部署脚本默认不带 `--wasm`、加载器有 `wasm=0`。 |
| `test/web/wasm_compat_test.dart`（新） | 禁止旧浏览器库和 `dart.library.html` / `dart.library.js`。 |
| `tool/web_bench/`（新） | `bench.mjs`（启动、滚动、断网重开、冒烟、跨源隔离开关、限速）、`scroll_bench.dart`（滚动基准的入口）、`coep_probe.mjs`（COOP/COEP 探测）。 |

没有改任何 `*_web.dart`：它们已经是 `package:web` + `dart:js_interop`，没有可以再迁移的。

## 5. 怎么测的

- 浏览器：Chrome 156 无头模式（`--headless=new`），独立的临时配置目录，用 DevTools 协议驱动（`tool/web_bench/bench.mjs`，只要 Node 22 以上和本机 Chrome，不装依赖）。
- 服务：本机 Node 静态服务，带 Brotli、ETag、`max-age=0, must-revalidate`，和 Cloudflare 静态资源的行为接近；Brotli 质量 5，Cloudflare 的压缩率可能略不同。
- 对象：同一次构建的产物。JS 版是同一个包加 `?wasm=0`（`main.dart.js` 和单独做的 `flutter build web --release` 产物逐字节大小相同：12,178,515 字节）。启动测试用带占位 Supabase 地址的构建（登录页）。
- 启动：「冷」=关闭缓存；「回访」=开缓存，所有文件走 `If-None-Match` 返回 304。首帧 = `flutter-first-frame` 事件相对导航开始的时间。每组 3 次取中位数。网络用 DevTools 限速（下载带宽和延迟）；CPU 用 `Emulation.setCPUThrottlingRate`，只放慢页面主线程，Worker 不受影响。
- 滚动：`tool/web_bench/scroll_bench.dart` 是单独的入口，里面是聊天用的真 `MessageListView`（同样的切片、锚点和 key），5000 条像气泡的条目（中英文混合长文本、头像、回应、图片占位、阴影、裁剪）。预热 3 秒后以 2400 像素/秒匀速滚 12 秒，每帧 `jumpTo`，记录 Flutter 的帧耗时（构建、光栅）和页面的 `requestAnimationFrame` 间隔。**这不是真聊天页**（真聊天页要登录 Supabase），它测的是引擎的布局、绘制、光栅差别。
- 本机性能很强，所以滚动要放慢 CPU 才看得出差别。

## 6. 测量结果

### 6.1 启动（首帧，毫秒；3 次中位数）

| 网络 / CPU | JS 冷 | wasm 冷 | wasm+隔离 冷 | JS 回访 | wasm 回访 | wasm+隔离 回访 |
|---|---|---|---|---|---|---|
| 本机不限速 / 1 倍 | 1542 | **768** | 1063 | 1281 | **376** | 421 |
| 30 Mbit/s、20 ms / 4 倍慢 | 6929 | 3521 | **3036** | 5304 | 1624 | **1358** |
| 9 Mbit/s、85 ms（4G）/ 4 倍慢 | 8598 | **6616** | 6783 | 4943 | **1870** | 1949 |

首次下载量（Brotli，中位数）：JS 5020 KB，wasm 5315 KB（+5.9%），回访 4 到 5 KB。最大的几项：JS 是 `main.dart.js` 2.8 MB + `canvaskit/chromium/canvaskit.wasm` 1.8 MB；wasm 是 `main.dart.wasm` 3.5 MB + `skwasm.wasm` 1.35 MB。字体和 Roboto 回退字体（从 gstatic 取）两边一样。

wasm 回访快得多，推测是因为 Chrome 缓存了 wasm 的编译结果，而 12 MB 的 JS 每次都要重新解析（没有单独验证）。

### 6.2 滚动 5000 条消息（12 秒；3 次中位数）

| CPU | 版本 | 页面帧率 | 帧耗时 p50 / p90 / p99（毫秒） | 超过 33 毫秒的帧 |
|---|---|---|---|---|
| 1 倍 | JS | 60.1 | 1.8 / 2.5 / 3.7 | 0 |
| 1 倍 | wasm | 60.1 | 1.7 / 2.2 / 3.5 | 0 |
| 1 倍 | wasm+隔离 | 60.1 | 2.0 / 2.7 / 6.8 | 0 |
| 4 倍慢 | JS | 59.6 | 9.9 / 14.3 / 22 | 2 |
| 4 倍慢 | wasm | 58.9 | 8.9 / 12.3 / 23 | 3 |
| 4 倍慢 | wasm+隔离 | 59.5 | 5.3 / 7.7 / 20 | 3 |
| 10 倍慢 | JS | **15.1** | 57 / 90 / 763 | 133（共 150 帧） |
| 10 倍慢 | wasm | **27.6** | 32 / 44 / 118 | 144（共 313 帧） |
| 10 倍慢 | wasm+隔离 | **57.6** | 12.5 / 25 / 59 | 16（共 688 帧） |

- 手机和机器够快时，三者没有可见差别，都是满 60 帧（受屏幕刷新率限制）。差别出现在慢设备上：10 倍慢时 wasm 单线程比 JS 流畅约 1.8 倍，最差帧（p99）从 763 毫秒降到 118 毫秒。
- 多线程（隔离）最好，但 CPU 放慢只作用在主线程，光栅在 Worker 里没被放慢，所以这一行偏乐观；而且它需要开 COOP/COEP（第 3.4 节），不建议。
- 单次运行的噪声不小（隔离版冷启动有一次 3.5 秒的离群值，中位数不受影响）。

## 7. 部署开关和风险

`WECORD_WEB_WASM=1 sh tool/deploy_web.sh`：

1. 构建加 `--wasm`，其余（版本戳、`wrangler deploy`）不变。
2. 所有浏览器仍然拿到同一份 `index.html`，由加载器当场决定用 wasm 还是 JS；不需要服务器按浏览器分流。

风险：

- **回滚**：不设变量重新部署就回到纯 JS；用户端可用 `?wasm=0` 强制 JS。
- **两套都要部署**：一次构建、一次上传，上传量从 59 MB 变成 71 MB；Service Worker 版本戳是整个目录的哈希，每次部署都会变，更新提示照旧。
- **wasm 文件的 MIME 类型**：`compileStreaming` 要求 `Content-Type: application/wasm`。Cloudflare 静态资源按扩展名给，应该没问题，但**部署后要用 `curl -I` 检查** `main.dart.wasm`（应是 `application/wasm`）和 `main.dart.mjs`（`text/javascript`）。
- **崩溃报告**：wasm 的堆栈是 `wasm-function[n]` 形式，没有符号文件（`tool/symbolize_errors.py` 本来就不适用于网页版）；JS 版的堆栈也是压缩过的，所以不算新退步，但报告里会多出一类看不懂的堆栈。
- **Flutter 说 wasm 仍是「新功能」**：构建时有警告；每次升级 Flutter 都要再测。
- **Safari 和 Firefox**：Safari 18.2 起支持 WasmGC，但 Flutter 默认不对 WebKit 和 Gecko 开 wasm（允许列表只有 Blink），所以它们继续用 JS，行为和现在完全一样。要给它们开，需要在 `flutter_bootstrap.js` 的 config 里加 `wasmAllowList: { webkit: true }`，那需要真机 Safari 验证后再做。
- **iPhone 主屏 PWA** 用的是 WebKit，所以不受这次切换影响。

## 8. 没有测的（需要真浏览器 / 登录 / 设备）

- 登录之后的所有页面：聊天页、圈子、朋友圈、笔记、白板、设置。
- 需要硬件或授权的：摄像头（圆形视频消息、背景虚化、扫码）、麦克风（语音消息、语音输入、通话）、Web Push 授权和点击通知、定位、分享目标、`web+wecord:` 协议。
- LiveKit 通话、PDF 查看（pdfrx 在 wasm 下）、IndexedDB 里的老缓存迁移、Passkey 实际登录。
- 视频消息摄像头出错时的判断（`video_note_camera_web.dart` 用错误文字里是否含 `NotAllowed` 来分类）：wasm 下 JS 异常的文字形式没有验证。
- 真机：Android Chrome、Windows Edge、低端手机的实际帧率。
- Supabase Storage 的图片和视频响应头（决定要不要考虑隔离）。

## 9. 建议是否切换

**可以切换，建议分两步：**

1. **第一步（现在可做）**：用 `WECORD_WEB_WASM=1` 部署一次，在一台 Chrome 桌面和一台 Android Chrome 上走一遍第 8 节的清单（先登录、发消息、滚动、发图片、语音、扫码、通话、Passkey、断网重开、更新提示）。发现问题就不设变量重新部署，影响面只是 Chromium 用户。收益：冷启动快一倍、回访快三到四倍、低端机滚动更稳。代价：首次多下载约 0.3 MB，崩溃堆栈难读。
2. **第二步（观察一到两周后）**：把 `tool/deploy_web.sh` 的默认改成 wasm（去掉开关的判断，保留 `WECORD_WEB_WASM=0` 作为关闭）。同时看错误报告里有没有 `wasm-function` 堆栈集中出现的问题。
3. **不建议开 COOP/COEP**，也不建议现在给 Safari 和 Firefox 开 wasm。

## 10. 以后引入 openmls / flutter_rust_bridge（G9）

`openmls` 和 `flutter_rust_bridge` 目前不支持 `--wasm` 构建（路线图 L5 的提醒，这次没有验证）。如果做 G9（端到端加密）要用它们，有两个选择：

- 网页版保持 JS 构建（部署脚本的默认值就是），wasm 开关就不能用在带这些包的构建上；
- 或者给网页版另选纯 Dart 的实现（例如已经在用的 `cryptography` 包）。

做 G9 之前要先决定这一点；引入这些包之后 `flutter build web --wasm` 会直接编不过，`test/web/wasm_compat_test.dart` 不会替你发现，要在 G9 的验收里加一次 `flutter build web --wasm`。

## 11. 复现

```sh
# 1. 带占位地址的 wasm 包（登录页），本机试用
flutter build web --wasm --release \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=x
cp -R build/web /tmp/wc_app

# 2. 启动（冷 / 回访）；--wasm 0 强制 JS；--isolate 开 COOP/COEP；--net 4g；--cpu 4
node tool/web_bench/bench.mjs --dir /tmp/wc_app --mode startup --runs 3 --net broadband --cpu 4
node tool/web_bench/bench.mjs --dir /tmp/wc_app --mode startup --runs 3 --net broadband --cpu 4 --wasm 0

# 3. 滚动基准（单独的入口）
flutter build web --wasm --release -t tool/web_bench/scroll_bench.dart
cp -R build/web /tmp/wc_bench
node tool/web_bench/bench.mjs --dir /tmp/wc_bench --mode scroll --runs 3 --cpu 10
node tool/web_bench/bench.mjs --dir /tmp/wc_bench --mode scroll --runs 3 --cpu 10 --wasm 0

# 4. 冒烟（控制台错误 + 截图）、没有 WasmGC 的回退、断网重开（先给 wecord_sw.js 盖版本戳）
node tool/web_bench/bench.mjs --dir /tmp/wc_app --mode smoke --shot /tmp/shot.png
node tool/web_bench/bench.mjs --dir /tmp/wc_app --mode smoke --nowasmgc
node tool/web_bench/bench.mjs --dir /tmp/wc_app_stamped --mode offline

# 5. COOP/COEP 对跨站内容的影响
node tool/web_bench/coep_probe.mjs
```

每次 `flutter build` 会把 `analysis_options.yaml` 改写一下（加排除目录），不要提交这个改动。
