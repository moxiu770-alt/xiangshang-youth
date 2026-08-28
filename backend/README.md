# 向上少年后端

这是与 iOS/Android `v1` API 对齐的第一版后端和数据库实现，包含 PostgreSQL schema、登录会话、学校/学生、测评任务、状态流转、报告、消息、审计日志和一个无构建依赖的管理后台。

学校管理（校长/平台管理员）统一使用管理后台数据看板，移动端只承载家长端和教师端工作台。学校总览、年级/班级对比、风险学生、任务与报告运营入口位于 `/admin`，移动端收到旧校长路由时仅展示迁移提示，不复制后台权限和统计页面。

## 本地启动

Docker Desktop 是可选项；本机开发也可以直接使用 PostgreSQL 或 Postgres.app：

```bash
cd backend
docker compose up --build
```

服务地址：

- API 健康检查：`http://localhost:8080/health`
- 存活检查：`http://localhost:8080/livez`
- 就绪检查：`http://localhost:8080/readyz`
- Prometheus 指标：`http://localhost:8080/metrics`（生产环境设置 `METRICS_TOKEN` 后使用 Bearer Token）
- 管理后台：`http://localhost:8080/admin`
- OpenAPI 3.1 契约：[`openapi.yaml`](openapi.yaml)（`npm run lint:openapi` 校验）
- 数据库：`localhost:5432`

默认后台账号：`13800000000 / ChangeMe123!`。首次正式部署必须修改密码，并确认 `NODE_ENV=production`；生产环境默认关闭公开注册接口，如确需开放才设置 `ALLOW_PUBLIC_REGISTRATION=true`。

如果本机已有 PostgreSQL，也可以先设置 `DATABASE_URL`，然后运行：

```bash
npm install
npm run migrate
npm run seed
npm start
```

本项目在 macOS 上也支持 Postgres.app。将 PostgreSQL 16 初始化在用户目录后，使用下面的连接串即可：

```bash
export PATH="/Applications/Postgres.app/Contents/Versions/latest/bin:$PATH"
export DATABASE_URL="postgres://xiangshang:xiangshang_dev@127.0.0.1:5432/xiangshang_youth"
npm run migrate
npm run seed
npm start
```

Postgres.app 的数据目录不在仓库内，当前本机目录为：`/Users/luyanpeng/Library/Application Support/Postgres/var-16`。

## 主要接口

