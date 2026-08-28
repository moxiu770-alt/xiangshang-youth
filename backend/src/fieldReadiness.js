const objectValue = (value) => value && typeof value === 'object' && !Array.isArray(value) ? value : {};

const numericValue = (value) => {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
};

const check = (key, category, label, status, detail, remediation, measuredValue = null) => ({
  key, category, label, status, detail, remediation, measuredValue
});

export function fieldHardwareReadiness(device, calibration) {
  const health = objectValue(device?.health_json ?? device?.health);
  const selfTest = objectValue(health.selfTest);
  const capture = objectValue(health.capture);
  const calibrationCheck = objectValue(health.calibration);
  const storage = objectValue(health.storage);
  const storageFreeMb = numericValue(storage.freeMb ?? health.storageFreeMb);
  const frameSyncOffsetMs = numericValue(capture.frameSyncOffsetMs);
  const calibrationErrorCm = numericValue(calibrationCheck.errorCm);
  const depthCameraCount = numericValue(capture.depthCameraCount);
  const rgbCameraCount = numericValue(capture.rgbCameraCount);
  const checks = [];
  const add = (key, category, label, passed, failure, remediation, measuredValue = null) => checks.push(check(key, category, label, passed ? 'passed' : 'blocked', passed ? '已通过' : failure, remediation, measuredValue));

  add('health_contract', 'connection', '场地自检上报', health.schemaVersion === 'field-health/v1', '未上报 field-health/v1 场地自检结果', '启动 Windows 场地端并等待一次完整心跳', health.schemaVersion || null);
  add('self_test', 'hardware', '边缘主机自检', selfTest.passed === true, '边缘主机自检未通过', selfTest.message || '检查采集设备、电源和驱动后重新自检', selfTest.completedAt || null);
  add('edge_host', 'connection', '设备注册类型', device?.device_type === 'edge_host' || device?.deviceType === 'edge_host', '正式采集必须由已注册的边缘主机发起', '在后台注册类型为边缘主机的 Windows 设备', device?.device_type || device?.deviceType || null);
  add('capture_adapter', 'hardware', '认证采集适配器', capture.adapterReady === true && Boolean(String(capture.adapterName || '').trim()), '视觉采集适配器未就绪', '安装厂商适配器后，在 Windows 场地端点击右侧“接入采集设备”选择 DLL', capture.adapterName || null);
  add('depth_cameras', 'hardware', '双深度摄像头', depthCameraCount != null && depthCameraCount >= 2, '双深度摄像头未全部通过自检', '检查两台深度摄像头的连接、驱动和视野', depthCameraCount);
  add('rgb_camera', 'hardware', '高速 RGB 摄像头', rgbCameraCount != null && rgbCameraCount >= 1, '高速 RGB 摄像头未通过自检', '检查高速 RGB 摄像头的连接和驱动', rgbCameraCount);
  add('gpu', 'hardware', 'GPU 推理环境', capture.gpuReady === true, '边缘 GPU 推理环境未就绪', '检查显卡驱动、推理运行库和适配器配置', capture.gpuReady === true);
  add('frame_sync', 'hardware', '多机帧同步', frameSyncOffsetMs != null && frameSyncOffsetMs <= 33.4, '多机帧同步未达标（需不超过 33.4ms）', '重新同步相机时钟并检查 USB/网络带宽', frameSyncOffsetMs);
  add('storage', 'storage', '本地证据空间', storageFreeMb != null && storageFreeMb >= 5_120, '本地证据存储空间不足（至少 5GB）', '清理本地磁盘或调整证据存储位置', storageFreeMb);

  if (calibration) {
    add('calibration_check', 'calibration', '设备标定复核', calibrationCheck.passed === true, '场地标定复核未通过', '在场地端重新执行设备标定复核', calibrationCheck.passed === true);
    add('calibration_version', 'calibration', '标定版本一致', String(calibrationCheck.version || '') === String(calibration.version), '设备标定版本与中央下发版本不一致', '刷新配置并重新加载后台当前标定', calibrationCheck.version || null);
    add('calibration_checksum', 'calibration', '标定校验一致', String(calibrationCheck.checksumSha256 || '').toLowerCase() === String(calibration.checksumSha256 || calibration.checksum_sha256 || '').toLowerCase(), '设备标定校验和与中央下发版本不一致', '重新下发同一份标定文件，禁止手工改写', calibrationCheck.checksumSha256 || null);
    add('calibration_error', 'calibration', '标定误差', calibrationErrorCm != null && calibrationErrorCm <= 5, '场地标定误差未达标（需不超过 5cm）', '重新布置标定板并执行标定，误差需不超过 5cm', calibrationErrorCm);
  } else {
    for (const [key, label] of [['calibration_check', '设备标定复核'], ['calibration_version', '标定版本一致'], ['calibration_checksum', '标定校验一致'], ['calibration_error', '标定误差']]) {
      checks.push(check(key, 'calibration', label, 'pending', '等待后台下发有效标定配置', '先在后台完成场地标定'));
    }
  }
  add('emergency_stop', 'safety', '本地紧急停止', health.emergencyStop !== true, '场地端处于紧急停止状态', '排除现场风险后在 Windows 场地端人工解除', health.emergencyStop === true);

  const blockers = checks.filter((item) => item.status === 'blocked').map((item) => item.detail);
  return {
    ready: blockers.length === 0,
    blockers,
    checks,
    summary: {
      schemaVersion: String(health.schemaVersion || ''),
      selfTestPassed: selfTest.passed === true,
      selfTestAt: selfTest.completedAt || null,
      adapterName: String(capture.adapterName || '') || null,
      depthCameraCount,
      rgbCameraCount,
      gpuReady: capture.gpuReady === true,
      frameSyncOffsetMs,
      storageFreeMb,
      calibrationVersion: String(calibrationCheck.version || '') || null,
      calibrationErrorCm,
      emergencyStop: health.emergencyStop === true
    }
  };
}

