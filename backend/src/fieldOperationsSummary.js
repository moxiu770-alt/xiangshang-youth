import { fieldReadiness } from './fieldReadiness.js';
import { dateOnlyText } from './dateOnly.js';

const count = (value) => Number.isFinite(Number(value)) ? Number(value) : 0;

export function summarizeFieldOperations({ devices = [], queue = {}, now = new Date(), heartbeatMaxAgeSeconds = 90 } = {}) {
  const activeDevices = devices.filter((device) => device.status !== 'disabled');
  const deviceEntries = activeDevices.map((device) => ({
    device,
    readiness: fieldReadiness(
      { ...device, station_id: device.stationId ?? device.station_id, device_type: device.deviceType ?? device.device_type, health_json: device.health ?? device.health_json },
      (device.stationId ?? device.station_id) ? { id: device.stationId ?? device.station_id, status: device.stationStatus ?? device.station_status } : null,
      (device.activeCalibrationVersion ?? device.active_calibration_version) ? { version: device.activeCalibrationVersion ?? device.active_calibration_version, checksumSha256: device.activeCalibrationChecksumSha256 ?? device.active_calibration_checksum_sha256 } : null,
      { now, heartbeatMaxAgeSeconds }
    )
  }));
  const readiness = deviceEntries.map((item) => item.readiness);
  const onlineDevices = readiness.filter((item) => item.checks.find((check) => check.key === 'device_online')?.status === 'passed').length;
  const readyDevices = readiness.filter((item) => item.ready).length;
  const heartbeat = (device) => {
    const value = device.lastHeartbeatAt ?? device.last_heartbeat_at;
    const parsed = value ? new Date(value) : null;
    return parsed && Number.isFinite(parsed.valueOf()) ? parsed.toISOString() : null;
  };
  const neverConnectedDevices = activeDevices.filter((device) => !heartbeat(device)).length;
  const unboundDevices = activeDevices.filter((device) => !(device.stationId ?? device.station_id)).length;
  const onlineEntry = deviceEntries.find((item) => item.readiness.checks.find((check) => check.key === 'device_online')?.status === 'passed');
  const recoveryEntry = onlineEntry || [...deviceEntries].sort((left, right) =>
    Number(Boolean(right.device.signedRequestReady ?? right.device.signed_request_ready)) - Number(Boolean(left.device.signedRequestReady ?? left.device.signed_request_ready))
    || Number(!heartbeat(right.device)) - Number(!heartbeat(left.device))
  )[0] || null;
  const focusDevice = recoveryEntry ? {
    id: recoveryEntry.device.id || null,
    name: recoveryEntry.device.name || recoveryEntry.device.deviceCode || recoveryEntry.device.device_code || 'Windows 场地端',
    deviceCode: recoveryEntry.device.deviceCode ?? recoveryEntry.device.device_code ?? null,
    stationName: recoveryEntry.device.stationName ?? recoveryEntry.device.station_name ?? null,
    softwareVersion: recoveryEntry.device.softwareVersion ?? recoveryEntry.device.software_version ?? null,
    lastHeartbeatAt: heartbeat(recoveryEntry.device),
    primaryBlocker: recoveryEntry.readiness.blockers[0] || null
  } : null;
  const publishedTaskCount = count(queue.publishedTaskCount ?? queue.published_task_count);
  const selectedTaskId = queue.selectedTaskId ?? queue.selected_task_id ?? null;
  const selectedTaskTitle = queue.selectedTaskTitle ?? queue.selected_task_title ?? null;
  const selectedTaskDate = dateOnlyText(queue.selectedTaskDate ?? queue.selected_task_date);
  const taskContext = selectedTaskTitle ? `“${selectedTaskTitle}”` : '当前任务';
  const activeQueueCount = count(queue.activeQueueCount ?? queue.active_queue_count);
  const waitingCount = count(queue.waitingCount ?? queue.waiting_count);
  const testingCount = count(queue.testingCount ?? queue.testing_count);
  const overdueCount = count(queue.overdueCount ?? queue.overdue_count);
  let state = 'ready';
  let message = `${taskContext}：${readyDevices} 台设备可开测，${waitingCount} 人等待叫号。`;
  let primaryAction = { target: 'queue', label: '查看本站学生' };
  if (!publishedTaskCount) {
    state = 'no_task';
    message = '暂无已发布任务；先发布测评任务。';
    primaryAction = { target: 'task', label: '发布测评任务' };
  } else if (!activeQueueCount) {
    state = 'no_queue';
    message = `${taskContext}尚未生成候测名单。`;
    primaryAction = { target: 'generate', label: '生成候测名单' };
  } else if (!activeDevices.length) {
    state = 'no_device';
    message = `${taskContext}已有学生，但尚未注册 Windows 场地端。`;
    primaryAction = { target: 'devices', label: '注册场地设备' };
  } else if (!onlineDevices) {
    state = 'offline';
    message = neverConnectedDevices
      ? `${taskContext}：0/${activeDevices.length} 台设备在线，其中 ${neverConnectedDevices} 台从未连接；先启动“${focusDevice?.name || 'Windows 场地端'}”。`
      : `${taskContext}：0/${activeDevices.length} 台设备在线；先恢复“${focusDevice?.name || 'Windows 场地端'}”连接。`;
    primaryAction = { target: 'devices', label: '恢复场地设备' };
  } else if (!readyDevices) {
    state = 'blocked';
    message = `${taskContext}：${onlineDevices}/${activeDevices.length} 台设备在线，但没有设备通过开测检查${focusDevice?.primaryBlocker ? `：${focusDevice.primaryBlocker}` : ''}。`;
    primaryAction = { target: 'devices', label: '完成开测检查' };
  } else if (overdueCount) {
    state = 'attention';
    message = `${taskContext}：${readyDevices} 台设备可开测，另有 ${overdueCount} 名学生等待超时。`;
    primaryAction = { target: 'timing', label: '处理超时学生' };
  }
  return {
    state,
    message,
    publishedTaskCount,
    selectedTaskId,
    selectedTaskTitle,
    selectedTaskDate,
    activeQueueCount,
    waitingCount,
    testingCount,
    overdueCount,
    totalDevices: activeDevices.length,
    onlineDevices,
    readyDevices,
    blockedDevices: Math.max(0, activeDevices.length - readyDevices),
    neverConnectedDevices,
    unboundDevices,
    focusDevice,
    primaryAction
  };
}