```text
POST  /v1/auth/login
POST  /v1/auth/oauth/wechat/start
GET   /v1/auth/oauth/wechat/callback
POST  /v1/auth/oauth/wechat/exchange
POST  /v1/auth/mfa/totp
POST  /v1/auth/refresh
POST  /v1/auth/password
GET   /v1/me
GET   /v1/me/mfa
POST  /v1/me/mfa/totp/setup
POST  /v1/me/mfa/totp/confirm
POST  /v1/me/mfa/totp/disable
GET   /v1/me/sessions
DELETE /v1/me/sessions/{sessionId}
GET   /v1/schools/{schoolId}/dashboard
GET   /v1/schools/{schoolId}/students
POST  /v1/students/{studentId}/bind?code=...（生产环境只接受后台生成的一次性绑定码）
GET   /v1/schools/{schoolId}/tasks
PATCH /v1/tasks/{taskId}/students/{studentId}/status
GET   /v1/tasks/{taskId}/students
POST  /v1/admin/tasks/batch-status
GET   /v1/students/{studentId}/report
POST  /v1/students/{studentId}/report/refresh
GET   /v1/users/{userId}/messages
POST  /v1/messages/{messageId}/read
POST  /v1/admin/students
POST  /v1/admin/students/{studentId}/binding-code
POST  /v1/admin/tasks
GET   /v1/admin/schools
POST  /v1/admin/schools
PATCH /v1/admin/schools/{schoolId}/status
GET   /v1/admin/grades
POST  /v1/admin/grades
PATCH /v1/admin/grades/{gradeId}
GET   /v1/admin/classes
POST  /v1/admin/classes
PATCH /v1/admin/classes/{classId}
GET   /v1/admin/school-periods
POST  /v1/admin/school-periods
PATCH /v1/admin/school-periods/{periodId}/status
GET   /v1/admin/students/import/template
POST  /v1/admin/students/import/preview
POST  /v1/admin/students/import
GET   /v1/admin/students/imports
PATCH /v1/admin/students/{studentId}
PATCH /v1/admin/students/{studentId}/status
GET   /v1/admin/students/{studentId}/history
POST  /v1/admin/students/batch-promote
PATCH /v1/admin/tasks/{taskId}
PATCH /v1/admin/tasks/{taskId}/status
POST  /v1/admin/tasks/{taskId}/sync-students
POST  /v1/admin/tasks/{taskId}/clone
GET   /v1/admin/operations/items
PATCH /v1/admin/operations/{type}/{itemId}/status
GET   /v1/admin/notifications/campaigns
POST  /v1/admin/notifications/campaigns
GET   /v1/admin/audit-logs
GET   /v1/admin/audit-integrity?schoolId=...
GET   /v1/admin/jobs?status=failed
POST  /v1/admin/jobs/{jobId}/retry
PATCH /v1/admin/accounts/{accountId}
POST  /v1/admin/accounts/{accountId}/reset-password
POST  /v1/admin/accounts/{accountId}/reset-mfa
POST  /v1/auth/reset-password
GET   /v1/schools/{schoolId}/grade-stats
GET   /v1/schools/{schoolId}/class-stats
POST  /v1/tasks/{taskId}/students/{studentId}/scores
POST  /v1/scores/{scoreId}/review
GET   /v1/reports?schoolId=...
POST  /v1/reports/{reportId}/publish
POST  /v1/reports/{reportId}/withdraw
POST  /v1/students/{studentId}/body-assessments
GET   /v1/students/{studentId}/consent
POST  /v1/students/{studentId}/consent
DELETE /v1/students/{studentId}/consent
POST  /v1/files/presign
PUT   /v1/files/{fileId}/content
GET   /v1/files/{fileId}/content
GET   /v1/admin/data-retention
POST  /v1/admin/students/{studentId}/export（异步）
GET   /v1/admin/privacy-requests/{requestId}
POST  /v1/admin/students/{studentId}/anonymize
GET   /v1/admin/test-stations?schoolId=...
POST  /v1/admin/test-stations
PATCH /v1/admin/test-stations/{stationId}
GET   /v1/admin/test-devices?schoolId=...
POST  /v1/admin/test-devices（仅响应一次 deviceKey）
POST  /v1/admin/test-devices/{deviceId}/rotate-key
POST  /v1/admin/test-stations/{stationId}/calibrations
GET   /v1/admin/test-sessions?schoolId=...
GET   /v1/admin/test-sessions/{sessionId}
GET   /v1/admin/test-queues?taskId=...
POST  /v1/admin/test-queues/rebalance
POST  /v1/admin/test-queues/{queueEntryId}/transition
GET   /v1/admin/field/stream?schoolId=...（SSE 实时状态流）
POST  /v1/admin/device-commands
POST  /v1/field/heartbeat
GET   /v1/field/bootstrap?taskId=...
GET   /v1/field/commands
POST  /v1/field/commands/{commandId}/ack
POST  /v1/field/files/presign
PUT   /v1/field/files/{fileId}/content
POST  /v1/field/queue/transition
POST  /v1/field/sessions
POST  /v1/field/sessions/{sessionId}/events
POST  /v1/field/sessions/{sessionId}/complete
POST  /v1/field/sync/batches
```

场地端同步批次与每条边缘事实均以客户端 UUID 去重。客户端会在本地 SQLite 持久化批次 ID，网络在中央端完成提交后中断时，重试会直接取回同一批次的缓存回执；中央端同时校验事件类型和内容摘要，拒绝“同一事件 ID、不同内容”的覆盖尝试。处理中批次的租约为五分钟，超时后仅允许同一设备用原批次接管重放。

### 高权限账户双重验证

管理后台右上角“账户安全”可为当前账户启用标准 TOTP（Microsoft/Google Authenticator、1Password 等）。设置必须重新输入当前密码，密钥以 AES-256-GCM 加密后保存；确认时生成十个只显示一次、单次使用的恢复码。密码登录成功后不会立刻签发会话，而是返回五分钟有效的 MFA 挑战；验证码按账户与来源 IP 双限速，且同一 TOTP 时间窗不能重放。生产环境默认 `REQUIRE_MFA_FOR_PRIVILEGED=true`：管理员和校长首次登录会被引导完成身份验证器注册后才获得会话，教师和家长仍可自愿启用。生产环境必须在密钥管理服务中提供至少 32 位的 `MFA_ENCRYPTION_KEY`。

