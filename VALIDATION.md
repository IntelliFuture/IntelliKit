# 第一批验证 — 2026-10-26

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
