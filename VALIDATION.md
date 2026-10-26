# 验证记录

## 第三批：Networking / DiskCache / Mutex — 2026-10-26

- 实际工具链：Xcode 27.1 / Swift 6.4，macOS 27.0.1。声明基线继续为 Swift tools 6.0、iOS 16 / macOS 13；未使用 Swift 6.0 原版编译器或 iOS16/macOS13 真正运行。
- 最终 macOS：68/68 测试定义 PASS，Networking 12（9 XCTest + 3 Swift Testing）、DiskCache 14、Concurrency 16、Files 13、聚合/首批 13。
- 最终 iOS 17.5：同样 68/68 PASS，TEST SUCCEEDED。实际验证不支持 Mutex 的系统自动回退；两个锁后端均在现代 host 上通过 1000 次并发更新/抛错解锁的参数化测试。参数展开不额外增加测试定义数量。
- 最终 iOS 18.5：68/68 PASS，TEST SUCCEEDED，实际验证系统支持 Mutex 时的自动选择及强制 NSLock 参数用例。
- iOS 16 deployment target 的 Release 编译 BUILD SUCCEEDED，日志 `/tmp/IntelliKit-third-release.log`。之后的改动仅为测试夹具/文档；临时诊断 print 已移除，生产源码恢复为相同内容。
- Networking / DiskCache 的测试 targets 各自只依赖对应 product；聚合入口另测。没有第三方 SDK，没有调用任何真实业务服务。网络测试使用 URLProtocol 脚本和仅绑定 127.0.0.1 的本机 HTTP server；缓存测试仅使用新建临时目录。
- 下载覆盖：非法策略/URL/method/body、状态码、MIME、声明及实际长度、恰好上限、取消/预先取消、真实同源重定向/次数限制、跨源头部剥离策略、拒绝降级、gzip 解压后大小、未发送终结 chunk 的流提前中止、完整资源超时、configuration headers 隔离。
- 缓存覆盖：重开持久化、长/带路径 key 哈希、namespace 隔离、TTL 精确边界/显式过期读取/prune、schema 不符、编码体积限额、原子替换、最早写入淘汰、缩容 prune、重复打开、关闭、50 并发写入和预先取消、损坏/错 key envelope、symlink/目录/lock 替换、marker 丢失、缺失目录 I/O、拒绝接管无标记目录、清理保留父目录/无关文件/原件。

### 最终证据

- macOS：`/tmp/IntelliKit-third-verified-macos.log`。
- iOS17.5（复用 7EC5A2CC-4F51-4BFD-9D00-822EE6E7017E）：`/tmp/IntelliKit-third-legacy-verified.log` 与 `/tmp/IntelliKit-third-legacy-verified.xcresult`。
- iOS18.5（复用 21A4182C-BE69-47A6-86B3-ED2272572A98）：`/tmp/IntelliKit-third-modern-verified.log` 与 `/tmp/IntelliKit-third-modern-verified.xcresult`。
- 初轮 iOS27.0 66/66 与 Release 通过分别见 `/tmp/IntelliKit-third-ios.log`、`/tmp/IntelliKit-third-release.log`；后来增加两项真实 HTTP 边界测试，不能把该初轮计为最终 68 项通过。

### 失败诊断与实际限制

- 首次编译因提取测试夹具仍使用旧参数签名失败，修正后复验通过，记录 `/tmp/IntelliKit-third-initial.log`。
- 旧 iOS 的自定义 URLProtocol 对未完成的短响应暂不交付 delegate 回调，导致 header-only 夹具停滞；该批和定向诊断主动终止，采样 `/tmp/IntelliKit-third-legacy-hang.sample`，原日志 `/tmp/IntelliKit-third-legacy.log`、`/tmp/IntelliKit-third-legacy-diagnosis.log`、`/tmp/IntelliKit-third-legacy-network.log` 保留，不计通过。
- 改用真实 HTTP 后发现：header-only 保持连接时，macOS/iOS17.5 的 URLSession 也可能延迟交付 response，最终触发 URLError.timedOut，而不是立即 tooLarge。原先“一收到 wire headers 就必须拒绝”的测试假设错误，失败分别保留于 `/tmp/IntelliKit-third-final-macos.log` 与 `/tmp/IntelliKit-third-legacy-final.log`。生产实现没有为了测试绕过大小校验；当前契约明确在 response 回调校验 header，并用资源超时约束停滞。新增测试接受明确的 tooLarge 或 timedOut，拒绝成功和无限等待；真实 chunked 流仍严格要求 tooLarge 且服务端尚未结束。
- 传输上限约束库内累计 Data，不是整个 URLSession 内存上限；服务端 MIME 不是内容验证。跨源 HTTPS 凭据剥离通过策略测试，未搭建跨站真实 TLS 服务。
- 缓存采用 actor 和 advisory 文件锁，不是抵抗恶意文件系统并发篡改的隔离沙箱；容量不是整个卷的配额，未执行断电/崩溃、磁盘满或超大容量压力测试。批量清理和发布后淘汰不是事务。无 App 迁移、真机或账号接入验收。