身份验证器遗失时，只有平台管理员能在“账户分桶”中执行“恢复双重验证”。该操作必须填写不少于 8 个字符的原因、立即撤销目标账户全部会话并写入审计链；管理员/校长恢复后会在下次登录重新注册 TOTP。常规密码重置不会绕过 MFA。

生产环境的新审计事件会按学校（以及平台级范围）串成 HMAC-SHA-256 哈希链，签名密钥为独立管理的 `AUDIT_LOG_SIGNING_KEY`。API 与独立 worker 使用同一实现：隐私导出完成/失败等异步后台动作也会进入同一链条。平台管理员可调用 `/v1/admin/audit-integrity` 校验链条；部署前已有的审计记录作为不可改写的历史基线，不会被补写或删除。

### 场地正式开测门禁

`/v1/field/heartbeat` 的 `health` 采用 `field-health/v1`。中央服务不会因为“设备在线”就放行正式会话；边缘主机必须同时上报并通过：双深度摄像头、至少一台高速 RGB 摄像头、GPU 推理环境、多机帧同步不超过 33.4ms、至少 5GB 本地证据空间，以及与中央有效标定相同的版本、SHA-256 和不超过 5cm 的标定误差。紧急停止或任一自检失败会在 bootstrap 的 `readiness.blockers` 中返回原因，并使 `POST /v1/field/sessions` 返回 `409 FIELD_STATION_NOT_READY`。

只有 `edge_host` 的心跳可以把测试点置为在线；显示屏、喇叭、读卡器等外围设备在线不能绕过该门禁。后台“场地中控”会分别显示设备在线状态和“可正式开测”状态。

同一已发布任务可由多个通过正式自检的测试点共同承接。中央服务按测试点队列容量和已占用比例分配候测学生；测试点离线或不再满足开测门禁时，仅释放其仍为 `waiting` 的学生回公共队列。`called`、`checked_in`、`testing` 状态不会跨测试点迁移，避免身份、采集证据和现场操作上下文断裂。管理员或校长可在“场地中控”选择任务执行重新分流；管理员、校长或负责班级的教师也可将单个 `waiting` / `retest` 学生调整到另一个已通过开测检查且有剩余容量的测试点。单人换点要求提交原因和最新队列版本，并写入队列事件、审计日志和场地实时推送；并发旧版本、未就绪、满容量或已进入叫号流程的调整都会被拒绝。

候测队列接口会为正在采集的学生附带活动会话、开始时间、已接收事件数、最后反馈时间、最新事件类型及其结构化进度载荷。后台现场运行页据此显示当前项目与设备反馈；会话关闭后这些活动字段自动消失，完整原始时间线仍只在学生现场记录和会话详情中查看。

后台顶部的现场运行看板按测试点逐行展开，不再把全校并行流程压缩成每个阶段一名学生。每个测试点分别显示所有正在采集、已签到和已叫号学生，以及本站下一位、剩余候测人数、设备在线/就绪状态和容量；点击学生可定位到队列记录，点击“查看本站队列”可直接筛选该测试点。

当前场地流程采用“一名学生、一个任务、一次完整采集会话”的模型。测试点能力为空时表示“整套任务通道”，可完成任务中配置的全部项目；测试点选择某一标准项目时表示“单项通道”，只承接项目完全相同的单项任务。自动分流、人工换点和正式开测都会重复校验任务—测试点匹配，设备提交的成绩项目也必须与任务项目完全一致，缺项、重复项或任务外项目都会被拒绝。后台测试点卡片可直接调整测试能力；多项目任务应使用整套任务通道。

家庭测评提交后由服务端 `bodyScoring.js` 统一计算身高发育（WS/T 612）、BMI 年龄别筛查与 `postureScoring.js` 姿态观察，再按 `UY-IMCA-CV-1.3` 合并总体等级；BMI 使用 `UY-IMCA-BMI-1.2` 的 WS/T 586 半岁年龄档，不做逐月插值。姿态模型对厘米/角度输入执行物理范围校验，异常值进入待补采，不直接生成红色结论。客户端传入的 `overallLevel` 仅用于预览，不参与最终入库。读取最新测评时也会基于保存的四项证据重新评分，避免历史客户端结果漂移；原生端提交成功后会回写服务端的姿态等级、风险分和质量分。

