# 向上少年 Windows 场地体测端

这是面向 Windows 11 的场地端对接工程，而不是管理后台的网页替代品。它遵循开发书的边缘运行方式：下载任务、花名册、规则与标定配置后，可在网络中断时继续叫号、采集、评分、保存证据；网络恢复后按事件唯一 ID 重放到中央服务。

## 工程边界

- `FieldClient.Core`：可测试的领域契约、中央服务 API、SQLite 本地出站队列和采集适配器接口。
- `FieldClient.Windows`：WPF 调度界面壳。实际深度相机、RGB 相机、显示屏、播报器和读卡器由实现 `ICaptureAdapter` 的厂商适配包接入。
- 中央服务：`backend/` 的 `/v1/field/*`，设备使用 `X-Device-Id`、时间戳、单次随机数、请求体 SHA-256（`X-Device-Body-Hash`）和 HMAC 签名，不使用教师或管理员登录态，也不在每次业务请求传输设备密钥。签名串为 `METHOD + URL + timestamp + nonce + bodyHash`，GET/空请求体使用空字节摘要。

## Windows 部署前置条件

- Windows 11；.NET 8 SDK / Desktop Runtime。
- 为每台边缘主机在后台注册测试点和设备，仅在注册/轮换时保存一次设备密钥到 Windows Credential Manager 或企业密钥服务。客户端默认读取 `XiangshangField:DeviceCredentials` 通用凭证（用户名为设备 ID、密码为设备密钥）；环境变量只用作首次部署回退，读取后会从进程环境清除。
- 使用本地 SQLite 文件保存任务快照、出站事件和证据上传进度；不要将学生资料写入临时目录或日志。
- 通过部署环境变量配置 HTTPS 中央服务地址。生产环境会拒绝旧式 `X-Device-Key` 请求；本地密钥仅用于派生 HMAC 签名。仍应通过 MDM、客户端证书或硬件 TPM 进一步保护设备密钥。

## 构建与本地验收

工程固定使用 .NET 8。仓库根目录的 `global.json` 锁定 SDK 版本；若本机没有全局 SDK，可按以下方式使用工作区隔离 SDK：

```bash
export DOTNET_ROOT="$(pwd)/.tooling/dotnet"
"$DOTNET_ROOT/dotnet" test field-client/FieldClient.Core.Tests/FieldClient.Core.Tests.csproj --configuration Release
"$DOTNET_ROOT/dotnet" build field-client/FieldClient.Windows/FieldClient.Windows.csproj --configuration Release
```

在 Windows 发布机执行单文件发布：

```powershell
pwsh ./field-client/publish-windows.ps1 -SelfContained
```

默认输出到 `field-client/artifacts/field-client-win-x64`；发布物仍需要由学校部署工具注入设备环境变量，不能在安装包内预置密钥。

Windows 启动前由部署工具注入以下环境变量，不能将设备密钥提交到仓库：

```text
FIELD_API_BASE_URL=https://api.example.edu
FIELD_DEVICE_ID=<后台注册后返回的设备 ID，仅首次部署回退>
FIELD_DEVICE_KEY=<仅显示一次的设备密钥，仅首次部署回退>
FIELD_LOCAL_DB=C:\ProgramData\XiangshangField\field-client.db
```

应用启动后会发送设备心跳、下载最新任务和队列；叫号及开始采集先落入 SQLite，再由“立即同步”按批次幂等上传。`session.open`、动作事件与 `session.complete` 都使用客户端会话 ID，因此可在同一断网批次中顺序补传，不依赖中央端预先返回的会话 ID。

推荐由 MDM 或部署脚本写入 Windows Credential Manager：

```powershell
cmdkey /generic:XiangshangField:DeviceCredentials /user:<FIELD_DEVICE_ID> /pass:<FIELD_DEVICE_KEY>
```

写入后删除部署期 `FIELD_DEVICE_ID`、`FIELD_DEVICE_KEY`，并避免将其写入注册表、安装包、日志或排障截图。

未安装经认证的相机/计时器适配器时，客户端会如实上报 `manual-fallback` 与未通过的 `field-health/v1` 自检；中央端会锁定正式开测，不会把人工兜底误报成视觉评分。接入硬件后，厂商 `ICaptureAdapter` 必须上报双深度相机、RGB 相机、GPU、同步偏差、存储、标定版本/校验和/误差和急停状态；仅通过中控门禁后才可生成正式会话。人工异常处理应在后台复核/补测流程中完成，不得绕过中央复核规则。

## 离线一致性契约

1. 每项边缘事实生成 UUID `clientEventId`；同一事件任意次数重传只生效一次。
2. 同一批事件有持久化的 `clientBatchId`；网络断开于中央端提交完成之后，重试仍使用原批次 ID，直接取得中央端缓存回执。
3. 中央端会校验重放的 `clientEventId`、事件类型与内容摘要完全一致；同一 ID 的不同内容会被拒绝并保留为客户端“冲突”，不自动覆盖中央记录。
4. 队列状态携带 `expectedVersion`；版本冲突时停止覆盖，重新下载花名册/队列后由教师或管理员处理。
5. 服务端处理中的批次最多保留五分钟租约；边缘主机或网络异常中断后可由同一设备用原批次 ID安全接管重放。
6. 证据先通过 `/v1/field/files/*` 上传，再将文件 ID 写入会话完成事件。
7. 成绩最终由中央端基于规则版本、标定版本、算法版本和置信度确认；低置信度自动进入复核。

> 本工程不虚构硬件算法实现。接入具体相机/计时器后，需要对每个设备型号做标定、准确度、断网、断电恢复和人工复核验收。
