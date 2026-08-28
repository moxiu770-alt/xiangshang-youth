import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

const openapi = await fs.readFile(new URL('../openapi.yaml', import.meta.url), 'utf8');
const serverEntrypoint = await fs.readFile(new URL('../src/server.js', import.meta.url), 'utf8');
const fieldSessionService = await fs.readFile(new URL('../src/fieldSessionService.js', import.meta.url), 'utf8');
const server = `${serverEntrypoint}\n${fieldSessionService}`;
const authClaims = await fs.readFile(new URL('../src/authClaims.js', import.meta.url), 'utf8');
const activityRoutes = await fs.readFile(new URL('../src/routes/activities.js', import.meta.url), 'utf8');
const expertAppointmentRoutes = await fs.readFile(new URL('../src/routes/expertAppointments.js', import.meta.url), 'utf8');
const classPostRoutes = await fs.readFile(new URL('../src/routes/classPosts.js', import.meta.url), 'utf8');
const familyHealthRoutes = await fs.readFile(new URL('../src/routes/familyHealth.js', import.meta.url), 'utf8');
const courseRoutes = await fs.readFile(new URL('../src/routes/courses.js', import.meta.url), 'utf8');
const notificationRoutes = await fs.readFile(new URL('../src/routes/notifications.js', import.meta.url), 'utf8');
const notificationDelivery = await fs.readFile(new URL('../src/notificationDelivery.js', import.meta.url), 'utf8');
const privacyRoutes = await fs.readFile(new URL('../src/routes/privacy.js', import.meta.url), 'utf8');
const messageRoutes = await fs.readFile(new URL('../src/routes/messages.js', import.meta.url), 'utf8');
const supportRoutes = await fs.readFile(new URL('../src/routes/support.js', import.meta.url), 'utf8');
const productEventRoutes = await fs.readFile(new URL('../src/routes/productEvents.js', import.meta.url), 'utf8');
const contentOperationRoutes = await fs.readFile(new URL('../src/routes/contentOperations.js', import.meta.url), 'utf8');
const teacherTaskRoutes = await fs.readFile(new URL('../src/routes/teacherTasks.js', import.meta.url), 'utf8');
const fieldAdminRoutes = await fs.readFile(new URL('../src/routes/fieldAdmin.js', import.meta.url), 'utf8');
const fieldDeviceRoutes = await fs.readFile(new URL('../src/routes/fieldDevice.js', import.meta.url), 'utf8');
const fileRoutes = await fs.readFile(new URL('../src/routes/files.js', import.meta.url), 'utf8');
const remoteWorkflowSmoke = await fs.readFile(new URL('../scripts/remote-workflow-smoke.js', import.meta.url), 'utf8');
const fieldClientPackageScript = await fs.readFile(new URL('../../field-client/package-windows.sh', import.meta.url), 'utf8');
const fieldClientReadme = await fs.readFile(new URL('../../field-client/README-WINDOWS.txt', import.meta.url), 'utf8');
const fieldClientContracts = await fs.readFile(new URL('../../field-client/FieldClient.Core/Contracts.cs', import.meta.url), 'utf8');
const adminHtml = await fs.readFile(new URL('../public/index.html', import.meta.url), 'utf8');
const adminEnhancements = await fs.readFile(new URL('../public/admin-enhancements.js', import.meta.url), 'utf8');
const fieldOperationsPolicySource = await fs.readFile(new URL('../public/field-operations-policy.js', import.meta.url), 'utf8');
const adminCss = await fs.readFile(new URL('../public/admin.css', import.meta.url), 'utf8');
const adminWorkspaces = await fs.readFile(new URL('../public/admin-workspaces.js', import.meta.url), 'utf8');
const fieldClientMainWindow = await fs.readFile(new URL('../../field-client/FieldClient.Windows/MainWindow.xaml.cs', import.meta.url), 'utf8');
const fieldClientMainWindowXaml = await fs.readFile(new URL('../../field-client/FieldClient.Windows/MainWindow.xaml', import.meta.url), 'utf8');
const fieldClientConnectionSetup = await fs.readFile(new URL('../../field-client/FieldClient.Windows/ConnectionSetupWindow.xaml.cs', import.meta.url), 'utf8');
const fieldClientConnectionSetupXaml = await fs.readFile(new URL('../../field-client/FieldClient.Windows/ConnectionSetupWindow.xaml', import.meta.url), 'utf8');
const fieldConnectionImportPolicy = await fs.readFile(new URL('../../field-client/FieldClient.Core/FieldConnectionImportPolicy.cs', import.meta.url), 'utf8');
const captureAdapterSetupWindow = await fs.readFile(new URL('../../field-client/FieldClient.Windows/CaptureAdapterSetupWindow.xaml.cs', import.meta.url), 'utf8');
const fieldClientConfiguration = await fs.readFile(new URL('../../field-client/FieldClient.Core/FieldClientConfiguration.cs', import.meta.url), 'utf8');
const captureAdapterHost = await fs.readFile(new URL('../../field-client/FieldClient.Core/CaptureAdapterHost.cs', import.meta.url), 'utf8');
const captureEventPresentation = await fs.readFile(new URL('../../field-client/FieldClient.Core/CaptureEventPresentation.cs', import.meta.url), 'utf8');
const { validateProductEventBatch } = await import('../src/routes/productEvents.js');
await import('../public/field-operations-policy.js');
const { selectPrimaryAction } = globalThis.XiangshangFieldOperationsPolicy;
// Workflow assertions intentionally inspect the composed HTTP surface. Route
// modules may move independently of the entrypoint, but their validation and
// authorization rules must remain part of the same shipped service.
const routeHandlers = `${server}\n${activityRoutes}\n${expertAppointmentRoutes}\n${classPostRoutes}\n${familyHealthRoutes}\n${courseRoutes}\n${notificationRoutes}\n${privacyRoutes}\n${messageRoutes}\n${supportRoutes}\n${productEventRoutes}\n${contentOperationRoutes}\n${teacherTaskRoutes}\n${fileRoutes}`;
const jobs = await fs.readFile(new URL('../src/jobs.js', import.meta.url), 'utf8');
const schema = await fs.readFile(new URL('../db/schema.sql', import.meta.url), 'utf8');