七项动作成绩由 `scoring.js` 统一归一化、去重并按置信度选择证据；同一项目重复上报相差至少 1.5 分时标记 `conflictingItems` 并进入待复核，不自动覆盖已发布报告，阈值记录在 `modelCalibration.js` 以便审计。

列表接口默认返回数组；需要分页时追加 `paged=1&page=1&pageSize=20`。学生导入同时支持 CSV 和 `.xlsx`（JSON 请求中传 `csvText` 或 `fileBase64`），先调用 preview 再正式写入；导入记录、学生转班/停用/恢复历史都会保留。创建类写接口支持 `Idempotency-Key`，重复提交会复用第一次响应。数据库结构由 `db/schema.sql` 和 `db/migrations/` 管理，演示基础数据必须单独执行 `npm run seed`。

### 通知投递网关

站内通知和外部通知都先写入 `notification_deliveries` 与 `job_queue`，由 Worker 按 `deliveryId` 投递。定时通知在 `scheduled_at` 到达前不会出现在收件箱；Worker 重试不会生成重复站内消息。`in_app` 不依赖外部服务，`push`、`sms`、`wechat` 需要配置 `NOTIFICATION_WEBHOOK_URL`，并可通过 `NOTIFICATION_WEBHOOK_AUTHORIZATION` 注入网关凭证。生产地址必须为 HTTPS；网关会收到 `deliveryId` 作为 `Idempotency-Key`，必须按该键去重，并根据 `receiverUserId` 在受控服务内解析 APNs、FCM、短信或微信目标。App 健康数据和摄像头数据不得进入通知负载。

### 生产部署入口

#### 学校试点部署

在正式微信、对象存储和异地备份资源到位前，可以使用试点编排验证真实 HTTPS、登录、家庭绑定、教师任务和 App 联调。试点环境使用独立数据库卷与本机文件卷，不会通过生产预检，也不得作为正式生产环境或准确率、合规上线证明。

```bash
cp .env.pilot.example .env.pilot
# 替换三个随机密钥后执行：
docker compose --env-file .env.pilot -f docker-compose.pilot.yml config
docker compose --env-file .env.pilot -f docker-compose.pilot.yml up -d postgres
docker compose --env-file .env.pilot -f docker-compose.pilot.yml --profile migrate run --rm migrate
docker compose --env-file .env.pilot -f docker-compose.pilot.yml up -d
curl -fsS https://api.risingteen.com/readyz
```

试点环境允许公开创建家庭账号，但不允许自行注册或扩权为教师；学校教师账号仍由管理端或受控脚本发放。切换正式环境前必须停止试点编排，迁移或清除试点数据，再改用下述 `docker-compose.prod.yml`，不得直接把 `.env.pilot` 改名冒充生产配置。

#### 正式生产部署

生产环境使用 `docker-compose.prod.yml`：API 和 PostgreSQL 不对公网发布端口，Caddy 是唯一公网入口，负责自动 HTTPS、HTTP→HTTPS 跳转和 API 健康探测。`worker` 是独立后台执行器，处理隐私导出、通知投递、场地会话后的报告刷新、设备失联回收与重试任务；API 可以独立扩容，不能再把作业轮询嵌入每个 API 副本。每个 Worker 用 `FOR UPDATE SKIP LOCKED` 安全领取至多 `JOB_WORKER_CONCURRENCY`（默认 4）条任务并发执行，不同 Worker 不会重复处理同一记录；收到停止信号后先停止领取，再在 `JOB_WORKER_SHUTDOWN_TIMEOUT_MS`（默认 25 秒、小于容器 30 秒宽限期）内排空已领取任务。`backup` 是独立、只读文件系统的备份执行器：启动后立即执行并按 `BACKUP_INTERVAL_SECONDS`（默认每天）归档到独立 S3 bucket，健康心跳、最近成功时间和失败状态均暴露给监控。应根据数据库连接池、对象存储和学校峰值导出量调优。复制 `.env.production.example` 到受管密钥系统或不入库的 `.env.production`，填入真实域名、数据库、S3/KMS 访问凭据和随机指标令牌；DNS 必须先解析到部署主机，80/443 必须可从公网访问。

