# 2026-08-28 本地候选版验收证据

本记录只证明实际执行的本地构建、自动测试和 iPhone 安装/启动，不代替真实儿童模型验证、远程业务联调或多机型真机矩阵。

## 本轮实施

- 八段家庭身体筛查增加足部独立近景取景，足部质量门不再复用全身取景证据。
- 后端发布门增加八个独立问题域：脊柱排列、肩/骨盆、头颈/上肢、躯干旋转、动态膝、步态、坐姿和足弓。任一域未完成独立人工验证时，家庭端不自动发布姿态风险等级。
- 模型审批合同升级为 `UY-MODEL-APPROVAL-1.1`，必须挂载八份独立报告，并校验样本量、报告 SHA-256、敏感度、特异度、阴性预测值、重复性 ICC 和不可判定率。
- iOS、Android 和后端的模型注册表同步到 `UY-MODELS-1.1`，消除 Remote 模式下的客户端版本误拒绝。
- 后端场地会话从 `server.js` 拆到 `fieldSessionService.js`；iOS 身体测评模型/草稿/重复性已分文件；Android 分析引擎、足部处理和快照生成已分文件。所有新边界均纳入行数预算。
- iOS 九步 UI 测试改用稳定的任务标识定位采集卡，不再依赖可变的中文展示标题。

## 已执行验证

- 后端：`npm run check` 通过；`npm test` 94/94 通过；家庭筛查专项 12/12 通过；`npm run lint:openapi` 通过。
- 跨端合同：前端合同通过；模型合同 233 项不变量通过；大文件边界全部通过；`git diff --check` 通过。
- Android：`:app:testDebugUnitTest` 通过；`:app:assembleDebug` 通过；`:app:lintDebug` 通过。本轮无连接 Android 设备，未执行 `connectedDebugAndroidTest`。
- iOS：模拟器 XCTest 107/107 通过。UI 套件首轮 9 项中 7 通过、1 跳过、1 旧定位失败；修复稳定任务 ID 后，失败的完整九步路径单独重跑通过。跳过项为未注入专用远程家长账号。
- iPhone 15：Debug 包完成 Apple Development 签名、安装并成功启动 `com.xiangshang.youth`。这只是安装/启动证据，摄像头八段精度仍需儿童、监护人和专业标注人员按协议实测。
- 本地发布预检：`release_preflight.py --target local --allow-missing-devices` 通过。

## 未通过/外部阻塞

- 本机没有独立 PostgreSQL 服务，因此未在本机运行 `npm run test:integration`；GitHub Actions run `33170822638` 已在独立 PostgreSQL 16 服务与独立 schema 中完成 migration、隔离 fixture、96 项单元/契约测试和集成测试，Backend integration 作业通过，未连接开发或生产库替代。
- 本机无 `dotnet`，本轮未重跑 Windows 场地端核心测试。
- Android `adb devices -l` 列表为空，本轮没有 Android 真机/模拟器证据。
- `api.risingteen.com` 当前被大陆云侧 `webblock` 拦截，HTTPS/TLS 不可用；源站 HTTP 只返回 Caddy 转 HTTPS。在备案/云侧接入修复前，RemoteRepository 现网全闭环无法验收。
- 未提供真实儿童独立人工标注集、每人 10 次重复性数据和八份分域报告。模型状态保持 `pending-human-validation`，不做商业准确率声明。
- 远程准备提交 `b0b02d0` 已推送到 `codex/pilot-content-ops-architecture`。同一 CI run 的 Production container contract 已验证生产 Compose、Caddy 正式域名配置、公网 IP 短期证书配置和 pilot overlay；该配置验证不冒充腾讯云实机部署或公网 `/readyz` 已通过。
- 推送 device installation 已完成服务端加密注册、撤销、失效回收与 OpenAPI；真实 APNs Key、Firebase 配置和通知网关凭据尚未注入，当前不得声称系统推送通过。
