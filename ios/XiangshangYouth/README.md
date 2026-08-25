# 向上少年 iOS

SwiftUI + MVVM 的一期原生客户端。Debug 默认使用 `MockRepository`，网络层已通过 `ApiClient` 和各 API 类型预留，替换为 `RemoteRepository` 不影响页面层。Release 强制使用远程数据源，且构建阶段会拒绝占位地址；联调时可通过 `XS_API_BASE_URL` 注入服务地址；URLSession 统一处理 token、超时、取消、401/403/5xx 与解码错误。

后端联调时，在 Xcode Scheme 的 Run > Arguments > Environment Variables 中同时设置 `XS_USE_REMOTE_DATA_SOURCE=1`、`XS_API_BASE_URL=https://<服务地址>/` 和可选的 `XS_SCHOOL_ID=<学校ID>`；不设置前者时始终使用安全的 Mock 数据源。

归档或 Release 构建必须由 CI/密钥系统覆盖 `API_BASE_URL=https://<正式或预发布中央服务>/`；项目内置的 `https://api.example.com/` 仅用于 Debug 占位，Release 会直接失败，不能生成误连演示地址或回落 Mock 的安装包。

## 启动

```bash
open XiangshangYouth.xcodeproj
# 或
xcodebuild -project XiangshangYouth.xcodeproj -scheme XiangshangYouth -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

登录页使用预填测试手机号即可进入；移动端选择家长或教师后进入对应工作台。学校管理数据由后台数据看板提供，移动端不再承载校长工作台。

启动海报使用 `Assets.xcassets/LaunchPoster.imageset` 的 1x/2x/3x 清晰资源，画面已去除嵌入式时间、信号、电量和 Home 指示条；隐私清单位于 `PrivacyInfo.xcprivacy`，后端联调前无需修改页面路由。
