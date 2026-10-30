# 第一批来源与边界

2026-10-26，仅提取共享能力；所有来源文件原地保留，没有修改 App 或迁移数据。

| 能力 | 本地来源路径（相对对应仓库） | 处理方式 |
|---|---|---|
| Apply | EveryDayJapanese-iOS/EveryDayJapanese/Extension/Foundation/Apply.swift；NGAPlus-iOS/NGAPlus/Shared/Apply.swift；mtn-iOS/Modules/Sources/Core/Apply.swift | 合并同一实现与公开契约，保留 Then 模式来源说明；仅 NSObject 默认一致性 |
| ImageIO 信息/下采样 | NGAPlus-iOS/NGAPlus/Shared/ReplyImagePreprocessor.swift；CapMemo/iOS/CapMemo/Services/MemoCoverLoader.swift、MemoExport.swift | 按共享接口重新组织，移除帖子/memo、固定尺寸、固定中文错误和缓存策略 |
| 编码/元数据策略 | NGAPlus 同上；mtn-iOS/MayChannel/Libraries/Utils/AssetCompressor/Image/ImageMetadataAttacher.swift | 从产品行为归纳为显式策略；检查编码终态，不搬上传管线和原 App 的元数据默认值 |

参考快照：CapMemo ca45459；EveryDayJapanese-iOS 302c978；NGAPlus-iOS dc59551。mtn 本机目录没有可读取的 Git HEAD，按实际文件审计，不虚构版本号。

首次包不包含 mtn 的上传压缩器、Photos 获取、日志或业务实体；不包含第三方图片库、DateTools 或全局 Task:Cancellable 一致性声明。

## 第二批：Concurrency / Files — 2026-10-26

| 工具 | 来源 | 共享化变化 |
|---|---|---|
| Locked | NGAPlus-iOS/NGAPlus/Domain/Services/Lock.swift | 只保留 NSLock 兼容内核及 Sendable 值约束，不引入 iOS 18 Mutex 或 Swift 6.1 的类型级 nonisolated |
| CancellationHandle / AsyncCallback | EveryDayJapanese-iOS/EveryDayJapanese/Extension/Observation/ObservationTracking+UIKit.swift；mtn-iOS/MayChannel/Libraries/SDWebImage/SDWebImageDownloader+downloadImageAsync.swift | 从 continuation/取消桥接需求重新实现单次终态状态机，覆盖提前取消、句柄迟到、重复回调与释放；不搬 Observation 循环、UIKit、SDWebImage 或任何框架适配器 |
| AsyncRemoveDuplicatesSequence | EveryDayJapanese-iOS/Core/Sources/Extension/AsyncRemoveDuplicatesSequence.swift | 保留连续去重语义；用显式 missing/value 区分首次状态与 nil key，增加取消检查及主线程消费测试 |
| TemporaryWorkspace | NGAPlus-iOS/NGAPlus/Shared/LongImageExporter.swift；CapMemo/iOS/CapMemo/Services/MemoExport.swift 的自有临时产物约定 | 去除 topicID、图片编码和分享控制器，只管理新建 UUID 目录；加入无覆盖发布、普通文件复制、路径及目录身份检查，显式报告清理失败 |

第二批没有修改第一批图片行为，没有迁移任何 App。Concurrency 与 Files 各自独立 product/target，均无第三方或其他能力模块依赖；IntelliKit 聚合入口同步导出公开类型。

App 中已有同名 AsyncSequence 扩展未来迁移时应移除或转发，避免定义冲突。用户草稿、录音原件、缓存账号域、任意目录删除和框架特有取消语义继续留在消费方。

## 第三批：Networking / DiskCache / Mutex — 2026-10-26

