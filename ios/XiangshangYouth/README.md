# 向上少年 iOS

SwiftUI + MVVM 的一期原生客户端。默认使用 `MockRepository`，网络层已通过 `ApiClient` 和各 API 类型预留，替换为 `RemoteRepository` 不影响页面层。

## 启动

```bash
open XiangshangYouth.xcodeproj
# 或
xcodebuild -project XiangshangYouth.xcodeproj -scheme XiangshangYouth -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

登录页使用预填测试手机号即可进入；选择家长、教师或校长后进入对应工作台。
