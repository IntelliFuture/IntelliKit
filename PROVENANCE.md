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
