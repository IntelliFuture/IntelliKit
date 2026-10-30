# IntelliKit

IntelliFuture 的独立工具包。Swift tools 6.0，iOS 16 / macOS 13，无第三方依赖、UIKit 或 App 业务模型。

| 目录 | Product / import | 能力 |
|---|---|---|
| Sources/Foundation | IntelliKitFoundation | Apply：值类型配置副本、引用类型原地配置 |
| Sources/ImageProcessing | IntelliKitImageProcessing | 图片信息、方向修正、下采样、PNG/JPEG 编码、元数据和多帧策略 |
| Sources/Concurrency | IntelliKitConcurrency | Locked、CancellationHandle、AsyncCallback、异步序列连续去重 |
| Sources/Files | IntelliKitFiles | 自有临时工作区、完整文件发布、复制与生命周期清理 |
| Sources/Networking | IntelliKitNetworking | 流式受限 HTTP GET、响应校验、重定向和取消 |
| Sources/DiskCache | IntelliKitDiskCache | 独立命名空间的 Data 磁盘缓存、TTL、schema 与容量淘汰 |
| Sources/IntelliKit | IntelliKit | 显式类型别名聚合入口 |

每个能力独立 target，六个能力之间没有强制依赖；Networking / DiskCache 互不依赖，也不依赖 Concurrency、Files、图片模块或第三方包。

## 安装

仓库：`https://github.com/IntelliFuture/IntelliKit.git`。初期使用 main 分支；尚未发布稳定版本。
第二、三批 Concurrency / Files / Networking / DiskCache 目前位于 `codex/concurrency-and-files` 评审分支；合并前若要试用新模块，应选择该分支，main 仍只有第一批。

```swift
// 消费方 Package.swift 的 dependencies
.package(url: "https://github.com/IntelliFuture/IntelliKit.git", branch: "main")
// 消费方 target.dependencies，按需选择：
.product(name: "IntelliKitFoundation", package: "IntelliKit")
// 或 IntelliKitImageProcessing / IntelliKitConcurrency / IntelliKitFiles / IntelliKitNetworking / IntelliKitDiskCache / IntelliKit
```

## 基础配置

```swift
import IntelliKitFoundation // 或 import IntelliKit
import Foundation

let formatter = DateFormatter().apply { $0.dateFormat = "yyyy-MM-dd" }
```

只有 NSObject 继承体系默认遵循 Apply；自有值类型显式遵循，避免为所有标准类型添加全局一致性：

```swift
struct Settings: Apply { var retries = 1 }
let original = Settings()
let copy = original.apply { $0.retries = 3 }
// original.retries 仍为 1
let formatter = DateFormatter().apply { $0.dateFormat = "yyyy-MM-dd" }
```

引用类型返回同一实例；配置闭包抛错会向上传递，之前已发生的引用修改不回滚。

## 图片处理

```swift
import IntelliKitImageProcessing // 或 import IntelliKit

let options = ImageProcessingOptions(
  maximumPixelSize: 2048,
  maximumInputBytes: 8 * 1024 * 1024,
  outputFormat: .jpeg(quality: 0.8, background: .white),
  metadata: .strip,
  multipleFrames: .reject
)
let result = try ImageProcessor.process(sourceData, options: options)
let preview = try ImageProcessor.thumbnail(result.data, maximumPixelSize: 240)
let info = try ImageProcessor.inspect(fileURL: originalFileURL)
```

- 尺寸使用物理像素，方向按 EXIF 归一，不放大小图。thumbnail 明确读取第一帧。
- PNG 保留透明度；JPEG 按指定背景色合成。返回实际 typeIdentifier，不由原文件扩展名猜测格式。
- 默认剥离源元数据。preserve 只传递支持的 EXIF/GPS/IPTC/TIFF 信息，并修正方向及 EXIF 像素尺寸。
- 默认拒绝多帧。显式选择 preserveOriginal 时，多帧输入按原字节返回，**不会应用缩放、转码或元数据剥离**，isOriginal 为 true。适用于需要完整保留 GIF 等源文件的调用方。
- Data 和本地 URL 都检查输入大小；文件 API 只读，绝不删除或覆盖原件。文件权限、安全作用域及归属由调用方负责。
- 无网络请求；同步编解码可能较重，应由调用方安排在工作任务中。取消在阶段边界检查，不能中断 ImageIO 正在执行的单次 C 调用。
- 错误为结构化类型；展示文案和是否重试由 App 处理。

## 并发工具

