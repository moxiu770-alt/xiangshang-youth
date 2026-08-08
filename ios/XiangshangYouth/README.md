# 向上少年 iOS

SwiftUI + MVVM 的一期原生客户端。默认使用 `MockRepository`，网络层已通过 `ApiClient` 和各 API 类型预留，替换为 `RemoteRepository` 不影响页面层。联调时可通过 `XS_API_BASE_URL` 注入服务地址；URLSession 统一处理 token、超时、取消、401/403/5xx 与解码错误。

后端联调时，在 Xcode Scheme 的 Run > Arguments > Environment Variables 中同时设置 `XS_USE_REMOTE_DATA_SOURCE=1` 和 `XS_API_BASE_URL=https://<服务地址>/`；不设置前者时始终使用安全的 Mock 数据源。

## 启动

```bash
open XiangshangYouth.xcodeproj
# 或
xcodebuild -project XiangshangYouth.xcodeproj -scheme XiangshangYouth -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

登录页使用预填测试手机号即可进入；选择家长、教师或校长后进入对应工作台。

启动海报使用 `Assets.xcassets/LaunchPoster.imageset` 的 1x/2x/3x 清晰资源，画面已去除嵌入式时间、信号、电量和 Home 指示条；隐私清单位于 `PrivacyInfo.xcprivacy`，后端联调前无需修改页面路由。