```bash
cd backend
docker compose --env-file .env.production -f docker-compose.prod.yml config
docker compose --env-file .env.production -f docker-compose.prod.yml run --rm api npm run preflight:production
docker compose --env-file .env.production -f docker-compose.prod.yml run --rm worker node scripts/worker-preflight.js
docker compose --env-file .env.production -f docker-compose.prod.yml run --rm backup node scripts/backup-preflight.js
docker compose --env-file .env.production -f docker-compose.prod.yml --profile migrate run --rm migrate
docker compose --env-file .env.production -f docker-compose.prod.yml up -d
```

预检会拒绝本地文件存储、HTTP S3、未受信任代理、公开注册、非 HTTPS 的 CORS 或缺失的域名/证书通知邮箱；正式环境不执行 `seed`。`/readyz` 还会核对数据库已应用当前 API 镜像随附的全部迁移及其 SHA-256 指纹；数据库可连接但迁移落后或已应用迁移被改写时返回 `503`，Caddy/Docker 不会把该副本加入服务。迁移器会为历史数据库首次补录当前指纹；之后任何已应用 SQL 的改写都会阻断部署，必须以新的迁移文件修正。

`/readyz` 的 `worker.mode` 在生产环境会显示 `external`，表示 API 本身不执行后台任务；必须同时监控 `worker` 容器的健康检查和结构化日志。

### 监控与告警

`monitoring/prometheus.yml` 使用 Docker secret 读取 `METRICS_TOKEN`，不会把指标令牌写进 Git。将同一令牌写入受限主机文件后，按监控 profile 启动：

```bash
set -a; . ./.env.production; set +a
install -d -m 700 /secure/xiangshang
printf %s "$METRICS_TOKEN" > /secure/xiangshang/metrics_token
chmod 600 /secure/xiangshang/metrics_token
docker compose --env-file .env.production -f docker-compose.prod.yml --profile monitoring up -d
```

Prometheus 仅绑定 `127.0.0.1:9090`，规则覆盖 API 不可用、独立 worker 心跳失联、备份执行器/备份时效异常、数据库迁移落后、5xx 比例、数据库连接池错误、失败任务和超过五分钟的队列积压。将 Prometheus 接入组织已有的 Alertmanager/PagerDuty/企业微信路由前，需由运维负责人配置接收方和静默策略；仓库不会默认对外发送告警。

## Windows 场地端与中央服务

电脑体测端与 App、管理后台共用中央业务数据，但不是网页登录后台：每台 Windows 边缘主机以 `X-Device-Id`、请求时间戳、单次随机数和 HMAC 签名调用 `/v1/field/*`，下载任务、花名册、规则/标定和待执行指令。设备密钥只在本机用于签名，服务端使用独立 `FIELD_DEVICE_SIGNING_ENCRYPTION_KEY` 加密保存对应签名材料，数据库泄露不能单独伪造设备请求。生产环境 `FIELD_DEVICE_SIGNED_REQUESTS_REQUIRED=true` 会拒绝旧式每请求传输密钥的方式；签名有效期默认五分钟且随机数只能使用一次。已有设备升级后需在后台轮换一次密钥，才会生成加密签名材料。场地端用本地 SQLite 保存 `clientEventId` 和 `clientBatchId`，断网期间继续采集、叫号、评分并保存证据，恢复联网后调用 `/v1/field/sync/batches` 幂等重放。中央端保存设备、测试点、标定、队列、会话、动作事件、证据关联和远程指令；低置信度成绩自动进入复核。

关闭现场任务必须填写原因并选择未完成学生去向。服务端会阻止仍有活动采集会话、待复核记录或完成异常的任务被关闭；通过检查后，未开始或未结束的队列统一取消，学生记录进入可追溯的“未完成”终态。管理员可同时创建只包含这些学生的后续补测草稿。关闭事件通过现场实时通道下发，Windows 客户端会停止叫号，或安全切换到下一项已发布任务。