export function fieldReadiness(device, station, calibration, options = {}) {
  const controlState = String(device?.control_state || device?.controlState || 'running');
  const deviceStatus = String(device?.status || 'offline');
  const heartbeatValue = device?.last_heartbeat_at || device?.lastHeartbeatAt || null;
  const heartbeatAt = heartbeatValue ? new Date(heartbeatValue) : null;
  const now = options.now instanceof Date ? options.now : new Date(options.now || Date.now());
  const heartbeatMaxAgeSeconds = Number.isFinite(Number(options.heartbeatMaxAgeSeconds)) && Number(options.heartbeatMaxAgeSeconds) > 0 ? Number(options.heartbeatMaxAgeSeconds) : 90;
  const heartbeatAgeSeconds = heartbeatAt && Number.isFinite(heartbeatAt.valueOf()) && Number.isFinite(now.valueOf()) ? Math.max(0, Math.round((now - heartbeatAt) / 1_000)) : null;
  const heartbeatIso = heartbeatAt && Number.isFinite(heartbeatAt.valueOf()) ? heartbeatAt.toISOString() : null;
  const heartbeatFresh = deviceStatus === 'online' && heartbeatAgeSeconds != null && heartbeatAgeSeconds <= heartbeatMaxAgeSeconds;
  const stationStatusLabel = { online: '在线', offline: '离线', maintenance: '维护中', paused: '已暂停', disabled: '已停用' }[station?.status] || station?.status;
  const checks = [];
  const add = (key, category, label, passed, failure, remediation, measuredValue = null) => checks.push(check(key, category, label, passed ? 'passed' : 'blocked', passed ? '已通过' : failure, remediation, measuredValue));

  add('central_control', 'control', '中央控制状态', controlState === 'running', controlState === 'stopped' ? '中央管理端已停止现场操作' : '中央管理端已暂停现场操作', '由后台管理员确认现场安全后恢复运行', controlState);
  add('device_online', 'connection', '设备在线心跳', heartbeatFresh, deviceStatus !== 'online' ? 'Windows 场地端当前离线' : heartbeatAgeSeconds == null ? '设备尚未上报有效心跳' : `设备心跳已超过 ${heartbeatMaxAgeSeconds} 秒`, '启动 Windows 场地端并检查网络、服务器地址和设备凭证', { status: deviceStatus, heartbeatAt: heartbeatIso, ageSeconds: heartbeatAgeSeconds, maxAgeSeconds: heartbeatMaxAgeSeconds });
  add('station_binding', 'connection', '测试点绑定', Boolean(device?.station_id || device?.stationId) && Boolean(station), device?.station_id || device?.stationId ? '测试点不存在或已删除' : '设备尚未绑定测试点', '在后台将 Windows 边缘主机绑定到有效测试点', station?.id || null);
  if (station) add('station_online', 'connection', '测试点在线', station.status === 'online', `测试点状态为${stationStatusLabel}，请先检查设备心跳或维护状态`, '启动 Windows 场地端并检查网络、凭证和设备心跳', station.status);
  else checks.push(check('station_online', 'connection', '测试点在线', 'pending', '等待设备绑定有效测试点', '先完成测试点绑定'));
  add('central_calibration', 'calibration', '中央标定配置', Boolean(calibration), '尚未下发有效标定配置', '在后台下发并激活由标定工具生成的配置', calibration?.version || null);

  const hardware = fieldHardwareReadiness(device, calibration);
  checks.push(...hardware.checks);
  const blockers = checks.filter((item) => item.status === 'blocked').map((item) => item.detail);
  return {
    ready: blockers.length === 0,
    controlState,
    stationStatus: station?.status || null,
    calibrationVersion: calibration?.version || null,
    hardware: hardware.summary,
    blockers,
    checks
  };
}
