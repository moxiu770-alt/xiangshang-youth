# 崩溃监控与灰度发布操作

## 1. 注入配置（不得提交真实值）

Android CI 或本机私有 `~/.gradle/gradle.properties`：

```properties
sentryDsn=https://public@example.ingest.sentry.io/123
releaseChannel=pilot
rolloutConfigUrl=https://config.example.com/xiangshang-youth/rollout.json
featureOverrides=
```

iOS 在 CI 的 `xcodebuild` 中覆盖：

```bash
xcodebuild -project ios/XiangshangYouth/XiangshangYouth.xcodeproj -scheme XiangshangYouth \
  -configuration Release SENTRY_DSN='https://public@example.ingest.sentry.io/123' \
  RELEASE_CHANNEL=pilot ROLLOUT_CONFIG_URL='https://config.example.com/xiangshang-youth/rollout.json' archive
```

无 DSN 时两端监控 SDK 都不会初始化；无灰度 URL 时都使用内置 100% 稳定规则。两个地址均强制使用 HTTPS。

## 2. 灰度规则

配置格式见 `qa/rollout-config.example.json`。每个功能以“匿名安装 ID + 功能 key”确定 0–99 桶，因此升级、重启和进入不同角色后分桶不变。设备 ID 不上传到配置服务。

建议节奏：内部 0% 验证回退 → 5%（24 小时）→ 10%（48 小时）→ 25% → 50% → 100%。任一异常率、关键路径失败率或客服反馈越阈值，立即把 `enabled` 设为 `false` 或 `rolloutPercent` 设为 `0`；客户端保留最后一份有效规则，配置请求失败不会清空现有页面。

## 3. Sentry 数据边界

- 允许：崩溃堆栈、应用版本、系统版本、机型、发布渠道、手工记录的功能标签。
- 禁止：姓名、手机号、学校/班级、学生标识、照片/视频、姿态关键点、BMI/身高/体重、输入内容、截图和视图层级。
- SDK 已关闭默认 PII 与用户交互 breadcrumb。启用前在 Sentry 项目中设置数据保留期、访问角色、删除流程和告警阈值。

## 4. 上线前证明

在 `pilot` 渠道用测试账号制造一次非个人化测试异常，确认事件到达且不含敏感字段；再发布 10% 灰度规则，在同一真机重启三次确认分桶稳定，最后把规则回退为 0% 并复验。