```swift
import IntelliKitConcurrency // 或 import IntelliKit
import Foundation

let count = Locked(0)
count.withLock { $0 += 1 }

// 将自己的 callback API 转为单次 async 操作：
let result: Data = try await AsyncCallback.value { completion in
  let operation = client.start(completion: completion)
  return CancellationHandle { operation.cancel() }
}

for try await update in updates.removeDuplicates(by: \.version) {
  // 只移除连续相同的 version，保留每段的第一个元素。
}
```

示例中的 client / operation / updates 由消费方提供，不是库中的网络实现。输入结果和取消闭包须满足 Sendable 约束。

- **Locked**：iOS 18+ / macOS 15+ 使用 `Synchronization.Mutex`，旧系统回退 `NSLock`；`#if canImport(Synchronization)` 与 `#available` 分别控制模块导入和运行时选择，不提高部署基线。新类型隔离在带 `@available` 的私有存储类中，调用方 API 不变。保护短同步临界区，抛错后仍释放锁，保留已完成的修改。锁不可递归，不可在闭包中 await 或调用可能重新获取同一锁的外部代码。
- **CancellationHandle**：跨线程取消至多执行一次，释放 handle 不自动取消。
- **AsyncCallback**：首个完成或取消成为终态；支持同步回调、重复/并发回调、任务预先取消和句柄迟到。所有框架回调及取消代码均在锁外执行，完成结果不会被桥接状态继续持有。
- 注册闭包必须尽快返回，执行线程不保证是 MainActor；框架有主线程要求时应由适配层处理。注册与取消竞争时操作仍可能启动，返回的 handle 随即被取消，不能撤销已经发生的副作用。
- 没有取消 handle 的 API 也可接入，但只能停止等待，无法停止底层工作。不内置超时；既不回调也不取消的操作会继续等待。
- 异步序列保留首个 nil key、传播上游错误、在丢弃重复项时检查取消。使用 for try await；同一迭代器不支持并发 next，不强行声明任意上游/KeyPath 为 Sendable。

## 自有临时工作区

```swift
import IntelliKitFiles // 或 import IntelliKit

let workspace = try TemporaryWorkspace()
let exportURL = try workspace.write(exportData, named: "report.pdf")
let copyURL = try workspace.copyFile(from: originalFileURL, named: "original-copy.txt")
let files = try workspace.files()
// 保持 workspace 存活，直到系统分享等消费者完成使用这些 URL。
try workspace.cleanup()
```

- 每个实例只创建/管理独立 UUID 子目录；不会清空父目录，不接受任意现有目录作为“已拥有”的工作区。
- 文件名限定单个路径段。完整数据先写入隐藏 staging 文件，再移入目标；不覆盖已有目标。复制只接受普通本地文件，不移动或删除原件。
- files() 返回本实例成功发布过的 URL；调用方若自行修改这些路径，不保证内容仍存在或未改变。
- 显式 cleanup 报告真实错误，成功后可重复调用；实例释放时只尝试尽力清理。过早释放实例会使 URL 失效，因此分享/导出适配层必须持有工作区。
- 写入与清理串行化；根目录的身份或符号链接发生变化时拒绝操作。它不是对恶意进程并发修改父目录的系统沙箱，也不承担用户数据持久化。
- 文件读写/复制为同步操作，取消在阶段边界检查，不中断正在执行的单次系统文件复制。文件权限、数据保护级别和备份策略由消费方另行明确。

## 受限 HTTP 下载

```swift
import IntelliKitNetworking // 或 import IntelliKit
import Foundation

let policy = try HTTPDownloadPolicy(
  maximumBytes: 8 * 1024 * 1024,
  allowedMIMETypes: ["image/jpeg", "image/png"],
  timeout: 30
)
let payload = try await BoundedHTTPDownload.read(URLRequest(url: imageURL), policy: policy)
// payload.data 和 payload.response 来自同一次已完成的真实请求。
```

