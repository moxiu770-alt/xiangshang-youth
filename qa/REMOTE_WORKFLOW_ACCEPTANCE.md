# 真实远程业务验收

`backend/scripts/remote-workflow-smoke.js` 不读取 Mock，也不会输出账号、密码或 Token。

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
