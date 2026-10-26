# IntelliKit

IntelliFuture 的独立工具包。Swift tools 6.0，iOS 16 / macOS 13，无第三方依赖、UIKit 或 App 业务模型。

| 目录 | Product / import | 能力 |
|---|---|---|
| Sources/Foundation | IntelliKitFoundation | Apply：值类型配置副本、引用类型原地配置 |
| Sources/ImageProcessing | IntelliKitImageProcessing | 图片信息、方向修正、下采样、PNG/JPEG 编码、元数据和多帧策略 |
| Sources/IntelliKit | IntelliKit | 显式类型别名聚合入口 |

每个能力独立 target；Foundation product 不依赖图片模块。没有预建缓存、网络、文件删除或并发工具模块。

## 安装

仓库：`https://github.com/IntelliFuture/IntelliKit.git`。初期使用 main 分支；尚未发布稳定版本。

```swift
// 消费方 Package.swift 的 dependencies
.package(url: "https://github.com/IntelliFuture/IntelliKit.git", branch: "main")
// 消费方 target.dependencies，按需选择：
.product(name: "IntelliKitFoundation", package: "IntelliKit")
// 或 IntelliKitImageProcessing / IntelliKit
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

## 验证与来源

```sh
swift test
# iOS：替换为本机已有设备的 UUID，不新建设备
xcodebuild test -scheme IntelliKit-Package \
  -destination 'platform=iOS Simulator,id=<已有设备UUID>'
```

来源、行为差异见 [PROVENANCE.md](PROVENANCE.md)，实际验证见 [VALIDATION.md](VALIDATION.md)。
本轮没有迁移或修改任何消费 App。声明兼容基线与实际测试的 Xcode/OS 版本分别记录。