- 只接收无 body 的 GET。默认 HTTPS、同源重定向，最多 5 次；`.deny` 禁止重定向，`.https` 显式允许跨源 HTTPS。`allowsHTTP` 只用于调用方明确允许的 HTTP 地址，任何策略都拒绝 HTTPS 降级。
- 跨源重定向会清除全部调用方 headers。同源保留 headers；显式认证值请放在初始 URLRequest 中。每次请求使用独立 session，关闭环境中的 cookie/credential storage、URLCache 和 configuration.httpAdditionalHeaders，配置先复制再修改。
- 接受 2xx；校验 Content-Length 和每个实际交付的数据块，包含 URLSession 解压后的数据。没有长度或长度不准确也不能绕过缓冲区上限。响应回调交付时，声明长度本身超过上限会拒绝，包括压缩响应的 wire length。URLSession 可能暂缓交付只有头部且未结束的短响应，此时由资源超时结束，不能保证在网络刚收到头部时立即报 tooLarge。
- MIME 列表大小写不敏感、精确匹配，不支持 `image/*`。nil 不限制 MIME；空集合拒绝所有响应。MIME 是服务端声明，不证明文件内容类型。
- 返回有界内存 Data，适合网页、封面等小文件；它不是大文件下载器，也不是整个 URLSession 的进程内存上限。SDK 内部可能已经分配一个超限 chunk，库在追加前拒绝它。
- timeout 同时设置请求和完整资源超时；取消传播至底层 session。没有后台下载、续传、自动重试、账号鉴权或主机/IP 访问控制，接入方仍负责来源授权。
- `HTTPDownloadError` 区分策略、响应、HTTP 状态、MIME、大小和重定向错误；传输错误保留 URLError，任务取消返回 CancellationError。

## 通用磁盘缓存

```swift
import IntelliKitDiskCache // 或 import IntelliKit
import Foundation

let parent = try FileManager.default.url(
  for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
)
let cache = try DiskCache(
  parentDirectory: parent,
  namespace: "preview-v1-anonymous", // 登录数据请显式加入账号边界
  capacityBytes: 50 * 1024 * 1024
)
try await cache.write(payloadData, forKey: cacheKey, schemaVersion: 1, ttl: 3600)
let entry = try await cache.read(forKey: cacheKey, schemaVersion: 1)
let stale = try await cache.read(forKey: cacheKey, schemaVersion: 1, allowExpired: true)
try await cache.prune()
try await cache.remove(forKey: cacheKey)
try await cache.removeAll() // 仅本命名空间的缓存条目
await cache.close() // 释放独占占用，持久缓存仍保留
```

示例 payloadData / cacheKey 由消费方提供；JSON/Codable 编解码也由消费方选择。

- namespace 和 key 以 SHA-256 生成固定长度路径，不读取全局账号，不存在默认登录用户，也不会把原始 key 当路径。哈希不是加密，payload 仍明文保存。
- 每条二进制 plist 保存 data、schemaVersion、savedAt、expiresAt 和 key digest。ttl 必须显式传入：nil 不过期，0 立即过期，负数/非有限数报错。schema 不符、缺失或普通过期读取返回 nil；allowExpired 可读取过期值，由 App 决定 SWR 刷新和失败策略。
- actor 串行操作，一个命名空间只允许一个存活实例；进程间也使用 advisory 文件锁，重复打开抛 alreadyOpen。共享实例或先 close 后重开，避免多个实例的容量/淘汰竞争。释放实例会释放锁，不删除持久数据。
- write 原子替换单个条目，再按最早写入顺序淘汰，读取不刷新顺序（非 LRU）。容量计入编码后条目大小，超大写入保留已有值。重新以更小容量打开后，可显式 prune。
- 容量不包含文件系统块开销、owner/lock 文件和原子写入的临时副本；写入期间磁盘占用可能暂时超过容量。不是磁盘配额，也不保证断电持久性。
- 单条发布与后续淘汰不是事务：淘汰失败会抛错，但已发布条目不回滚。批量 prune/removeAll 或取消也可能已完成部分清理；不把失败伪装成缓存未命中或成功。
- 损坏条目和真实 I/O 错误会抛出，损坏数据保留到显式 remove/removeAll；读取按上限分块，不无界加载外部变大的条目。
- 只管理带所有权标记的专用子目录及固定命名条目，清理保留父目录和无关文件。拒绝条目符号链接/硬链接、根目录或 lock 被替换；不递归清空任意目录。这些检查不是对恶意进程并发篡改文件系统的系统沙箱。
- 父目录、文件保护、备份/隐私策略由调用方选择。系统或外部删除整个目录/owner 标记时会报告错误；接入方须关闭旧实例并重新建立可用缓存。模块不处理账号退出清理、网络刷新、数据库迁移或跨设备同步。

## 验证与来源

```sh
swift test
# iOS：替换为本机已有设备的 UUID，不新建设备
xcodebuild test -scheme IntelliKit-Package \
  -destination 'platform=iOS Simulator,id=<已有设备UUID>'
```

来源、行为差异见 [PROVENANCE.md](PROVENANCE.md)，实际验证见 [VALIDATION.md](VALIDATION.md)。
本轮没有迁移或修改任何消费 App。声明兼容基线与实际测试的 Xcode/OS 版本分别记录。
