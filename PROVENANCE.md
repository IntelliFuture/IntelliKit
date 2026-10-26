# 第一批来源与边界

2026-10-26，仅提取共享能力；所有来源文件原地保留，没有修改 App 或迁移数据。

| 能力 | 本地来源路径（相对对应仓库） | 处理方式 |
|---|---|---|
| Apply | EveryDayJapanese-iOS/EveryDayJapanese/Extension/Foundation/Apply.swift；NGAPlus-iOS/NGAPlus/Shared/Apply.swift；mtn-iOS/Modules/Sources/Core/Apply.swift | 合并同一实现与公开契约，保留 Then 模式来源说明；仅 NSObject 默认一致性 |
| ImageIO 信息/下采样 | NGAPlus-iOS/NGAPlus/Shared/ReplyImagePreprocessor.swift；CapMemo/iOS/CapMemo/Services/MemoCoverLoader.swift、MemoExport.swift | 按共享接口重新组织，移除帖子/memo、固定尺寸、固定中文错误和缓存策略 |
| 编码/元数据策略 | NGAPlus 同上；mtn-iOS/MayChannel/Libraries/Utils/AssetCompressor/Image/ImageMetadataAttacher.swift | 从产品行为归纳为显式策略；检查编码终态，不搬上传管线和原 App 的元数据默认值 |

参考快照：CapMemo ca45459；EveryDayJapanese-iOS 302c978；NGAPlus-iOS dc59551。mtn 本机目录没有可读取的 Git HEAD，按实际文件审计，不虚构版本号。

首次包不包含 mtn 的上传压缩器、Photos 获取、日志或业务实体；不包含第三方图片库、DateTools 或全局 Task:Cancellable 一致性声明。