## 第二批：Concurrency / Files — 2026-10-26

- 实际环境沿用 Xcode 27.1 / Swift 6.4、macOS 27.0.1；复用现有 iPhone 18 Pro / iOS 27.0（254624F0-8F02-40F7-AF57-1A9876A8AA1A）。没有创建新设备，没有修改或运行四个消费 App。
- 最终 `swift test`：41/41 PASS，分为 IntelliKitTests 12、FilesTests 13、ConcurrencyTests 16。FilesTests 中有一项包含 7 个非法文件名参数用例，不将参数额外累加为测试定义数量。
- 最终 iOS 完整批次：同样 41/41 PASS，TEST SUCCEEDED。
- iOS 16 deployment target 的 umbrella Release 编译 BUILD SUCCEEDED。兼容声明仍为 Swift tools 6.0 / iOS 16 / macOS 13；旧系统运行与 Xcode 16.2 实编译未执行。
- 锁：1000 次并发修改、抛错释放、取消 handle 至多执行一次及可重入取消。
- 回调桥接：同步/重复/100 路并发回调、失败、预先取消、注册内取消后迟到 handle、没有完成回调时取消、100 轮完成与取消竞争、框架保留回调时成功结果可释放。
- 序列：连续去重、首个 nil key、非连续重复保留、独立迭代器、上游错误、MainActor 消费、开始前取消及等待上游期间取消。
- 文件：写入/复制/列表、原件保留、非法路径、已有文件和符号链接保护、发布失败后的 staging 清理、显式/重复/释放时清理、根目录缺失/替换/符号链接、30 路并发写入和取消不发布文件。
- 所有测试使用内存回调或新建临时目录，不访问网络、账号、用户图片或 App 数据。
- 单模块测试 targets 分别只依赖 IntelliKitConcurrency / IntelliKitFiles；聚合入口也有集成回归。新模块不依赖第一批模块或第三方 SDK。

最终证据：`/tmp/IntelliKit-second-final-macos.log`、`/tmp/IntelliKit-second-final-ios.log`、`/tmp/IntelliKit-second-final-release.log`，结果包 `/tmp/IntelliKit-second-final-ios.xcresult`。早先 37/39/40 项是补齐回归过程中的历史批次；交付只按最终 41 项源码计数。准备阶段一次 SwiftPM 调用因尚未创建测试目录退出，未执行测试，不计通过。

临时工作区是协作进程中的生命周期工具，不是抵御恶意进程并发修改父目录的系统沙箱；未执行压力容量、断电/崩溃一致性或真实外部 SDK 的取消验收。底层同步系统复制不能在调用中途强制中断。显式清理错误会抛出，deinit 仅尽力清理。

## 第一批验证 — 2026-10-26

## 实际环境

- Xcode 27.1 / Swift 6.4，Swift tools manifest 为 6.0。
- macOS 27.0.1；现有 iPhone 18 Pro 模拟器 / iOS 27.0，UUID 254624F0-8F02-40F7-AF57-1A9876A8AA1A。
- 没有创建模拟器；没有启动或迁移四个来源 App。测试图片由内存生成，不读取用户图片。

## 最终结果

- `swift test`：11/11 PASS，包含基础模块/聚合入口、值/引用/抛错语义及图片处理。
- `xcodebuild test -scheme IntelliKit-Package -destination 'platform=iOS Simulator,id=254624F0-8F02-40F7-AF57-1A9876A8AA1A' -parallel-testing-enabled NO`：11/11 PASS，TEST SUCCEEDED。
- `xcodebuild build -scheme IntelliKit -configuration Release -destination 'generic/platform=iOS Simulator' IPHONEOS_DEPLOYMENT_TARGET=16.0`：BUILD SUCCEEDED。
- 图片检查覆盖 EXIF 方向、尺寸上限/不放大、PNG 实际透明像素、JPEG 白底、多帧拒绝/原字节保留、GPS 剥离/保留、非法参数/坏数据/超限、本地文件不变和取消。
- 每个能力一个独立 product；Foundation target 不依赖 ImageProcessing，IntelliKit 通过显式类型别名聚合。单模块与聚合导入均在测试源码中验证。

## 证据与限制

最终原始日志：`/tmp/IntelliKit-first-batch-final-mac.log`、`/tmp/IntelliKit-first-batch-final-ios.log`、`/tmp/IntelliKit-first-batch-final-release.log`；iOS 结果包 `/tmp/IntelliKit-first-batch-final-ios.xcresult`。
初始两平台同名 11 项亦通过；随后增加了阶段间取消检查和 PNG 实际 alpha 断言，以上最终批次才是交付依据。

最低 iOS 16 / macOS 13 和 Swift tools 6.0 是声明/编译基线；未在这些旧系统运行，也未使用 Xcode 16.2 实编译。
不将 ImageIO 阶段间取消扩大为可中断单次系统 C 调用。没有 App 集成、真实照片/相机来源、真机、超大图片压力或全部格式验收。