Windows 基础工程位于 [`../field-client/README.md`](../field-client/README.md)。设备密钥只在后台注册或轮换时返回一次，生产环境必须放入 Windows Credential Manager/企业密钥服务，不能写入配置文件或日志。

场地设备密钥默认 90 天到期（`FIELD_DEVICE_KEY_TTL_DAYS`，上限 365 天）；后台可轮换，轮换后旧密钥立即失效。中央作业会在心跳超过 `FIELD_DEVICE_OFFLINE_AFTER_SECONDS`（默认 90 秒）后将设备和无在线设备的测试点标记为离线，并通过 SSE 发布 `device.offline`。维护/停用状态不会被自动覆盖。

定期维护：

```bash
npm run cleanup
```

该命令清理过期幂等键、失效会话、达到保留期限的健康测评和过期文件元数据；生产环境应通过定时任务执行，并配合数据库备份和恢复演练。健康数据默认保留 2555 天，可通过 `HEALTH_DATA_RETENTION_DAYS` 调整；生产环境默认要求先取得家长数据使用同意，可通过 `REQUIRE_HEALTH_CONSENT=true` 显式开启。

场地证据按最小必要原则单独治理：视频/图片默认 180 天（`FIELD_EVIDENCE_VIDEO_RETENTION_DAYS`），骨架、事件时间线、标定和日志默认 1095 天（`FIELD_EVIDENCE_DERIVED_RETENTION_DAYS`）；已上传但未关联会话的孤儿文件默认 24 小时清理（`FIELD_EVIDENCE_ORPHAN_RETENTION_HOURS`）。清理先删除对象存储内容，再解除文件引用；会话中的证据类型、校验和、保留截止时间、清理时间和原因会保留用于复核与审计。

数据库备份、异地归档与恢复：

```bash
BACKUP_DIR=./backups npm run backup
BACKUP_FILE=./backups/xiangshang-<timestamp>.dump npm run backup:verify
pg_restore --clean --if-exists --no-owner --dbname="$DATABASE_URL" ./backups/xiangshang-<timestamp>.dump
```

生产环境将 `BACKUP_ARCHIVE_ENABLED=true`，并为 `BACKUP_S3_*` 配置**独立于证据文件**的 HTTPS S3 兼容存储。每次备份会上传 `.dump` 与带 SHA-256、字节数、对象键和生成时间的 `.manifest.json`；归档前缀必须是受限路径（默认 `xiangshang/database`）。备份 bucket 应由运维设置服务端加密、版本控制、跨区域复制/不可变保留和生命周期策略，备份账号只授予该 bucket/prefix 的最小写入权限。

容器运行一次备份时，根文件系统为只读，因此使用 `/tmp` 作为暂存目录：

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml run --rm \
  -e BACKUP_DIR=/tmp/backup api npm run backup
