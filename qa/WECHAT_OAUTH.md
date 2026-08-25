# 微信登录联调清单

服务端已提供一次性授权链路：

1. `POST /v1/auth/oauth/wechat/start` 创建 5 分钟 state，并返回开放平台授权地址。
2. 微信回调到 `GET /v1/auth/oauth/wechat/callback`，服务端只把一次性 `code/state` 中转到 `xiangshang-youth://open?target=wechat-callback`。
3. iOS/Android 从自定义 scheme 取出 code/state，调用 `POST /v1/auth/oauth/wechat/exchange`。
4. 服务端向微信换取 openid/unionid，写入 `auth_identities`；首次授权创建家长账户，手机号保持未绑定，后续从家庭绑定流程补齐。

上线前由发布环境注入：

- `WECHAT_APP_ID`
- `WECHAT_APP_SECRET`
- `WECHAT_REDIRECT_URI`（必须是已备案 HTTPS 地址，并与开放平台配置完全一致）

不要把 AppSecret、微信 access token、code 或学生健康数据写入客户端日志。未配置三项生产参数时接口明确返回 `WECHAT_NOT_CONFIGURED`，客户端保留手机号/账号密码登录，不把 OAuth 失败伪装成登录成功。