| 能力 | 本地来源 | 共享化变化 |
|---|---|---|
| BoundedHTTPDownload | CapMemo/iOS/CapMemo/Services/BoundedHTTPDownload.swift；同仓库 Tests/BoundedHTTPDownloadTests.swift 的传输夹具 | 提取独立 Networking target；保留 header/chunk 限额和取消状态机，新增 throwing 配置、结构化状态码错误、GET/HTTPS/重定向策略、完整资源超时与 session 隔离；不搬 Web 导入、封面或 memo 行为 |
| DiskCache | EveryDayJapanese-iOS/Core/Sources/Cache/SWRCacheStore.swift、SWRCacheTypes.swift；EveryDayJapanese/AudioManager/CacheFileManager.swift | 从 actor/Data envelope/容量淘汰需求重新组织；namespace/key 哈希、显式 TTL/schema、独占目录锁和归属检查、原子写入及可观察错误；不搬 Pluto 当前账号、SWR 网络调度、音频/视频目录或 shared 全局实例 |
| Locked Mutex 分支 | 既有 IntelliKitConcurrency.Locked；本机 Synchronization.swiftinterface 与 Apple Mutex 文档 | 本轮用户要求启用版本判断：iOS18/macOS15 及以上用 Mutex，旧系统 NSLock；保留 Value:Sendable、泛型返回值和 rethrows 语义；不采用需要新版编译器的类型级 nonisolated |

来源快照仍为 CapMemo ca45459、EveryDayJapanese-iOS 302c978；本轮只读这些来源，未迁移四个 App。Networking 和 DiskCache 均仅依赖系统框架，互相独立，也不依赖其他 IntelliKit 能力。

容量淘汰沿用最早写入优先，不声称 LRU。缓存账号隔离、刷新与重试、文件保护、清理时机继续属于接入方。缓存不再吞掉所有 I/O 错误；需要 best-effort 行为的 App 可明确决定如何处理错误。

Mutex 官方参考：https://developer.apple.com/documentation/synchronization/mutex
本机 SDK 声明：`@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)`。

## 第四批：MoreApps（同一开发者的更多 App）— 2026-10-30

| 能力 | 本地来源（相对对应仓库） | 共享化变化 |
|---|---|---|
| MoreApp 模型 | EveryDayJapanese-iOS/Core/Sources/Model/MoreApps/MoreAppInfo.swift | 更名 `MoreAppInfo` → `MoreApp`，字段与公开契约不变；移出 App 层 |
| 语言映射 | EveryDayJapanese-iOS/Core/Sources/Repository/MoreAppsRepository.swift（`lookupLanguageCode`） | 提取为独立 `MoreAppsLanguage.lookupCode(forAppLanguage:)`，保留 en/zh-Hans/zh-Hant/ko/vi/ja 映射与非法输入判断 |
| 查询仓库 | 同上 `MoreAppsRepository` | 传输从 Alamofire 改为 IntelliKitNetworking 的 `BoundedHTTPDownload`；保留 itunes lookup URL、software 过滤、bundle 去重/排除、http→https 图标升级、HTTP 400 去 `lang` 重试与 `failureKind` 分类；`developerID`/排除项/语言全部改由调用方传入，不再内置 `MoreAppsConfiguration` |
| 列表视图 | EveryDayJapanese-iOS/EveryDayJapanese/Controller/Settings/MoreApps/MoreAppsView.swift、MoreAppsViewModel.swift | 重实现为 `MoreAppsListModel`（`ObservableObject`，兼容 iOS 16，非 `@Observable`）+ `MoreAppsListView`；图标用系统 `AsyncImage` 替换 Kingfisher，文案经 `MoreAppsListStrings` 注入，分析日志改为可选回调；SwiftUI 代码以 `#if canImport(SwiftUI)` 包裹 |

参考快照：EveryDayJapanese-iOS 302c978（只读来源，未修改或迁移该 App）。MoreApps 仅依赖系统框架与 IntelliKitNetworking，不引入 Alamofire、Kingfisher 或任何业务模型/账号；不内置具体开发者 ID、bundle 排除列表或 `EDJAnalytics`，可随 IntelliKit 一并开源。`MoreAppsConfiguration`（开发者 ID、排除 bundle）、Firebase 打点和 App 主题样式继续留在各自 App。