function section(route) {
  return openapi.split(`  ${route}:\n`)[1]?.split('\n  /')[0] || '';
}

test('Windows field client is delivered as a self-contained verified download', () => {
  const metadata = section('/v1/public/field-client-release');
  const download = section('/downloads/xiangshang-field-client-windows-x64.zip');
  assert.notEqual(metadata, '', 'field client release metadata must be documented');
  assert.notEqual(download, '', 'field client download must be documented');
  assert.match(server, /fieldClientArchiveName = 'xiangshang-field-client-windows-x64\.zip'/);
  assert.match(server, /X-Checksum-Sha256/);
  assert.match(fieldClientPackageScript, /--self-contained true/);
  assert.match(fieldClientPackageScript, /PublishSingleFile=true/);
  assert.match(fieldClientPackageScript, /README-WINDOWS\.txt/);
  assert.match(fieldClientPackageScript, /ADAPTER-README\.txt/);
  assert.doesNotMatch(fieldClientPackageScript, /FIELD_DEVICE_KEY|FIELD_DEVICE_ID/);
  assert.match(fieldClientReadme, /无需安装 \.NET SDK/);
  assert.match(fieldClientReadme, /FieldClient\.Windows\.exe/);
  assert.match(adminEnhancements, /下载 Windows 客户端/);
  assert.match(adminEnhancements, /不要运行 \.ps1/);
  assert.match(adminEnhancements, /xiangshang-field-connection\/v1/);
  assert.match(adminEnhancements, /一次复制三项接入信息/);
  assert.match(adminEnhancements, /document\.execCommand\('copy'\)/);
  assert.match(fieldClientConnectionSetupXaml, /从剪贴板粘贴/);
  assert.match(fieldClientConnectionSetup, /ClearMatchingImportedClipboard/);
  assert.match(fieldClientConnectionSetupXaml, /ConnectionTestStatus/);
  assert.match(fieldClientConnectionSetup, /连接测试超时/);
  assert.match(fieldClientConnectionSetup, /设备身份验证失败/);
  assert.match(fieldClientMainWindowXaml, /HeaderConnectionButton/);
  assert.match(fieldClientMainWindow, /HeaderConnectionButton\.Content = "恢复连接"/);
  assert.match(fieldConnectionImportPolicy, /SchemaVersion = "xiangshang-field-connection\/v1"/);
  assert.match(fieldClientMainWindow, /HeartbeatAsync\(health, SoftwareVersion/);
  assert.doesNotMatch(fieldClientMainWindow, /HeartbeatAsync\(health, "field-client\//);
  assert.match(adminEnhancements, /待升级至 v/);
  assert.match(adminEnhancements, /无法识别为 Windows 场地端/);
  assert.match(adminEnhancements, /fieldMetricUpdates/);
  assert.match(adminEnhancements, /下载新版/);
  assert.match(fieldClientMainWindowXaml, /Content="采集设备与厂商 DLL"/);
  assert.match(fieldClientMainWindowXaml, /设备、连接与同步/);
  assert.match(fieldClientMainWindowXaml, /仅首次接入、设备更换或故障排查时使用/);
  assert.match(fieldClientMainWindowXaml, /CurrentTaskScopeText/);
  assert.match(fieldClientMainWindowXaml, /核验身份并签到  F3/);
  assert.match(captureAdapterSetupWindow, /DiscoverAdapterTypes/);
  assert.match(fieldClientConfiguration, /SaveCaptureAdapter/);
  assert.match(captureAdapterHost, /LoadFromConfiguration/);
  assert.match(adminEnhancements, /安装包默认不包含硬件 DLL/);
  assert.match(server, /const mode = readyStations\.length \? 'formal_ready' : 'pre_dispatch'/);
  assert.match(server, /s\.status NOT IN \('maintenance','paused','disabled'\).*d\.status<>'disabled'/s);
  assert.match(adminEnhancements, /预生成候测名单/);
  assert.match(adminEnhancements, /设备通过心跳、自检和标定前仍不能正式采集/);
  assert.match(adminEnhancements, /rebalanceButton\.disabled = !dispatchableTasks\.length \|\| !planningStations\.length/);
  assert.match(adminEnhancements, /正式采集仍须通过设备、项目与签到门禁/);
  assert.match(fieldAdminRoutes, /latestCaptureEventType/);
  assert.match(server, /captureEventCount/);
  assert.match(adminEnhancements, /fieldCaptureProgress/);
  assert.match(adminEnhancements, /等待设备首条反馈/);
  assert.match(fieldClientContracts, /LatestCapturePayload/);
  assert.match(fieldClientMainWindowXaml, /CaptureLiveEventPanel/);
  assert.match(fieldClientMainWindow, /CaptureEventPresentationPolicy\.Describe/);
  assert.match(captureEventPresentation, /allow-list/);
  assert.match(captureEventPresentation, /ReadText/);
  assert.match(adminEnhancements, /fieldTaskReadyStationCount/);
  assert.match(adminEnhancements, /已分配测试点尚未通过开测检查/);
  assert.match(server, /FIELD_QUEUE_UNASSIGNED/);
  assert.match(server, /不能叫号；请先处理设备、自检和标定/);
  assert.match(section('/v1/admin/test-queues/rebalance'), /允许预分流/);
});

test('task completion is evidence-backed across field, teacher, and admin workflows', () => {
  const queueTransition = section('/v1/field/queue/transition');
  const taskStatus = section('/v1/tasks/{taskId}/students/{studentId}/status');
  const scoreWrite = section('/v1/tasks/{taskId}/students/{studentId}/scores');
  assert.doesNotMatch(queueTransition, /enum: \[[^\]]*completed/);
  assert.doesNotMatch(queueTransition, /enum: \[[^\]]*testing/);
  assert.match(server, /FIELD_SESSION_COMPLETION_REQUIRED/);
  assert.match(server, /FIELD_SESSION_OPEN_REQUIRED/);
  assert.match(teacherTaskRoutes, /TASK_COMPLETION_SCORES_INCOMPLETE/);
  assert.match(teacherTaskRoutes, /TASK_COMPLETION_REVIEW_PENDING/);
  assert.match(teacherTaskRoutes, /SCORE_ITEM_OUTSIDE_TASK/);
  assert.match(server, /validTaskCompletionPredicate/);
  assert.match(teacherTaskRoutes, /validTaskCompletionPredicate/);
  assert.match(taskStatus, /全部成绩且无待复核项目/);
  assert.match(scoreWrite, /markCompleted 仍受完整成绩与复核门禁约束/);
  assert.match(adminEnhancements, /成绩齐全且无待复核项后，才可人工确认完成/);
  assert.match(adminEnhancements, /历史异常/);
  assert.doesNotMatch(adminEnhancements, /批量标记已完成/);
});

test('field operations primary action follows the task, queue, device, then exception runway', () => {
  const deviceAndTimingIssues = [
    { target: 'devices', label: '3 台设备离线' },
    { target: 'timing', label: '2 人候测超过 30 分钟' }
  ];
  assert.deepEqual(selectPrimaryAction({ taskChosen: false, queueReady: false, deviceReady: false }), { target: 'task', label: '选择测评任务' });
  assert.deepEqual(selectPrimaryAction({ taskChosen: true, queueReady: false, deviceReady: false, canGenerateQueue: true }), { target: 'generate', label: '生成候测名单' });
  assert.deepEqual(selectPrimaryAction({ taskChosen: true, queueReady: true, deviceReady: false, issues: deviceAndTimingIssues, onlineDevices: 0, activeDeviceCount: 3 }), { target: 'devices', label: '恢复场地设备（0/3 在线）' });
  assert.deepEqual(selectPrimaryAction({ taskChosen: true, queueReady: true, deviceReady: true, issues: [{ target: 'timing' }, { target: 'conflicts' }] }), { target: 'conflicts', label: '处理同步冲突' });
  assert.deepEqual(selectPrimaryAction({ taskChosen: true, queueReady: true, deviceReady: true, issues: [{ target: 'timing' }] }), { target: 'timing', label: '处理超时学生' });
  assert.match(fieldOperationsPolicySource, /policyHost\.XiangshangFieldOperationsPolicy/);
  assert.match(adminHtml, /field-operations-policy\.js[\s\S]*admin-enhancements\.js/);
  assert.match(server, /field-operations-policy\.js/);
  assert.match(adminEnhancements, /当前阻塞：没有可开测设备/);
  assert.match(adminEnhancements, /targetName === 'task'/);
});

test('unified operations center routes field exceptions and retests to actionable workbenches', () => {
  const summary = section('/v1/admin/operations/summary');
  const items = section('/v1/admin/operations/items');
  assert.match(summary, /完成异常、场地会话、补测、同步冲突/);
  assert.match(summary, /待发布报告/);
  assert.match(summary, /现场任务、候测学生、设备在线与开测门禁/);
  assert.match(server, /fieldRuntime/);
  assert.match(server, /summarizeFieldOperations/);
  assert.match(server, /selectedTaskTitle/);
  assert.match(adminEnhancements, /当前现场任务/);
  assert.match(server, /queueSummary/);
  assert.match(server, /WHERE q\.task_id=\$1 AND q\.station_id=\$2/);
  assert.match(items, /completionAnomalies/);
  assert.match(items, /fieldSessions/);
  assert.match(items, /retests/);
  assert.match(items, /syncConflicts/);
  assert.match(items, /reports/);
  for (const key of ['completionAnomalies', 'attentionFieldSessions', 'pendingRetests', 'openFieldSyncConflicts']) assert.match(server, new RegExp(key));
  assert.match(adminEnhancements, /统一待办中心/);
  assert.match(adminEnhancements, /data-operation-anomaly-task/);
  assert.match(adminEnhancements, /data-operation-retest-task/);
  assert.match(adminEnhancements, /data-operation-field-session/);
  assert.match(adminEnhancements, /data-operation-sync-conflict/);
  assert.match(adminEnhancements, /actionableTotal/);
  assert.match(adminEnhancements, /fieldRuntimeSummary/);
  assert.match(adminEnhancements, /data-open-field-runtime/);
  assert.match(adminEnhancements, /data-field-runtime-target/);
  assert.match(adminEnhancements, /pendingFieldRuntimeTarget/);
  assert.match(adminEnhancements, /data-field-device-card/);
  assert.match(adminEnhancements, /设备全部离线/);
  assert.match(adminEnhancements, /等待首次连接/);
  assert.match(adminEnhancements, /台设备连接中断/);
  assert.match(adminEnhancements, />开始连接</);
  assert.match(adminEnhancements, /fieldOpsPrimaryAction/);
  assert.match(adminEnhancements, /data-operation-report/);
  assert.match(fieldAdminRoutes, /s\.id,s\.client_session_id,st\.name/);
  assert.match(fieldClientMainWindowXaml, /异常 \/ 补测/);
  assert.match(fieldClientMainWindow, /"retest", "absent", "skipped", "paused", "cancelled"/);
  assert.match(fieldClientMainWindow, /next\.Status == "retest"/);
  assert.match(fieldClientMainWindow, /StatusBackground/);
  assert.match(fieldClientMainWindow, /visible\.FindIndex\(item => item\.Status is "testing" or "checked_in" or "called"\)/);
  assert.match(fieldClientPackageScript, /FIELD_CLIENT_VERSION:-0\.4\.27/);
  assert.match(fieldClientReadme, /场地端 0\.4\.27/);
  assert.match(fieldClientMainWindow, /callReady/);
  assert.match(fieldClientMainWindow, /测试点尚未具备叫号条件/);
  assert.doesNotMatch(fieldClientMainWindow, /离线时可叫号/);
  assert.match(fieldClientMainWindow, /离线时仅可查看名单和本地记录/);
  assert.match(fieldClientMainWindowXaml, /QueueEmptyActionButton/);
  assert.match(fieldClientMainWindowXaml, /ReadinessActionButton/);
  assert.match(fieldClientMainWindow, /FieldReadinessRecoveryPolicy\.Describe/);
  assert.match(fieldClientMainWindow, /QueueEmptyActionButton\.Tag/);
  assert.match(fieldClientMainWindow, /case "adapter"/);
  assert.doesNotMatch(fieldClientMainWindow, /右上角“采集设备”/);
  assert.match(fieldClientMainWindow, /identityVerified: true/);
  assert.match(fieldClientMainWindow, /采集中 · 配置已锁定/);
  assert.match(fieldClientMainWindow, /runtimeConfigurationLocked/);
  assert.match(fieldClientMainWindow, /后台已将 .* 的异常会话安全收口并转入补测/);
  assert.match(fieldClientMainWindow, /现场运行 → 同步冲突工作台/);
  assert.match(server, /FIELD_IDENTITY_CONFIRMATION_REQUIRED/);
  assert.match(adminEnhancements, /身份一致，确认签到/);
  assert.match(adminEnhancements, /fieldIdentityStudentNo/);
  assert.match(fieldClientContracts, /\[\{TimingLabel\}\]/);
  assert.match(fieldAdminRoutes, /stateAgeSeconds/);
  assert.match(fieldAdminRoutes, /calledOverdue/);
  assert.match(adminEnhancements, /时间超时/);
  assert.match(adminEnhancements, /叫号超过 2 分钟/);
  assert.match(adminEnhancements, /候测超过 15 分钟/);
  assert.match(fieldClientMainWindow, /叫号后仍未签到/);
  assert.match(fieldClientMainWindow, /FieldQueueTimingPolicy\.Describe/);
  assert.match(server, /FIELD_QUEUE_REASON_REQUIRED/);
  assert.match(fieldAdminRoutes, /timingSeverity/);
  assert.match(adminEnhancements, /严重积压/);
  assert.match(adminEnhancements, /fieldQueueDecisionModal/);
  assert.match(adminEnhancements, /处理原因/);
  assert.match(fieldClientMainWindowXaml, /Content="时间超时" Tag="timing"/);
  assert.notEqual(section('/v1/admin/test-queues/{queueEntryId}/history'), '');
  assert.match(fieldAdminRoutes, /queue_events event/);
  assert.match(fieldAdminRoutes, /"actorName"/);
  assert.match(fieldAdminRoutes, /"evidenceCount"/);
  assert.match(adminEnhancements, /fieldQueueHistoryModal/);
  assert.match(adminEnhancements, /学生现场记录/);
  assert.match(fieldClientContracts, /string\? Note = null/);
  assert.match(fieldClientMainWindowXaml, /SelectedStudentNotePanel/);
});

test('admin navigation separates operational workspaces and exposes the field workflow', () => {
  assert.match(server, /admin-workspaces\.js/);
  assert.doesNotMatch(adminEnhancements, /createElement\(['"]style['"]\)/, 'strict CSP must not silently discard component styles');
  assert.match(adminWorkspaces, /workspace-surface-hidden/);
  assert.match(adminWorkspaces, /fieldOperationsBtn/);
  assert.match(adminEnhancements, /data-field-runway="task"/);
  assert.match(adminEnhancements, /条件完成，可以叫号/);
  assert.match(adminEnhancements, /data-task-open-field/);
  assert.match(adminEnhancements, /task-situation-grid/);
  assert.match(adminEnhancements, /处理待复核与完成异常/);
  assert.match(adminEnhancements, /fieldDeviceDetailModal/);
  assert.match(adminEnhancements, /data-field-device-detail/);
  assert.match(adminEnhancements, /完整开测检查/);
  assert.match(adminEnhancements, /data-field-save-device/);
  assert.match(adminEnhancements, /保存设备信息/);
  assert.match(adminEnhancements, /data-field-station-edit/);
  assert.match(adminEnhancements, /保存测试点/);
  assert.match(adminEnhancements, /状态变更原因/);
  assert.match(adminEnhancements, /恢复待连接/);
  assert.match(adminEnhancements, /statusReason/);
  assert.match(adminEnhancements, /statusChangedByName/);
  assert.match(fieldAdminRoutes, /status_actor\.name AS "statusChangedByName"/);
  assert.match(fieldClientContracts, /StatusReason/);
  assert.match(adminEnhancements, /fieldQueueStationFilter/);
  assert.match(adminEnhancements, /fieldQueueStationId/);
  assert.match(fieldClientMainWindowXaml, /SelectNextStudentButton/);
  assert.match(fieldClientMainWindowXaml, /定位下一位  F6/);
  assert.match(fieldClientMainWindow, /SelectNextWaiting/);
  assert.doesNotMatch(adminEnhancements, /data-field-station-profile=/, '测试能力只能通过明确的编辑表单修改，不能下拉即写入');
  assert.match(adminEnhancements, /测试点并行运行/);
  assert.match(adminEnhancements, /renderFieldParallelBoard/);
  assert.match(adminEnhancements, /fieldParallelLane/);
  assert.match(adminEnhancements, /data-field-parallel-station/);
  assert.match(adminEnhancements, /data-field-station-focus/);
  assert.doesNotMatch(adminEnhancements, /const handoffStages/);
  assert.match(adminEnhancements, /data-field-handoff-student/);
  assert.match(adminEnhancements, /data-field-recall-device/);
  assert.match(adminEnhancements, /再次提醒/);
  assert.match(fieldAdminRoutes, /FIELD_RECALL_STATION_MISMATCH/);
  assert.match(fieldAdminRoutes, /FIELD_RECALL_STATUS_INVALID/);
  assert.match(fieldAdminRoutes, /FIELD_STATION_CAPACITY_BELOW_LOAD/);
  assert.match(fieldAdminRoutes, /FIELD_STATION_BUSY/);
  assert.match(fieldAdminRoutes, /FIELD_STATION_QUEUE_INCOMPATIBLE/);
  assert.match(fieldAdminRoutes, /FIELD_STATION_CODE_CONFLICT/);
  assert.match(fieldAdminRoutes, /FIELD_STATION_HAS_ACTIVE_QUEUE/);
  assert.match(fieldAdminRoutes, /status_reason AS "statusReason"/);
  assert.match(fieldAdminRoutes, /FIELD_DEVICE_CODE_CONFLICT/);
  assert.match(fieldAdminRoutes, /FIELD_DEVICE_ONLINE/);
  assert.match(fieldAdminRoutes, /field\.device\.update/);
  assert.match(fieldAdminRoutes, /FIELD_CALIBRATION_STATION_BUSY/);
  assert.match(fieldAdminRoutes, /FIELD_SESSION_DEVICE_ACTIVE/);
  assert.match(fieldAdminRoutes, /FIELD_SESSION_RECOVERY_STATE_INVALID/);
  assert.match(fieldAdminRoutes, /field\.session\.recover/);
  assert.match(server, /FIELD_SESSION_ABORTED/);
  assert.match(server, /field_device\.last_heartbeat_at<now\(\)-interval '90 seconds'/);
  assert.match(adminEnhancements, /运行中已锁定/);
  assert.match(fieldDeviceRoutes, /status='offline' THEN 'online' ELSE status/);
  assert.match(adminEnhancements, /结束异常会话并安排补测/);
  assert.match(adminEnhancements, /设备中断待恢复/);
  assert.match(adminEnhancements, /data-field-session-recover/);
});

test('task closure safely retires field queues and preserves unfinished students', () => {
  const taskStatus = section('/v1/admin/tasks/{taskId}/status');
  const syncBatches = section('/v1/field/sync/batches');
  assert.match(taskStatus, /unfinishedAction/);
  assert.match(taskStatus, /close_incomplete/);
  assert.match(taskStatus, /create_followup/);
  assert.match(taskStatus, /maxLength: 500/);
  assert.match(server, /TASK_CLOSE_ACTIVE_SESSIONS/);
  assert.match(server, /TASK_CLOSE_PENDING_REVIEWS/);
  assert.match(server, /TASK_CLOSE_COMPLETION_ANOMALIES/);
  assert.match(server, /status='cancelled'.*state_version=q\.state_version\+1/s);
  assert.match(server, /'未完成'.*'task_closed'/s);
  assert.match(server, /task\.closed/);
  assert.match(adminEnhancements, /安全关闭现场任务/);
  assert.match(adminEnhancements, /未完成学生去向/);
  assert.match(adminEnhancements, /创建后续补测任务/);
  assert.match(adminEnhancements, /taskClosureReason/);
  assert.match(adminEnhancements, /本次任务已结束，保留未完成记录/);
  assert.match(fieldClientMainWindow, /后台已关闭原现场任务/);
  assert.match(fieldClientMainWindow, /本站已停止叫号/);
  assert.match(fieldClientMainWindow, /已安全切换到/);
  assert.match(fieldClientMainWindow, /InterruptedCapturePolicy\.Decide/);
  assert.match(fieldClientMainWindow, /封存旧任务采集记录/);
  assert.match(fieldClientMainWindow, /taskId = entry\.TaskId/);
  assert.match(fieldClientMainWindow, /taskRetiredRecovery = cause == "task_retired"/);
  assert.match(adminCss, /\.field-dispatch-bar>div\{[^}]*grid-template-columns:minmax\(0,1fr\)[^}]*flex:1/);
  assert.match(adminCss, /\.field-dispatch-bar span\{[^}]*-webkit-line-clamp:2/);
  assert.match(server, /t\.status AS task_status/);
  assert.match(server, /lateAfterTaskClosure: true/);
  assert.match(server, /session\.retired_after_task_close/);
  assert.match(fieldDeviceRoutes, /allowInactiveRecovery: true/);
  assert.match(syncBatches, /不得重新开启任务、队列或学生状态/);
});

test('workflow APIs document bounded request contracts', () => {
  const expectations = [
    ['/v1/activities/{activityId}/registrations', 'required: [contactName, phone]', 'pattern: \'^1\\\\d{10}$\''],
    ['/v1/expert-appointments', 'expertId', 'slotId', 'maxLength: 1000'],
    ['/v1/courses/uploads', 'required: [attachmentName, attendanceCount]', 'maximum: 10000'],
    ['/v1/class-posts', 'required: [content]', 'maxLength: 2000'],
    ['/v1/support/messages', 'required: [content]', 'maxLength: 2000']
  ];
  for (const [route, ...needles] of expectations) {
    const body = section(route);
    assert.notEqual(body, '', `${route} must be documented`);
    for (const needle of needles) assert.ok(body.includes(needle), `${route} is missing ${needle}`);
  }
});

test('workflow handlers enforce the same server-side validation as the API contract', () => {
  assert.match(routeHandlers, /SELECT id,school_id,status,capacity,registration_start_at,registration_end_at FROM activities WHERE id=\$1/);
  assert.match(routeHandlers, /只有家庭账号可以报名活动/);
  assert.match(routeHandlers, /ACTIVITY_NOT_AVAILABLE/);
  assert.match(routeHandlers, /只有家庭账号可以预约专家/);
  assert.match(routeHandlers, /const contactName = requiredString\(input\.contactName, '联系人姓名'/);
  assert.match(routeHandlers, /const phone = assertPhone\(input\.phone\)/);
  assert.match(routeHandlers, /const expertName = input\.expertName \? requiredString\(input\.expertName, '专家'/);
  assert.match(routeHandlers, /const attendanceCount = Number\(input\.attendanceCount\)/);
  assert.match(routeHandlers, /const content = requiredString\(input\.content, '动态内容'/);
  assert.match(routeHandlers, /const content = requiredString\(input\.content, '咨询内容'/);
});

test('product events are explicit opt-in compatible and reject identity or health fields', () => {
  const body = section('/v1/mobile/events');
  assert.notEqual(body, '', 'product event endpoint must be documented');
  assert.match(body, /additionalProperties: false/);
  const now = new Date('2026-08-26T08:00:00.000Z');
  const accepted = validateProductEventBatch({ events: [{
    eventId: '11111111-1111-4111-8111-111111111111',
    eventName: 'growth_report_opened',
    coarseValue: '本周',
    platform: 'ios',
    appVersion: '1.0.0',
    clientSessionId: '22222222-2222-4222-8222-222222222222',
    occurredAt: now.toISOString()
  }] }, now);
  assert.equal(accepted.length, 1);
  assert.equal(accepted[0].clientSessionHash.length, 64);
  assert.equal('clientSessionId' in accepted[0], false);
  assert.throws(() => validateProductEventBatch({ events: [{
    eventId: '11111111-1111-4111-8111-111111111111', eventName: 'growth_report_opened',
    platform: 'android', appVersion: '1.0', clientSessionId: '22222222-2222-4222-8222-222222222222',
    occurredAt: now.toISOString(), childId: 'child-private'
  }] }, now), /不允许的字段/);
  assert.doesNotMatch(schema.split('CREATE TABLE IF NOT EXISTS product_events')[1].split(');')[0], /user_id|child_id|student_id|health/i);
  assert.match(productEventRoutes, /product-events:\$\{user\.id\}/);
});

test('consent endpoint exposes an auditable withdrawal path', () => {
  const body = section('/v1/students/{studentId}/consent');
  assert.notEqual(body, '', 'consent endpoint must be documented');
  assert.match(body, /granted: \{ type: boolean \}/);
  assert.match(routeHandlers, /const granted = input\.granted !== false/);
  assert.match(routeHandlers, /data_consent\.revoke/);
});

test('message inbox keeps receiver scope and explicit read receipts', () => {
  assert.match(messageRoutes, /receiver_user_id=\$1/);
  assert.match(messageRoutes, /parts\[2\] !== user\.id/);
  assert.match(messageRoutes, /MESSAGE_NOT_FOUND/);
  assert.match(messageRoutes, /business_route AS "businessRoute"/);
  assert.match(messageRoutes, /read_at=COALESCE\(read_at,now\(\)\)/);
});

test('mobile session claims are documented and server-owned', () => {
  const session = section('/v1/auth/session');
  assert.notEqual(session, '', 'mobile session endpoint must be documented');
  assert.match(session, /MobileAuthClaims/);
  assert.match(openapi, /authorizedClassIds/);
  assert.match(openapi, /mobileEntryAllowed/);
  assert.match(authClaims, /async function authClaimsForUser/);
  assert.match(authClaims, /user_capability_overrides/);
  assert.match(server, /createAuthClaimsService/);
  assert.match(server, /url\.pathname === '\/v1\/auth\/session'/);
});

test('public registration cannot self-provision a teacher workbench', () => {
  // A client-side role picker is only presentation. Keep the denial at the
  // HTTP boundary so a crafted registration body cannot grant school access.
  assert.match(server, /url\.pathname === '\/v1\/auth\/register'/);
  assert.match(server, /input\.roleCode && input\.roleCode !== 'parent'/);
  assert.match(server, /ROLE_PROVISION_REQUIRED/);
  assert.match(server, /const role = 'parent'/);
});

test('account deletion exposes approval, idempotency, and anonymization paths', () => {
  const self = section('/v1/me/deletion-request');
  const admin = section('/v1/admin/account-deletion-requests/{requestId}');
  assert.notEqual(self, '', 'self account deletion endpoint must be documented');
  assert.match(self, /IdempotencyKey/);
  assert.notEqual(admin, '', 'admin account deletion review endpoint must be documented');
  assert.match(admin, /enum: \[approved, rejected\]/);
  assert.match(server, /account.delete.request/);
  assert.match(server, /account\.delete\.\$\{nextStatus\}/);
  assert.match(server, /enqueueJob\('account\.anonymize'/);
  assert.match(jobs, /account.delete.completed/);
});

test('class notification drafts expose remote lifecycle and scoped delivery', () => {
  const createDraft = section('/v1/classes/notifications');
  const drafts = section('/v1/classes/notifications/drafts');
  const updateDraft = section('/v1/classes/notifications/{notificationId}');
  const sendDraft = section('/v1/classes/notifications/{notificationId}/send');
  const retryDraft = section('/v1/classes/notifications/{notificationId}/retry');
  const receipt = section('/v1/classes/notifications/{notificationId}/receipt');
  assert.notEqual(createDraft, '', 'class notification create endpoint must be documented');
  assert.notEqual(drafts, '', 'class notification drafts endpoint must be documented');
  assert.notEqual(updateDraft, '', 'class notification update endpoint must be documented');
  assert.notEqual(sendDraft, '', 'class notification send endpoint must be documented');
  assert.notEqual(retryDraft, '', 'class notification retry endpoint must be documented');
  assert.notEqual(receipt, '', 'class notification receipt endpoint must be documented');
  assert.match(createDraft, /targetClassIds/);
  assert.match(createDraft, /scheduledAt/);
  assert.match(createDraft, /parentReceiptEnabled/);
  assert.match(updateDraft, /draftVersion/);
  assert.match(updateDraft, /delete:/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS notification_receipts/);
  assert.match(routeHandlers, /notification\.receipt\.acknowledge/);
  assert.match(routeHandlers, /parent_receipt_enabled/);
  assert.match(server, /function noticeClassIds|const noticeClassIds/);
  assert.match(routeHandlers, /VERSION_CONFLICT/);
  assert.match(routeHandlers, /notification\.draft\.discard/);
  assert.match(routeHandlers, /ur\.class_id=ANY\(\$2\)/);
  assert.match(routeHandlers, /teacherClassIds\(user, schoolId\)\.includes\(classId\)/);
  assert.match(notificationRoutes, /notification\.deliver/, 'notification delivery must use the durable job outbox');
  assert.match(notificationDelivery, /idempotency-key/, 'provider delivery must be idempotent');
  assert.match(notificationDelivery, /channel !== 'in_app'/, 'in-app delivery must not depend on an external provider');
  assert.match(notificationDelivery, /FROM device_installations WHERE user_id=\$1 AND status='active'/, 'push delivery must resolve encrypted devices from the authenticated installation registry');
  assert.match(notificationDelivery, /decryptPushToken/, 'push tokens must be decrypted only inside the trusted delivery boundary');
  assert.match(notificationDelivery, /invalidDeviceIds/, 'provider-invalid tokens must be retired instead of retried forever');
  assert.match(notificationDelivery, /WHERE NOT EXISTS/, 'worker retries must not duplicate inbox messages');
  assert.doesNotMatch(notificationRoutes, /channel !== 'in_app'\) return fail\(res, 503/, 'configured external channels must not be rejected unconditionally');
});

test('class circle exposes paged comments with ownership and attachment moderation hooks', () => {
  const comments = section('/v1/class-posts/{postId}/comments');
  assert.notEqual(comments, '', 'class post comments endpoint must be documented');
  assert.match(comments, /get:/);
  assert.match(comments, /pageSize/);
  assert.match(routeHandlers, /ownedByCurrentUser/);
  assert.match(routeHandlers, /class_post\.comment\.delete/);
  assert.match(routeHandlers, /class_post\.moderation/);
  assert.match(routeHandlers, /class_post_attachment/);
  assert.match(routeHandlers, /parentOnly,/);
  assert.match(routeHandlers, /CLASS_REQUIRED/);
  assert.match(routeHandlers, /只能向已绑定孩子所在班级发布动态/);
  assert.match(server, /hasRole, parentOnly, teacherOnly/);
  assert.match(openapi, /ownedByCurrentUser/);
  assert.match(schema, /idx_class_post_comments_post_created/);
});

test('file routes keep owner scope, content validation, and idempotent upload metadata', () => {
  assert.match(server, /handleFileRoutes/);
  assert.match(fileRoutes, /beginIdempotentRequest/);
  assert.match(fileRoutes, /FILE_TYPE_NOT_ALLOWED/);
  assert.match(fileRoutes, /FILE_SIGNATURE_INVALID/);
  assert.match(fileRoutes, /file\.owner_id !== user\.id/);
  assert.match(fileRoutes, /classPostFileVisibleToUser/);
  assert.match(fileRoutes, /Cache-Control': 'private, no-store'/);
});

test('activity lifecycle exposes list detail edit cancel history and capacity guard', () => {
  for (const route of [
    '/v1/activities',
    '/v1/activities/{activityId}',
    '/v1/activities/registrations/history',
    '/v1/activities/{activityId}/registrations/{registrationId}',
    '/v1/activities/{activityId}/registrations/{registrationId}/cancel'
  ]) {
    assert.notEqual(section(route), '', `${route} must be documented`);
  }
  assert.match(openapi, /childId: \{ type: string \}/);
  assert.match(openapi, /expectedVersion: \{ type: integer \}/);
  assert.match(routeHandlers, /ACTIVITY_FULL/);
  assert.match(routeHandlers, /ACTIVITY_REGISTRATION_CLOSED/);
  assert.match(routeHandlers, /activity\.registration\.update/);
  assert.match(routeHandlers, /activity\.registration\.cancel/);
  assert.match(routeHandlers, /报名信息已更新，请刷新后重试/);
  assert.match(section('/v1/activities/{activityId}/registrations/{registrationId}/cancel'), /expectedVersion/);
  assert.match(routeHandlers, /status NOT IN \('cancelled','rejected'\)/);
});

test('expert appointment lifecycle uses stable expert slot and appointment ids', () => {
  for (const route of [
    '/v1/experts',
    '/v1/experts/{expertId}',
    '/v1/experts/{expertId}/available-slots',
    '/v1/expert-appointments/history',
    '/v1/expert-appointments/{appointmentId}/reschedule',
    '/v1/expert-appointments/{appointmentId}/cancel'
  ]) {
    assert.notEqual(section(route), '', `${route} must be documented`);
  }
  assert.match(openapi, /slotId: \{ type: string \}/);
  assert.match(openapi, /expertId: \{ type: string \}/);
  assert.match(openapi, /required: \[slotId\]/);
  assert.match(routeHandlers, /SLOT_FULL/);
  assert.match(routeHandlers, /VERSION_CONFLICT/);
  assert.match(routeHandlers, /expert\.appointment\.reschedule/);
  assert.match(routeHandlers, /expert\.appointment\.cancel/);
  assert.match(routeHandlers, /预约已更新，请刷新后重试/);
  assert.match(section('/v1/expert-appointments/{appointmentId}/cancel'), /expectedVersion/);
  assert.match(routeHandlers, /FOR UPDATE/);
});

test('class circle documents commercial moderation attachments and actions', () => {
  for (const route of [
    '/v1/class-posts',
    '/v1/class-posts/{postId}',
    '/v1/class-posts/{postId}/comments',
    '/v1/class-posts/{postId}/report',
    '/v1/class-posts/{postId}/pin'
  ]) {
    assert.notEqual(section(route), '', `${route} must be documented`);
  }
  assert.match(openapi, /attachments:/);
  assert.match(openapi, /visibilityScope/);
  assert.match(openapi, /displayName/);
  assert.match(openapi, /authorRole/);
  assert.match(routeHandlers, /authorRole/);
  assert.match(routeHandlers, /moderation_status/);
  assert.match(routeHandlers, /class_post_reports/);
  assert.match(routeHandlers, /class_post_comments/);
  assert.match(routeHandlers, /class_post\.pin/);
  assert.match(routeHandlers, /deleted_at/);
  assert.match(routeHandlers, /classPostVisibleToUser/);
  assert.match(routeHandlers, /FILE_NOT_READY/);
  assert.match(routeHandlers, /class_post\.comment\.delete/);
  assert.match(routeHandlers, /class_post\.moderation/);
  assert.match(openapi, /comments\/\{commentId\}/);
  assert.match(openapi, /admin\/class-posts\/\{postId\}\/moderation/);
});

test('family health observations are structured and child-scoped', () => {
  const route = section('/v1/students/{studentId}/health-observations');
  assert.notEqual(route, '', 'health observation endpoint must be documented');
  assert.match(route, /questionId/);
  assert.match(route, /selectedOptionIds/);
  assert.match(route, /formVersion/);
  assert.match(route, /questionType/);
  assert.match(route, /enum: \[single, multiple, frequency, severity, text\]/);
  assert.match(route, /expectedVersion/);
  assert.match(routeHandlers, /family_health_observations/);
  assert.match(routeHandlers, /只有已绑定监护人可以查看家庭观察记录/);
  assert.match(routeHandlers, /只有已绑定监护人可以提交家庭观察记录/);
  assert.match(server, /async function guardianStudentForUser/);
  assert.match(server, /parent_student_bindings/);
  assert.match(routeHandlers, /guardianStudentForUser\(user, parts\[2\]\)/);
  assert.match(routeHandlers, /家庭观察记录已在其他设备更新/);
  assert.match(routeHandlers, /family_health_observation\.upsert/);
});

test('guided training sessions are structured, child-scoped, and never accept raw media', () => {
  const route = section('/v1/students/{studentId}/training-sessions');
  assert.notEqual(route, '', 'training session endpoint must be documented');
  for (const field of ['sessionId', 'dayId', 'completionRatio', 'qualityScore', 'modelVersion', 'visualUnits']) {
    assert.match(route, new RegExp(field), `${field} must be documented`);
  }
  assert.match(routeHandlers, /training_sessions/);
  assert.match(routeHandlers, /guardianStudentForUser\(user, parts\[2\]\)/);
  assert.match(routeHandlers, /跟练记录编号已被占用/);
  assert.match(routeHandlers, /training_session\.upsert/);
  assert.match(routeHandlers, /MODEL_VALIDATION_PENDING/);
  assert.match(routeHandlers, /MODEL_REGISTRY\.followAlong\.status !== 'human-validated'/);
  assert.doesNotMatch(server, /cameraFrame|rawVideo|rawPhoto/);
});

test('content operations publish immutable mobile manifests with scoped versions', () => {
  for (const route of [
    '/v1/mobile/content-manifest',
    '/v1/admin/content/releases',
    '/v1/admin/content/releases/{releaseId}/items',
    '/v1/admin/content/releases/{releaseId}/publish',
    '/v1/admin/content/releases/{releaseId}/withdraw'
  ]) assert.notEqual(section(route), '', `${route} must be documented`);
  assert.match(contentOperationRoutes, /content_release_items/);
  assert.match(contentOperationRoutes, /CONTENT_RELEASE_EMPTY/);
  assert.match(contentOperationRoutes, /schoolAllowed\(user, schoolId\)/);
  assert.match(contentOperationRoutes, /beginIdempotentRequest/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS content_releases/);
});

test('family exercise check-ins are date-scoped, versioned, and child-authorized', () => {
  const route = section('/v1/students/{studentId}/health-checkins');
  assert.notEqual(route, '', 'health check-in endpoint must be documented');
  for (const field of ['checkInDate', 'activityType', 'durationMinutes', 'intensity', 'completedRecommended', 'parentNote', 'expectedVersion']) {
    assert.match(route, new RegExp(field), `${field} must be documented`);
  }
  assert.match(routeHandlers, /health_checkins/);
  assert.match(routeHandlers, /只有家庭账号可以提交运动打卡/);
  assert.match(routeHandlers, /不能记录未来日期/);
  assert.match(routeHandlers, /打卡已在其他设备更新/);
  assert.match(routeHandlers, /health_checkin\.upsert/);
  assert.match(schema, /UNIQUE\(user_id, child_id, check_in_date\)/);
});

test('remote workflow acceptance follows the real session schema and exercises isolated lifecycles', () => {
  assert.match(remoteWorkflowSmoke, /ready\.data\?\.migration\?\.healthy/);
  assert.doesNotMatch(remoteWorkflowSmoke, /ready\.data\?\.migrations/);
  assert.match(remoteWorkflowSmoke, /session\.data\?\.user\?\.id/);
  assert.doesNotMatch(remoteWorkflowSmoke, /session\.data\?\.userId/);
  assert.doesNotMatch(remoteWorkflowSmoke, /parent\.session\.userId/);
  assert.match(remoteWorkflowSmoke, /REMOTE_E2E_ALLOW_LIFECYCLE_WRITES/);
  assert.match(remoteWorkflowSmoke, /parent\.activity\.lifecycle/);
  assert.match(remoteWorkflowSmoke, /parent\.appointment\.lifecycle/);
  assert.match(remoteWorkflowSmoke, /parent\.activity\.optimistic-conflict/);
  assert.match(remoteWorkflowSmoke, /parent\.appointment\.optimistic-conflict/);
  assert.match(remoteWorkflowSmoke, /expected: \[409\]/);
});
