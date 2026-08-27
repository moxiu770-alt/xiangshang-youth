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
| 后端静态检查 | `npm run check` | 通过 |
| 后端单元/契约 | `npm test` | 64/64 通过 |
| OpenAPI | `npm run lint:openapi` | 通过 |
| 跨端模型契约 | `check_model_contract.py` | 225 项不变量通过 |
| 前端契约 | `check_frontend_contract.py` | 通过 |
| Migration 序列 | `check_migration_sequence.py` | 39 个迁移通过 |
| 大文件边界 | `check_large_file_boundaries.py` | 24/24 通过 |
| 本地发布预检 | `release_preflight.py --target local` | 通过 |

## 本轮实缺陷修复

iOS 首次相机授权时，采集会话可在权限尚未决定时完成预配置，但授权成功后仅启动会话，没有重新发布“相机已就绪”。已改为授权成功后在串行队列重新提交当前镜头配置。无摄像头的 iOS Simulator 继续验证“明确错误＋重试”，不伪造可开始记录状态。

## 未完成的外部验收

1. 本机未提供独立 `TEST_DATABASE_URL`，Docker daemon 当前不可用；本地 PostgreSQL 集成测试未执行，不得连接开发或生产库代替。
2. 未提供专用家长/教师远程验收账号、测试孩子和可写 fixture ID；因此真实 HTTPS 远程生命周期未验收。
3. APNs、FCM、微信、短信、S3 对象存储和生产 Sentry 需要正式凭据与回调域名。
4. 动作/姿态模型仍为 `pending-human-validation`；缺少经合规授权、独立人工标注的真实儿童数据集，不能声称商业准确率或医疗诊断能力。
5. Android 本轮是 API 34 模拟器验收，不替代真机、平板、横屏、大字体和不同摄像头的完整矩阵。

