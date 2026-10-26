# IntelliKit

IntelliFuture 的独立工具包。Swift tools 6.0，iOS 16 / macOS 13，无第三方依赖、UIKit 或 App 业务模型。

| 目录 | Product / import | 能力 |
|---|---|---|
| Sources/Foundation | IntelliKitFoundation | Apply：值类型配置副本、引用类型原地配置 |
| Sources/ImageProcessing | IntelliKitImageProcessing | 图片信息、方向修正、下采样、PNG/JPEG 编码、元数据和多帧策略 |
| Sources/Concurrency | IntelliKitConcurrency | Locked、CancellationHandle、AsyncCallback、异步序列连续去重 |
| Sources/Files | IntelliKitFiles | 自有临时工作区、完整文件发布、复制与生命周期清理 |
| Sources/IntelliKit | IntelliKit | 显式类型别名聚合入口 |

每个能力独立 target，四个能力之间没有强制依赖；只选 Files 不会引入图片模块。没有预建缓存、网络客户端或任意目录清理模块。

## 安装

仓库：`https://github.com/IntelliFuture/IntelliKit.git`。初期使用 main 分支；尚未发布稳定版本。
第二批 Concurrency / Files 目前位于 `codex/concurrency-and-files` 评审分支；合并前若要试用新模块，应选择该分支，main 仍只有第一批。

```swift
// 消费方 Package.swift 的 dependencies
.package(url: "https://github.com/IntelliFuture/IntelliKit.git", branch: "main")
// 消费方 target.dependencies，按需选择：
.product(name: "IntelliKitFoundation", package: "IntelliKit")
// 或 IntelliKitImageProcessing / IntelliKitConcurrency / IntelliKitFiles / IntelliKit
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

- **Locked**：保护短同步临界区，抛错后仍释放锁，保留已完成的修改。锁不可递归，不可在闭包中 await 或调用可能重新获取同一锁的外部代码。
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

## 验证与来源

```sh
swift test
# iOS：替换为本机已有设备的 UUID，不新建设备
xcodebuild test -scheme IntelliKit-Package \
  -destination 'platform=iOS Simulator,id=<已有设备UUID>'
```

来源、行为差异见 [PROVENANCE.md](PROVENANCE.md)，实际验证见 [VALIDATION.md](VALIDATION.md)。
本轮没有迁移或修改任何消费 App。声明兼容基线与实际测试的 Xcode/OS 版本分别记录。
