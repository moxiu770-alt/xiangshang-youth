# 真实远程业务验收

## 隔离 fixture 与推送设备

专用验收账号和业务对象必须通过下方 provisioner 写入隔离 school scope，禁止复用真实学校和儿童记录。移动端取得 APNs/FCM token 后，使用当前登录会话调用 `POST /v1/notification-devices`；服务端仅保存 provider-scoped hash 与 AES-256-GCM 密文，列表接口不会返回原 token。退出账号或关闭通知时调用 `DELETE /v1/notification-devices/{installationId}`。

外部通知网关接收 `targets` 后直接调用 APNs/FCM，不得持久化或记录 token，并用 `invalidDeviceIds` 回传已经失效的 installationId。没有 Apple/Firebase 正式凭据时，验收范围必须标记为“站内消息通过、系统推送未验收”。

`backend/scripts/remote-workflow-smoke.js` 不读取 Mock，也不会输出账号、密码或 Token。

首次为试点环境建立隔离验收学校、家长/教师账号、专用学生、任务、报告、课程、活动、专家和两个时段时，使用显式保护的幂等命令。该命令不会写入真实学校；密码不会出现在输出中：

```bash
cd backend
DATABASE_URL=<由服务器密钥文件注入> \
REMOTE_FIXTURE_CONFIRM=1 \
REMOTE_FIXTURE_SCOPE=pilot \
REMOTE_FIXTURE_PARENT_ACCOUNT=<专用11位测试账号> \
REMOTE_FIXTURE_PARENT_PASSWORD=<至少12位强密码> \
REMOTE_FIXTURE_TEACHER_ACCOUNT=<另一个专用11位测试账号> \
REMOTE_FIXTURE_TEACHER_PASSWORD=<至少12位强密码> \
npm run provision:remote-acceptance
```

输出的稳定 ID 对应下方 `REMOTE_E2E_*` secrets。重复执行会轮换两个验收账号的密码并刷新活动/时段窗口，不会创建重复学校或学生。验收 fixture 必须保留在独立验收学校中，不能指向真实儿童、真实教学任务或真实专家服务。

默认只读验收覆盖：

- 服务就绪与数据库 migration；
- 家长登录、服务端会话、绑定孩子、报告、课程、活动、预约和消息；
- 教师登录、授权班级、capability、任务名单和通知草稿；
- 所有对象均使用后端稳定 ID，不使用姓名或标题定位。

运行：

```bash
cd backend
REMOTE_E2E_BASE_URL=https://api.risingteen.com \
REMOTE_E2E_SCHOOL_ID=<试点学校ID> \
REMOTE_E2E_PARENT_ACCOUNT=<专用家长账号> \
REMOTE_E2E_PARENT_PASSWORD=<由密钥服务注入> \
REMOTE_E2E_TEACHER_ACCOUNT=<专用教师账号> \
REMOTE_E2E_TEACHER_PASSWORD=<由密钥服务注入> \
npm run smoke:remote-workflows
```

教师状态写入验收只能使用专用测试任务和测试学生，并显式打开：

```bash
REMOTE_E2E_ALLOW_WRITES=1 \
REMOTE_E2E_TASK_ID=<验收任务ID> \
REMOTE_E2E_STUDENT_ID=<验收学生ID> \
npm run smoke:remote-workflows
```

写入模式先使用服务端当前版本执行幂等更新，再使用旧版本验证 HTTP 409；不允许指向真实教学任务。

活动和专家预约的创建、修改/改期、版本冲突与取消验收必须使用可清理的专用 fixture，并单独显式开启：

```bash
REMOTE_E2E_ALLOW_LIFECYCLE_WRITES=1 \
REMOTE_E2E_CHILD_ID=<该验收账号已绑定的专用孩子ID> \
REMOTE_E2E_ACTIVITY_ID=<可反复报名并取消的验收活动ID> \
REMOTE_E2E_EXPERT_ID=<验收专家ID> \
REMOTE_E2E_SLOT_ID=<验收时段ID> \
REMOTE_E2E_RESCHEDULE_SLOT_ID=<另一个验收时段ID> \
npm run smoke:remote-workflows
```

脚本会为专用孩子创建并取消报名、创建并取消预约，且用旧版本验证两条业务链路都返回 `VERSION_CONFLICT`。两个预约时段必须属于测试资源且保持可预约；不得使用真实家庭或真实服务时段。

验收输出应作为 CI artifact 保存。缺少专用账号或 fixture 时必须记录为阻塞，不能用 Mock 结果替代。

## 2026-08-28 广州试点实测

- 入口：`https://106.52.164.21`（备案完成前的临时 IP HTTPS）。
- 服务：`readyz` 外网访问成功，PostgreSQL 正常，migration 48/48，embedded worker 健康。
- fixture：`pilot` 隔离 school scope，专用家长和教师账号、孩子、任务、报告、课程、活动、专家和两个时段已幂等创建。
- 写入验收：活动报名→编辑→旧版本 409→取消，专家预约→改期→旧版本 409→取消，教师任务更新→服务端版本→旧版本 409，全部通过。
- 密钥：验收密码只保存在服务器 root-only 环境文件，不写入代码库、命令输出或验收 JSON。
