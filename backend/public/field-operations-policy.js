(() => {
  const selectPrimaryAction = ({ taskChosen, queueReady, deviceReady, canGenerateQueue, issues = [], onlineDevices = 0, activeDeviceCount = 0 }) => {
    const issue = (target) => issues.find((item) => item.target === target);
    if (!taskChosen) return { target: 'task', label: '选择测评任务' };
    if (!queueReady) {
      if (issue('stations')) return { target: 'stations', label: '配置匹配测试点' };
      if (canGenerateQueue) return { target: 'generate', label: '生成候测名单' };
      return { target: 'queue', label: '检查候测名单' };
    }
    if (!deviceReady) {
      if (issue('stations')) return { target: 'stations', label: '配置匹配测试点' };
      if (!activeDeviceCount) return { target: 'devices', label: '接入场地设备' };
      if (!onlineDevices) return { target: 'devices', label: `恢复场地设备（0/${activeDeviceCount} 在线）` };
      return { target: 'devices', label: '完成设备开测检查' };
    }
    if (issue('conflicts')) return { target: 'conflicts', label: '处理同步冲突' };
    if (issue('sessions')) return { target: 'sessions', label: '处理异常会话' };
    if (issue('timing')) return { target: 'timing', label: '处理超时学生' };
    if (issue('queue')) return { target: 'queue', label: '处理学生分配' };
    return { target: 'queue', label: '查看现场队列' };
  };

  const policyHost = typeof window === 'undefined' ? globalThis : window;
  policyHost.XiangshangFieldOperationsPolicy = Object.freeze({ selectPrimaryAction });
})();