```

标准 Compose 部署会运行独立 `backup` 服务，启动后立即备份并按 `BACKUP_INTERVAL_SECONDS` 自动执行；它不是 API 进程的一部分。Kubernetes/托管平台可用 CronJob 替代该服务，但必须保留同等的独立归档、心跳与告警能力。跨区域复制、不可变保留和密钥轮换仍属于存储与部署环境职责。

`npm run migrate` 使用 PostgreSQL advisory lock 串行执行迁移；备份文件和 `storage/` 文件对象应分别纳入加密备份。生产环境应使用云盘/数据库加密、密钥管理服务、对象存储病毒扫描和定期恢复演练，仓库不保存真实密钥。`FILE_STORAGE_DRIVER=local` 只适合单节点或验收环境；多实例部署可配置 `FILE_STORAGE_DRIVER=s3`、S3 兼容端点和密钥。数据导出和场地会话完成后的报告刷新均通过 `job_queue` 异步执行：场地会话、成绩写入与 `report.refresh` 任务在同一数据库事务中提交；API 即使在提交后停止，独立 Worker 也会领取、重试并审计报告生成，失败任务可在后台“任务队列”查看并进行受审计重试。

浏览器端登录使用 HttpOnly 刷新 Cookie，Access Token 只保留在当前页面内存中；移动端仍可使用响应体中的 Token。生产环境应设置 `MAX_SESSIONS_PER_USER`，并将审计日志接入集中日志系统。

权限遵循最小可见范围：平台管理员和校长可查看其授权学校；教师只能查看、管理和发布自己负责班级的学生、报告、体测队列与会话，且不能创建或操作全校任务；家长只能看到已绑定孩子及其已发布报告。设备级暂停、停止、配置刷新等远程指令仅限管理员或校长，教师应通过班级队列操作完成现场调度。拥有学校工作人员角色的混合账号按工作人员范围处理，不会因同时是家长角色而扩大或混合读取范围。

除接口层授权外，数据库还会拒绝跨学校关联：班级/学生/任务使用复合外键，场地设备、测试点、队列、会话和远程指令也必须属于同一学校；任务—学生、成绩、报告、队列事件和设备同步事件由触发器再次校验。这样批量导入、独立 worker 或后续新增接口即使遗漏应用层判断，也不能写入跨校业务关系。生产升级前须先在预发布库执行迁移并处理任何历史不一致记录，迁移不会自动修正或删除业务数据。

backup:verify 会用 pg_restore --list 验证归档可读取。恢复演练必须指向**独立且可丢弃**的数据库：

```bash
BACKUP_FILE=./backups/xiangshang-<timestamp>.dump \
RESTORE_DATABASE_URL='postgres://.../xiangshang_restore_verify' \
RESTORE_SCHEMA=public \
npm run backup:restore-verify
```

该命令拒绝把备份恢复到源数据库，并校验迁移记录和关键业务表；CI 同时执行这条完整恢复验证。异地归档至少每月应从对象存储下载一份备份，在隔离的恢复库执行此命令并记录恢复时长与校验结果。

本地并发冒烟：

SMOKE_CONCURRENCY=20 SMOKE_REQUESTS_PER_WORKER=10 npm run smoke:load

# 生产预发布环境：只读访问真实业务链路，不创建任何学生、任务或会话
SMOKE_BASE_URL=https://api-staging.example.edu.cn \
SMOKE_ADMIN_ACCOUNT=专用只读压测账号 \
SMOKE_ADMIN_PASSWORD=由密钥服务注入 \
SMOKE_SCHOOL_ID=staging-school-id \
SMOKE_CONCURRENCY=40 SMOKE_REQUESTS_PER_WORKER=25 SMOKE_P95_LIMIT_MS=800 \
npm run smoke:load

未配置账号时，该检查并发访问 `/readyz`；配置专用账号与学校范围后，会并发验证登录后的 `/v1/me`、学校总览、任务列表和场地测试点等只读核心链路，默认要求每个场景 p95 小于 1000ms 且不允许错误。它不写入数据，也不会绕过 MFA；建议在预发布环境使用受管密钥注入的专用只读压测账户。正式上线前仍需依据学校峰值人数、场地设备数量和对象存储吞吐执行更长时间的容量/故障压测。

集成测试必须使用独立数据库：

```bash
# 使用独立数据库和非 public schema。不要复用开发库：PostgreSQL 对同名
# `CREATE TABLE IF NOT EXISTS` 的解析会让测试表与开发库表结构串用。
# 若本机 5432 已被 Postgres.app 占用，以下 Docker 容器使用 15432。
docker run -d --name xiangshang-youth-integration-postgres \
  -e POSTGRES_DB=xiangshang_integration_test \
  -e POSTGRES_USER=xiangshang -e POSTGRES_PASSWORD=xiangshang_dev \
  -p 127.0.0.1:15432:5432 postgres:16-alpine
docker exec xiangshang-youth-integration-postgres \
  psql -U xiangshang -d xiangshang_integration_test \
  -c 'CREATE SCHEMA IF NOT EXISTS xiangshang_integration'
export TEST_DATABASE_URL="postgres://xiangshang:xiangshang_dev@127.0.0.1:15432/xiangshang_integration_test?options=-csearch_path%3Dxiangshang_integration"
DATABASE_URL="$TEST_DATABASE_URL" npm run migrate
DATABASE_URL="$TEST_DATABASE_URL" npm run seed
TEST_DATABASE_URL="$TEST_DATABASE_URL" SEED_PASSWORD=ChangeMe123! npm run test:integration
```

测试会校验当前 schema 必须为非 `public`，并在结束时清理它为幂等性验证创建的任务，避免把测试任务、会话和审计记录写入业务数据库。
