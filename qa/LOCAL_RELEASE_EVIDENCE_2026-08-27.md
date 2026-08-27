# 2026-08-27 本地可发布基线证据

本记录只证明候选提交的本地工程质量。它不代表生产密钥、真实远程账号、推送、对象存储或儿童动作模型准确率已验收。

## 领域拆分

- iOS `BodyPostureAssessment.swift`：673 行降至 381 行。
- iOS 新建 `BodyCaptureQualityGate.swift` 238 行、`PostureMetricCalculator.swift` 52 行。
- Android `BodyPostureAssessment.kt`：784 行降至 47 行。
- Android 新建 `PostureScreeningRules.kt` 181 行、`PostureAssessmentReport.kt` 214 行、`PostureMetricCalculator.kt` 27 行、`BodyCaptureQualityGate.kt` 320 行。
- 24 个重点文件均受 `qa/large_file_budgets.json` 行数门禁约束。
- 后端 `server.js` 当前 2907 行；仍须继续抽离 AuthSession、AdminSchool 和场地端编排，新功能不得再写回主文件。

## 已执行验证

| 范围 | 命令/环境 | 结果 |
|---|---|---|
| iOS Debug 构建 | iPhone 17 Pro / iOS 26.5 Simulator | 通过 |
| iOS XCTest | `XiangshangYouthTests` | 100/100 通过 |
| iOS UI Test | `XiangshangYouthUITests` | 9 项：8 通过、0 失败、1 远程账号用例按设计跳过 |
| Android JVM | `:app:testDebugUnitTest` | 116/116 通过 |
| Android Debug | `:app:assembleDebug` | 通过 |
| Android Lint | `:app:lintDebug` | 通过 |
| Android Compose UI | API 34 `XiangshangYouth_QA_API34` AVD | 6/6 通过 |
| Android Compose UI | API 35 `XiangshangYouth_CI_API35` AVD，冷启动、软件渲染 | 6/6 通过 |
| 后端静态检查 | `npm run check` | 通过 |
| 后端单元/契约 | `npm test` | 64/64 通过 |
| 后端 PostgreSQL 集成 | 独立 `xiangshang_integration` schema | 4/4 通过，覆盖活动/预约生命周期、设备同步和 TOTP |
| 数据库备份恢复 | PostgreSQL 16，独立恢复库 | 创建、校验、恢复、39 个 migration 和种子数据核验通过 |
| OpenAPI | `npm run lint:openapi` | 通过 |
| 跨端模型契约 | `check_model_contract.py` | 225 项不变量通过 |
| 前端契约 | `check_frontend_contract.py` | 通过 |
| Migration 序列 | `check_migration_sequence.py` | 39 个迁移通过 |
| 大文件边界 | `check_large_file_boundaries.py` | 24/24 通过 |
| 本地发布预检 | `release_preflight.py --target local` | 通过 |

## 本轮实缺陷修复

iOS 首次相机授权时，采集会话可在权限尚未决定时完成预配置，但授权成功后仅启动会话，没有重新发布“相机已就绪”。已改为授权成功后在串行队列重新提交当前镜头配置。无摄像头的 iOS Simulator 继续验证“明确错误＋重试”，不伪造可开始记录状态。

后端独立 PostgreSQL 集成测试实际暴露并修复了三处拆分回归：孩子绑定路由缺少 `studentForUser` 注入、活动路由缺少请求体注入、活动创建路由会误吞 `/cancel`。备份恢复演练同时修复了 `pg_restore` 未指定目标数据库以及 CI `createdb --dbname` 参数错误。上述问题均由真实数据库生命周期测试覆盖，不再以语法检查替代。

Android JVM 测试原先依赖开发机绝对路径读取姿态和跟练校准资产，已改为按 Gradle 模块根、Android 根和仓库根解析。API 35 Compose 测试在本机冷启动 AVD 6/6 通过；CI 同步保存 instrumentation JUnit/HTML/logcat。过期的第三方 emulator composite action 在 GitHub 托管机上对 API 34/35 均会在 adb/Gradle 启动前退出且没有生成 JUnit，工作流已改为直接配置 KVM、创建 AVD、等待 `sys.boot_completed`、执行测试并保存模拟器日志。托管烟测使用稳定 API 34；API 35 继续作为本机维护 AVD和 Android 15 真机发布矩阵门禁，不能用 API 34 替代。

平台 run `33059894062` 的 Android 作业在 JUnit 启动前失败。下载完整作业日志后确认根因是 GitHub 托管机共享出口访问 `repo.maven.apache.org` 连续收到 HTTP 429，不是测试断言或 App 构建回归。Gradle 现优先使用 Maven Central 官方备用入口 `repo1.maven.org`，只对明确的 429 做最多三次有限重试，并把原始 Gradle 日志作为 CI artifact 保存；本机使用相同仓库配置重新执行 JVM 测试通过。

后续托管 Android 验收还暴露了两个 CI 取证问题：AVD 创建与运行使用了不同的目录，以及 `connectedDebugAndroidTest` 结束后卸载目标 App，导致应用私有目录中的启动图证据无法拉取。现已统一 `ANDROID_AVD_HOME`，在测试前验证 AVD 名称，并把启动图截图写入干净模拟器的公共 Download 目录再上传。本机 API 35 完整 6/6 通过，PNG 证据为 1080×1920、约 1.17 MB。

候选提交 `105f0a5` 的最终平台 CI run `33064133368` 全部通过：后端 PostgreSQL 集成、生产容器契约、源码完整性、Windows 场地端、iOS 与 Android 六个作业均为 success。同一提交的 Release 中央服务契约 run `33064133327` 也已通过。

## 未完成的外部验收

1. 独立本地 PostgreSQL 集成和恢复演练已通过，但未提供专用家长/教师远程验收账号、测试孩子和可写 fixture ID；因此真实 HTTPS 远程生命周期仍未验收。
2. 公网 DNS 已指向试点服务器，但从发布机直连广州源站时，HTTP 80 当前被重定向至 DNSPod `webblock`，HTTPS 不能完成正常响应。需先完成或确认大陆域名备案/云侧接入状态并恢复网关，才能执行远程 smoke。
3. APNs、FCM、微信、短信、对象存储和生产 Sentry 仍需要正式凭据、回调域名与真实送达验收。
4. 动作/姿态模型仍为 `pending-human-validation`；缺少经合规授权、独立人工标注的真实儿童数据集，不能声称商业准确率或医疗诊断能力。
5. Android API 34/35 模拟器验收不替代 Android 真机、平板、横屏、大字体和不同摄像头的完整矩阵；iOS 也仍需同等级真机证据。
