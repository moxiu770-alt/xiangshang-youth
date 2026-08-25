(() => {
  const sectionLabels = { overview: '数据总览', tasks: '测评任务', students: '学生档案', reports: '报告中心', analysis: '数据分析', accounts: '账户分桶', settings: '运营提醒' };
  const pageState = { tasks: 1, students: 1, pageSize: 8 };

  const ensurePager = (id, targetId) => {
    let node = document.getElementById(id);
    if (node) return node;
    node = document.createElement('div');
    node.id = id;
    node.className = 'pager';
    const target = document.getElementById(targetId);
    target?.parentElement?.parentElement?.append(node);
    return node;
  };
  const renderPager = (node, page, total, onChange) => {
    if (!node) return;
    const pages = Math.max(1, Math.ceil(total / pageState.pageSize));
    node.innerHTML = `<span>第 ${page} / ${pages} 页，共 ${total} 条</span><span class="pager-actions"><button class="ghost-btn" data-pager="prev" ${page <= 1 ? 'disabled' : ''}>上一页</button><button class="ghost-btn" data-pager="next" ${page >= pages ? 'disabled' : ''}>下一页</button></span>`;
    node.querySelector('[data-pager="prev"]')?.addEventListener('click', () => onChange(Math.max(1, page - 1)));
    node.querySelector('[data-pager="next"]')?.addEventListener('click', () => onChange(Math.min(pages, page + 1)));
  };

  const renderTasksPaged = () => {
    const table = document.getElementById('taskTable');
    if (!table) return;
    const query = String(state.search || '').trim().toLowerCase();
    const all = (state.dashboard?.tasks || []).filter((task) => task.status !== 'draft').filter((task) => !query || `${task.title}${task.gradeName}${task.className}`.toLowerCase().includes(query));
    const pages = Math.max(1, Math.ceil(all.length / pageState.pageSize));
    pageState.tasks = Math.min(pageState.tasks, pages);
    const items = all.slice((pageState.tasks - 1) * pageState.pageSize, pageState.tasks * pageState.pageSize);
    table.innerHTML = items.length ? items.map((task) => {
      const rate = task.totalCount ? Math.round(task.completedCount / task.totalCount * 100) : 0;
      return `<tr class="clickable-row" tabindex="0" data-task-id="${escapeHtml(task.id)}"><td><strong>${escapeHtml(task.title)}</strong></td><td>${escapeHtml(task.gradeName || '全校')} / ${escapeHtml(task.className || '全校')}</td><td><div class="progress-cell"><div class="mini-progress"><i style="width:${rate}%"></i></div><span>${task.completedCount || 0}/${task.totalCount || 0}</span></div></td><td><span class="status ${statusClass(task.status)}">${escapeHtml(task.status || '待发布')}</span></td><td>${dateText(task.date)}</td></tr>`;
    }).join('') : '<tr><td colspan="5"><div class="empty-chart">没有匹配的测评任务</div></td></tr>';
    renderPager(ensurePager('taskPager', 'taskTable'), pageState.tasks, all.length, (next) => { pageState.tasks = next; renderTasksPaged(); });
  };

  const renderStudentsPaged = () => {
    const table = document.getElementById('studentTable');
    if (!table) return;
    const query = String(state.search || '').trim().toLowerCase();
    const all = (state.dashboard?.students || []).filter((student) => !query || `${student.name}${student.grade}${student.className}`.toLowerCase().includes(query));
    const pages = Math.max(1, Math.ceil(all.length / pageState.pageSize));
    pageState.students = Math.min(pageState.students, pages);
    const items = all.slice((pageState.students - 1) * pageState.pageSize, pageState.students * pageState.pageSize);
    table.innerHTML = items.length ? items.map((student) => `<tr class="clickable-row" tabindex="0" data-student-id="${escapeHtml(student.id)}"><td><div class="student-cell"><span class="student-mini">${escapeHtml(String(student.name || '').slice(0, 1))}</span><span><strong>${escapeHtml(student.name)}</strong><small>${escapeHtml(student.gender || '')} · ${escapeHtml(student.birthDate ? dateText(student.birthDate) : '未填写生日')}</small></span></div></td><td>${escapeHtml(student.grade)} / ${escapeHtml(student.className)}</td><td><span class="status ${statusClass(student.taskStatus)}">${escapeHtml(student.taskStatus || '未签到')}</span></td><td><strong>${student.totalScore == null ? '-' : Number(student.totalScore).toFixed(1)}</strong><span class="hint"> / 35</span></td><td>${student.isPovertyArea ? '<span class="status attention">重点帮扶</span>' : escapeHtml(student.region || '—')}</td></tr>`).join('') : '<tr><td colspan="5"><div class="empty-chart">没有匹配的学生</div></td></tr>';
    renderPager(ensurePager('studentPager', 'studentTable'), pageState.students, all.length, (next) => { pageState.students = next; renderStudentsPaged(); });
  };

  renderTasks = renderTasksPaged;
  renderStudents = renderStudentsPaged;
  document.querySelectorAll('[data-section]').forEach((node) => node.addEventListener('click', () => {
    const label = sectionLabels[node.dataset.section];
    if (label) document.querySelector('.crumb strong').textContent = label;
  }));
  document.getElementById('globalSearch')?.addEventListener('input', () => { pageState.tasks = 1; pageState.students = 1; renderTasksPaged(); renderStudentsPaged(); });
  document.getElementById('studentSearch')?.addEventListener('input', () => { pageState.students = 1; renderStudentsPaged(); });

  const detailModal = document.createElement('div');
  detailModal.id = 'detailModal';
  detailModal.className = 'modal-backdrop hidden';
  detailModal.innerHTML = '<div class="modal detail-modal"><div class="modal-head"><div><h2 id="detailTitle">详情</h2><p id="detailSubtitle">查看当前业务数据</p></div><button class="modal-close" aria-label="关闭详情">×</button></div><div id="detailBody"></div></div>';
  document.body.append(detailModal);
  detailModal.setAttribute('role', 'dialog');
  detailModal.setAttribute('aria-modal', 'true');
  detailModal.setAttribute('aria-labelledby', 'detailTitle');
  const closeDetail = () => { detailModal.classList.add('hidden'); document.body.classList.remove('modal-open'); };
  detailModal.querySelector('.modal-close').addEventListener('click', closeDetail);
  const openDetail = async (kind, id) => {
    const title = document.getElementById('detailTitle');
    const subtitle = document.getElementById('detailSubtitle');
    const body = document.getElementById('detailBody');
    detailModal.classList.remove('hidden');
    document.body.classList.add('modal-open');
    if (kind === 'task') {
      const task = (state.dashboard?.tasks || []).find((item) => item.id === id);
      title.textContent = task?.title || '测评任务详情';
      subtitle.textContent = '任务范围与完成进度';
      body.innerHTML = `<div class="detail-grid"><div><span>测评范围</span><strong>${escapeHtml(task?.gradeName || '全校')} / ${escapeHtml(task?.className || '全校')}</strong></div><div><span>测评日期</span><strong>${escapeHtml(dateText(task?.date))}</strong></div><div><span>当前状态</span><strong>${escapeHtml(task?.status || '—')}</strong></div><div><span>完成进度</span><strong>${task?.completedCount || 0} / ${task?.totalCount || 0}</strong></div></div><div class="detail-note">测评项目：${escapeHtml((task?.items || []).join('、') || '未配置')}</div><div class="detail-actions"><button class="secondary-btn" data-task-admin="sync" data-task-id="${escapeHtml(id)}">同步新增学生</button><button class="secondary-btn" data-task-admin="clone" data-task-id="${escapeHtml(id)}">复制任务</button>${task?.status === 'closed' ? '' : `<button class="secondary-btn" data-task-admin="close" data-task-id="${escapeHtml(id)}">关闭任务</button>`}</div><div id="taskStudentList" class="task-student-list">正在读取任务学生...</div>`;
      try {
        const students = await api(`/v1/tasks/${encodeURIComponent(id)}/students`);
        const list = students || [];
        document.getElementById('taskStudentList').innerHTML = list.length ? `<div class="detail-list-head"><strong>任务学生</strong><button class="secondary-btn" data-batch-task="${escapeHtml(id)}">批量标记已完成</button></div>${list.map((item) => `<label class="task-student-item"><input type="checkbox" value="${escapeHtml(item.studentId)}" data-task-version="${escapeHtml(item.version)}" ${item.status === '已完成' ? 'checked disabled' : ''}><span><strong>${escapeHtml(item.studentName)}</strong><small>${escapeHtml(item.className || '')} · ${escapeHtml(item.status)}</small></span></label>`).join('')}` : '<div class="empty-chart">该任务暂无学生</div>';
      } catch (error) { document.getElementById('taskStudentList').textContent = error.message || '任务学生加载失败'; }
      return;
    }
    const student = (state.dashboard?.students || []).find((item) => item.id === id);
    title.textContent = student?.name || '学生详情';
    subtitle.textContent = '学生档案与最新报告';
    body.innerHTML = `<div class="detail-grid"><div><span>班级</span><strong>${escapeHtml(student?.grade || '—')} / ${escapeHtml(student?.className || '—')}</strong></div><div><span>测评状态</span><strong>${escapeHtml(student?.taskStatus || '未签到')}</strong></div><div><span>综合得分</span><strong>${student?.totalScore == null ? '—' : `${Number(student.totalScore).toFixed(1)} / 35`}</strong></div><div><span>地区标记</span><strong>${student?.isPovertyArea ? '重点帮扶' : escapeHtml(student?.region || '—')}</strong></div></div><div id="detailReport" class="detail-note">正在读取最新报告...</div>`;
    try {
      const report = await api(`/v1/students/${encodeURIComponent(id)}/report`);
      document.getElementById('detailReport').textContent = `风险等级：${report.riskLevel || '待生成'} · 建议：${(report.trainingAdvice || []).join('、') || '暂无建议'}`;
    } catch { document.getElementById('detailReport').textContent = '当前暂无已发布诊断报告。'; }
  };
  document.addEventListener('click', (event) => {
    const taskAdmin = event.target.closest('[data-task-admin]');
    if (taskAdmin) {
      const action = taskAdmin.dataset.taskAdmin;
      const taskId = taskAdmin.dataset.taskId;
      const request = action === 'sync'
        ? api(`/v1/admin/tasks/${encodeURIComponent(taskId)}/sync-students`, { method: 'POST', headers: { 'Idempotency-Key': `task-sync-${Date.now()}` }, body: '{}' })
        : action === 'clone'
          ? api(`/v1/admin/tasks/${encodeURIComponent(taskId)}/clone`, { method: 'POST', headers: { 'Idempotency-Key': `task-clone-${Date.now()}` }, body: '{}' })
          : api(`/v1/admin/tasks/${encodeURIComponent(taskId)}/status`, { method: 'PATCH', headers: { 'Idempotency-Key': `task-close-${Date.now()}` }, body: JSON.stringify({ status: 'closed' }) });
      request.then((result) => { toast(action === 'sync' ? `已新增 ${result.addedCount || 0} 名学生` : action === 'clone' ? '任务副本已创建' : '任务已关闭'); closeDetail(); loadAll(); }).catch((error) => toast(error.message, true));
      return;
    }
    const batchButton = event.target.closest('[data-batch-task]');
    if (batchButton) {
      const selected = [...document.querySelectorAll('#taskStudentList input[type="checkbox"]:checked:not(:disabled)')];
      if (!selected.length) { toast('请先选择需要批量更新的学生', true); return; }
      api('/v1/admin/tasks/batch-status', { method: 'POST', headers: { 'Idempotency-Key': `batch-status-${Date.now()}-${Math.random().toString(16).slice(2)}` }, body: JSON.stringify({ updates: selected.map((input) => ({ taskId: batchButton.dataset.batchTask, studentId: input.value, status: '已完成', expectedVersion: Number(input.dataset.taskVersion) })) }) }).then((result) => { toast(`已更新 ${result.updated || selected.length} 条记录`); closeDetail(); loadAll(); }).catch((error) => toast(error.message, true));
      return;
    }
    const row = event.target.closest('[data-task-id],[data-student-id]');
    if (!row || event.target.closest('button,a')) return;
    openDetail(row.dataset.taskId ? 'task' : 'student', row.dataset.taskId || row.dataset.studentId);
  });
  document.addEventListener('keydown', (event) => {
    if (!['Enter', ' '].includes(event.key) || !document.activeElement?.matches('[data-task-id],[data-student-id]')) return;
    event.preventDefault();
    const row = document.activeElement;
    openDetail(row.dataset.taskId ? 'task' : 'student', row.dataset.taskId || row.dataset.studentId);
  });

  const setupModal = (modal) => {
    const title = modal.querySelector('h2');
    if (title) { title.id ||= `${modal.id}-title`; modal.setAttribute('aria-labelledby', title.id); }
    modal.setAttribute('role', 'dialog');
    modal.setAttribute('aria-modal', 'true');
  };
  document.querySelectorAll('.modal-backdrop').forEach(setupModal);
  const modalObserver = new MutationObserver(() => {
    const open = [...document.querySelectorAll('.modal-backdrop')].some((modal) => !modal.classList.contains('hidden'));
    document.body.classList.toggle('modal-open', open);
  });
  modalObserver.observe(document.body, { subtree: true, attributes: true, attributeFilter: ['class'] });
  document.addEventListener('keydown', (event) => { if (event.key === 'Escape') document.querySelector('.modal-backdrop:not(.hidden) .modal-close')?.click(); });

  const bell = document.querySelector('[title="消息提醒"]');
  bell?.setAttribute('aria-label', '消息提醒');
  bell?.addEventListener('click', () => {
    let popover = document.getElementById('messagePopover');
    if (popover) { popover.remove(); return; }
    popover = document.createElement('div');
    popover.id = 'messagePopover';
    popover.className = 'message-popover';
    const messages = state.dashboard?.messages || [];
    popover.innerHTML = `<div class="message-popover-head"><strong>消息提醒</strong><button class="modal-close" aria-label="关闭消息提醒">×</button></div>${messages.length ? messages.slice(0, 6).map((message) => `<button class="message-item ${message.isRead ? '' : 'unread'}" data-message-id="${escapeHtml(message.id)}"><strong>${escapeHtml(message.title)}</strong><span>${escapeHtml(message.content)}</span><small>${escapeHtml(message.time || '')}</small></button>`).join('') : '<div class="empty-chart">暂无新消息</div>'}`;
    document.body.append(popover);
    popover.querySelector('.modal-close').addEventListener('click', () => popover.remove());
    popover.querySelectorAll('[data-message-id]').forEach((item) => item.addEventListener('click', async () => {
      try { await api(`/v1/messages/${encodeURIComponent(item.dataset.messageId)}/read`, { method: 'POST' }); item.classList.remove('unread'); } catch (error) { toast(error.message, true); }
    }));
  });

  const setupSchoolOptions = async () => {
    const input = document.getElementById('schoolId');
    if (!input || document.getElementById('school-options')) return;
    try {
      const data = await api('/v1/admin/schools?paged=1&page=1&pageSize=100');
      const schools = data?.items || data || [];
      const list = document.createElement('datalist');
      list.id = 'school-options';
      list.innerHTML = schools.map((school) => `<option value="${escapeHtml(school.id)}">${escapeHtml(school.name)}</option>`).join('');
      document.body.append(list);
      input.setAttribute('list', list.id);
      input.title = schools.map((school) => `${school.id} · ${school.name}`).join('\n');
    } catch { /* non-admin users do not have access to the school directory */ }
  };

  const downloadCsv = (filename, rows) => {
    if (!rows.length) { toast('当前没有可导出的数据', true); return; }
    const keys = Object.keys(rows[0]);
    const quote = (value) => `"${String(value ?? '').replaceAll('"', '""')}"`;
    const csv = `\ufeff${keys.map(quote).join(',')}\n${rows.map((row) => keys.map((key) => quote(row[key])).join(',')).join('\n')}`;
    const link = document.createElement('a');
    link.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
    link.download = filename;
    link.click();
    URL.revokeObjectURL(link.href);
  };
  const addExportButton = (selector, id, label, rows) => {
    const host = document.querySelector(selector);
    if (!host || document.getElementById(id)) return;
    const button = document.createElement('button');
    button.id = id;
    button.className = 'ghost-btn';
    button.textContent = label;
    button.addEventListener('click', () => downloadCsv(`${id}-${new Date().toISOString().slice(0, 10)}.csv`, rows()));
    host.append(button);
  };
  const addBusinessExports = () => {
    addExportButton('#tasksSection .section-tools', 'exportTasksBtn', '导出任务', () => (state.dashboard?.tasks || []).map((item) => ({ 任务: item.title, 范围: `${item.gradeName || '全校'} / ${item.className || '全校'}`, 状态: item.status, 完成: `${item.completedCount || 0}/${item.totalCount || 0}`, 日期: item.date })));
    addExportButton('#studentsSection .section-tools', 'exportStudentsBtn', '导出学生', () => (state.dashboard?.students || []).map((item) => ({ 姓名: item.name, 年级: item.grade, 班级: item.className, 测评状态: item.taskStatus, 综合得分: item.totalScore ?? '', 地区: item.region || '' })));
    addExportButton('.report-panel .panel-head', 'exportReportsBtn', '导出报告', () => (state.reports || []).map((item) => ({ 学生: item.studentName, 班级: item.className, 风险: item.riskLevel, 得分: item.totalScore ?? '', 状态: item.status, 生成时间: item.generatedAt })));
    addExportButton('#accountsSection .panel-head', 'exportAccountsBtn', '导出账户', () => (state.accounts?.items || []).map((item) => ({ 姓名: item.name, 手机号: item.phoneMasked, 角色: (item.roles || []).map((role) => role.name).join('、'), 学校: item.schoolNames, 状态: item.status })));
  };
  addBusinessExports();
  const businessObserver = new MutationObserver(() => {
    addBusinessExports();
    document.querySelectorAll('#reportTable tr').forEach((row) => {
      const action = row.querySelector('[data-report-id]');
      if (!action || row.querySelector('[data-report-view]')) return;
      const report = (state.reports || []).find((item) => item.id === action.dataset.reportId);
      if (!report) return;
      const view = document.createElement('button');
      view.className = 'report-action'; view.dataset.reportView = report.studentId; view.textContent = '查看';
      action.parentElement.append(view);
    });
    document.querySelectorAll('#accountTable tr').forEach((row) => {
      const action = row.querySelector('[data-account-id]');
      if (!action || row.querySelector('[data-account-edit]')) return;
      const edit = document.createElement('button'); edit.className = 'report-action'; edit.dataset.accountEdit = action.dataset.accountId; edit.textContent = '编辑';
      const reset = document.createElement('button'); reset.className = 'report-action withdraw'; reset.dataset.accountReset = action.dataset.accountId; reset.textContent = '重置密码';
      const resetMfa = document.createElement('button'); resetMfa.className = 'report-action withdraw'; resetMfa.dataset.accountMfaReset = action.dataset.accountId; resetMfa.textContent = '恢复双重验证';
      action.parentElement.append(edit, reset, resetMfa);
    });
  });
  businessObserver.observe(document.body, { subtree: true, childList: true });

  document.addEventListener('click', (event) => {
    const reportView = event.target.closest('[data-report-view]');
    if (reportView) openDetail('student', reportView.dataset.reportView);
    const accountEdit = event.target.closest('[data-account-edit]');
    if (accountEdit) {
      const item = (state.accounts?.items || []).find((account) => account.id === accountEdit.dataset.accountEdit);
      if (!item) return;
      const name = window.prompt('账户姓名', item.name || '');
      if (!name) return;
      const role = window.prompt('角色：admin / principal / teacher / parent', item.roles?.[0]?.code || 'teacher');
      if (!role) return;
      api(`/v1/admin/accounts/${encodeURIComponent(item.id)}`, { method: 'PATCH', body: JSON.stringify({ name, role, replaceScopes: true, schoolId: item.roles?.[0]?.schoolId || state.schoolId, classId: item.roles?.[0]?.classId || null }) }).then(() => { toast('账户已更新'); loadAll(); }).catch((error) => toast(error.message, true));
    }
    const accountReset = event.target.closest('[data-account-reset]');
    if (accountReset && window.confirm('确定生成一次性密码设置令牌并撤销其全部会话吗？令牌只显示一次。')) api(`/v1/admin/accounts/${encodeURIComponent(accountReset.dataset.accountReset)}/reset-password`, { method: 'POST', body: '{}' }).then((result) => { navigator.clipboard?.writeText(result.setupToken); toast(`设置令牌已复制（30分钟有效）：${result.setupToken}`); }).catch((error) => toast(error.message, true));
    const accountMfaReset = event.target.closest('[data-account-mfa-reset]');
    if (accountMfaReset) {
      const reason = window.prompt('请填写双重验证恢复原因（至少 8 个字符，将写入审计日志）', '');
      if (reason == null) return;
      if (!window.confirm('这将删除该账户的双重验证配置、撤销其全部会话；若该账户属于管理员或校长，下次登录必须重新注册。确认继续？')) return;
      api(`/v1/admin/accounts/${encodeURIComponent(accountMfaReset.dataset.accountMfaReset)}/reset-mfa`, { method: 'POST', headers: { 'Idempotency-Key': `account-mfa-reset-${Date.now()}` }, body: JSON.stringify({ reason }) }).then((result) => { toast(result.mfaReset ? '双重验证已恢复，原会话已全部撤销' : '该账户未启用双重验证，已清理待完成注册'); loadAll(); }).catch((error) => toast(error.message, true));
    }
  });

  const originalRenderOverview = renderOverview;
  renderOverview = () => {
    originalRenderOverview();
    const activeTask = (state.dashboard?.tasks || []).filter((task) => task.status !== 'draft')[0];
    const activeTotal = Number(activeTask?.totalCount || 0);
    const activeCompleted = Number(activeTask?.completedCount || 0);
    const activeRate = activeTotal ? Math.round(activeCompleted / activeTotal * 100) : 0;
    const completion = document.getElementById('heroCompletion');
    if (completion) completion.textContent = `${activeRate}%`;
    const description = document.getElementById('schoolDescription');
    if (description && activeTask) description.textContent += ` 当前指标按「${activeTask.title}」任务批次统计。`;
  };

  const operationsPanel = document.createElement('section');
  const designStyle = document.createElement('style');
  designStyle.textContent = ':root{--blue:#347cf1;--blue-2:#4b8df5;--teal:#21c46b;--ink:#172b4d;--canvas:#f7faff;--green:#21c46b}.operations-panel{margin-bottom:18px}.operations-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;padding:4px 19px 20px}.operation-card{display:grid;gap:4px;padding:14px;border:1px solid var(--line);border-radius:12px;background:linear-gradient(180deg,#fff,#f8fbff)}.operation-card strong{font-size:24px;line-height:1;color:var(--ink);letter-spacing:-.04em}.operation-card span{font-size:11px;color:var(--ink);font-weight:750}.operation-card small{font-size:10px;color:var(--muted);line-height:1.45}@media(max-width:1180px){.operations-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:520px){.operations-grid{grid-template-columns:1fr 1fr;padding-left:12px;padding-right:12px}.operation-card{padding:11px}.operation-card strong{font-size:20px}}';
  document.head.append(designStyle);
  operationsPanel.id = 'operationsSection';
  operationsPanel.className = 'panel operations-panel';
  operationsPanel.innerHTML = '<div class="panel-head"><div><h3>运营中心</h3><p>汇总 App 回写、复核和数据治理待处理事项</p></div><button class="panel-action" id="refreshOperationsBtn">刷新</button></div><div class="operations-grid" id="operationsGrid"><div class="loading-skeleton">正在读取运营队列...</div></div>';
  const settingsSection = document.getElementById('settingsSection');
  settingsSection?.parentElement?.insertBefore(operationsPanel, settingsSection);
  const operationLabels = { pendingReviews: ['待复核成绩', '需要教师或管理员核验'], pendingActivities: ['活动报名', '等待运营确认'], pendingAppointments: ['专家预约', '等待安排时间'], pendingCourseUploads: ['课程上传', '等待教师材料处理'], pendingSupportMessages: ['客服咨询', '等待服务人员回复'], pendingPrivacyRequests: ['隐私申请', '需要数据治理处理'], bodyAssessmentsLast30Days: ['家庭测评', '近 30 天已回写记录'], auditEventsLast24Hours: ['审计事件', '近 24 小时操作记录'] };
  const renderOperations = (data) => {
    const grid = document.getElementById('operationsGrid');
    if (!grid) return;
    grid.innerHTML = Object.entries(operationLabels).map(([key, [label, hint]]) => `<article class="operation-card"><strong>${Number(data?.[key] || 0)}</strong><span>${label}</span><small>${hint}</small></article>`).join('');
  };
  const loadOperations = async () => {
    if (!state.dashboard || !operationsPanel) return;
    try { renderOperations(await api(`/v1/admin/operations/summary?schoolId=${encodeURIComponent(state.schoolId)}`)); operationsPanel.classList.remove('hidden'); }
    catch (error) { if (error.message.includes('权限') || error.message.includes('管理员')) operationsPanel.classList.add('hidden'); else document.getElementById('operationsGrid').innerHTML = `<div class="empty-chart">运营队列暂时不可用：${escapeHtml(error.message)}</div>`; }
  };
  document.getElementById('refreshOperationsBtn')?.addEventListener('click', loadOperations);
  document.getElementById('schoolId')?.addEventListener('change', () => setTimeout(loadOperations, 200));
  document.getElementById('refreshBtn')?.addEventListener('click', () => setTimeout(loadOperations, 200));
  document.getElementById('refreshTextBtn')?.addEventListener('click', () => setTimeout(loadOperations, 200));

  const bootstrapAuth = async () => {
    try {
      const response = await fetch('/v1/auth/refresh', { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json' } });
      if (!response.ok) return;
      const payload = await response.json();
      state.token = payload.data.accessToken;
      applyProfile(payload.data.user);
      showApp();
      await loadAll();
      await setupSchoolOptions();
    } catch { /* login screen remains available */ }
  };
  bootstrapAuth();
  const directoryTimer = setInterval(() => { if (state.dashboard) { setupSchoolOptions(); clearInterval(directoryTimer); } }, 500);
  const operationsTimer = setInterval(() => { if (state.dashboard) { loadOperations(); clearInterval(operationsTimer); } }, 500);
})();

(function addAssessmentStandardConsole() {
  const style = document.createElement('style');
  style.textContent = `
    .standard-modal{width:min(980px,100%);max-width:980px!important}.standard-toolbar{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:14px}.standard-summary{display:flex;gap:8px;flex-wrap:wrap}.standard-kpi{padding:8px 10px;border:1px solid var(--line);border-radius:9px;background:#f8fbff;color:var(--muted);font-size:10px}.standard-kpi b{margin-right:4px;color:var(--ink);font-size:14px}.standard-filter{height:34px;min-width:118px;padding:0 9px;border:1px solid var(--line);border-radius:8px;background:#fff;color:var(--ink);font-size:11px}.standard-table{min-height:170px;border:1px solid var(--line);border-radius:12px;overflow:auto}.standard-table table{width:100%;min-width:760px;border-collapse:collapse}.standard-table th,.standard-table td{padding:11px 12px;border-bottom:1px solid #eef2f7;text-align:left;vertical-align:top;font-size:11px}.standard-table th{background:#f8fbff;color:#8795a8;font-size:10px;letter-spacing:.04em}.standard-table td small{display:block;margin-top:4px;color:var(--muted);font-size:10px;line-height:1.45}.standard-scope{display:inline-flex;align-items:center;flex-wrap:wrap;gap:4px}.standard-json{width:100%;min-height:92px;resize:vertical;padding:9px;border:1px solid var(--line);border-radius:8px;background:#fbfdff;color:#31415a;font:11px/1.55 ui-monospace,SFMono-Regular,Menlo,monospace}.standard-json:focus{border-color:var(--blue);outline:0}.standard-create{margin-top:16px;padding-top:16px;border-top:1px solid var(--line)}.standard-create h3{margin:0 0 5px;font-size:14px}.standard-create p{margin:0 0 13px;color:var(--muted);font-size:11px;line-height:1.55}.standard-empty{padding:32px 18px;text-align:center;color:var(--muted);font-size:11px}.standard-state{display:inline-flex;align-items:center;padding:5px 8px;border-radius:7px;font-size:10px;font-weight:750}.standard-state.active{color:#13966f;background:#e9faf4}.standard-state.draft{color:#2c6ebf;background:#eaf4ff}.standard-state.archived{color:#748399;background:#eef2f7}.standard-action{height:28px;padding:0 9px;border-radius:7px;color:var(--blue);background:#eaf4ff;font-size:10px;font-weight:750}.standard-action.archive{color:#a36a00;background:#fff5db}@media(max-width:680px){.standard-modal{max-width:100%!important}.standard-toolbar{align-items:flex-start;flex-direction:column}.standard-toolbar select{width:100%}}
  `;
  document.head.append(style);

  const button = document.createElement('button');
  button.id = 'assessmentStandardsBtn';
  button.className = 'secondary-btn';
  button.type = 'button';
  button.textContent = '标准版本';
  document.querySelector('.heading-actions')?.append(button);

  const modal = document.createElement('div');
  modal.id = 'assessmentStandardsModal';
  modal.className = 'modal-backdrop hidden';
  modal.innerHTML = `
    <div class="modal hard-modal standard-modal">
      <div class="modal-head"><div><h2>测评标准版本管理</h2><p>按学校、年级、地区及困难地区条件配置。正式测试会在开始时锁定快照，后续调整不会影响历史成绩。</p></div><button class="modal-close" type="button" aria-label="关闭">×</button></div>
      <div class="hard-modal-body">
        <div class="standard-toolbar"><div class="standard-summary" id="standardSummary"><span class="standard-kpi">正在读取版本信息…</span></div><div><select id="standardStatusFilter" class="standard-filter" aria-label="标准状态"><option value="">全部状态</option><option value="active">生效中</option><option value="draft">草稿</option><option value="archived">已归档</option></select><button id="standardRefreshBtn" class="ghost-btn" type="button">刷新</button></div></div>
        <div class="standard-table"><table><thead><tr><th>标准版本</th><th>适用范围</th><th>生效日期</th><th>规则摘要</th><th>状态</th><th>操作</th></tr></thead><tbody id="standardTable"><tr><td colspan="6"><div class="standard-empty">正在读取标准版本…</div></td></tr></tbody></table></div>
        <section class="standard-create"><h3>创建不可变标准版本</h3><p>创建后只允许变更状态。请以新版本替代旧版本，确保测评规则、报告模板和课程建议具备完整审计链路。</p><div class="hard-form-grid">
          <div class="field"><label for="standardVersionInput">版本名称</label><input id="standardVersionInput" maxlength="120" placeholder="例如：2027 春季三年级运动能力 v2" required></div>
          <div class="field"><label for="standardEffectiveDate">生效日期</label><input id="standardEffectiveDate" type="date" required></div>
          <div class="field"><label for="standardGradeInput">适用年级</label><select id="standardGradeInput"><option value="">全校通用</option></select></div>
          <div class="field"><label for="standardRegionInput">地区条件</label><input id="standardRegionInput" maxlength="80" placeholder="留空表示不限制地区"></div>
          <div class="field"><label for="standardPovertyInput">困难地区条件</label><select id="standardPovertyInput"><option value="">不限制</option><option value="true">仅困难地区</option><option value="false">仅非困难地区</option></select></div>
          <div class="field"><label for="standardCreateStatus">初始状态</label><select id="standardCreateStatus"><option value="draft">保存为草稿</option><option value="active">立即生效</option></select></div>
          <div class="field full"><label for="standardRuleConfig">评分规则 JSON</label><textarea id="standardRuleConfig" class="standard-json">{"itemCount":7,"scoreRange":{"min":0,"max":5},"lowConfidenceRequiresReview":true}</textarea></div>
          <div class="field"><label for="standardReportConfig">报告配置 JSON（可选）</label><textarea id="standardReportConfig" class="standard-json">{}</textarea></div>
          <div class="field"><label for="standardCourseConfig">课程建议 JSON（可选）</label><textarea id="standardCourseConfig" class="standard-json">{}</textarea></div>
        </div><div class="modal-footer"><button id="createAssessmentStandard" type="button" class="primary-btn">创建标准版本</button></div>
        </section>
      </div>
    </div>`;
  document.body.append(modal);
  modal.querySelector('.modal-close')?.addEventListener('click', () => modal.classList.add('hidden'));
  modal.addEventListener('click', (event) => { if (event.target === modal) modal.classList.add('hidden'); });

  let standards = [];
  const parseConfig = (id, label) => {
    const raw = document.getElementById(id)?.value?.trim() || '{}';
    try {
      const parsed = JSON.parse(raw);
      if (!parsed || Array.isArray(parsed) || typeof parsed !== 'object') throw new Error();
      return parsed;
    } catch { throw new Error(`${label}必须是有效的 JSON 对象`); }
  };
  const statusLabel = { active: '生效中', draft: '草稿', archived: '已归档' };
  const scopeText = (item) => {
    const grade = document.querySelector(`#standardGradeInput option[value="${CSS.escape(item.gradeId || '')}"]`)?.textContent || (item.gradeId ? '指定年级' : '全校通用');
    const parts = [grade];
    if (item.region) parts.push(item.region);
    if (item.povertyArea === true) parts.push('困难地区');
    if (item.povertyArea === false) parts.push('非困难地区');
    return parts;
  };
  const renderStandards = () => {
    const table = document.getElementById('standardTable');
    const summary = document.getElementById('standardSummary');
    if (!table || !summary) return;
    const active = standards.filter((item) => item.status === 'active').length;
    const draft = standards.filter((item) => item.status === 'draft').length;
    const archived = standards.filter((item) => item.status === 'archived').length;
    summary.innerHTML = `<span class="standard-kpi"><b>${active}</b>生效中</span><span class="standard-kpi"><b>${draft}</b>草稿</span><span class="standard-kpi"><b>${archived}</b>已归档</span>`;
    table.innerHTML = standards.length ? standards.map((item) => {
      const rules = item.ruleConfig || {};
      const scoreRange = rules.scoreRange ? `${rules.scoreRange.min ?? 0}–${rules.scoreRange.max ?? 5} 分` : '默认计分范围';
      const action = item.status === 'archived' ? '' : `<button class="standard-action ${item.status === 'active' ? 'archive' : ''}" type="button" data-standard-id="${escapeHtml(item.id)}" data-standard-status="${item.status === 'active' ? 'archived' : 'active'}">${item.status === 'active' ? '归档' : '设为生效'}</button>`;
      return `<tr><td><strong>${escapeHtml(item.standardVersion)}</strong><small>${escapeHtml(item.id)}</small></td><td><span class="standard-scope">${scopeText(item).map((part) => `<span class="status gray">${escapeHtml(part)}</span>`).join('')}</span></td><td>${escapeHtml(dateText(item.effectiveDate))}</td><td>${Number.isFinite(Number(rules.itemCount)) ? `${Number(rules.itemCount)} 项` : '默认项目数'} · ${escapeHtml(scoreRange)}<small>${rules.lowConfidenceRequiresReview === false ? '低置信度无需自动复核' : '低置信度自动进入复核'}</small></td><td><span class="standard-state ${escapeHtml(item.status)}">${statusLabel[item.status] || escapeHtml(item.status)}</span></td><td>${action}</td></tr>`;
    }).join('') : '<tr><td colspan="6"><div class="standard-empty">当前筛选下尚无标准。未配置时系统会使用任务默认版本；建议在首次正式体测前建立并生效标准。</div></td></tr>';
  };
  const loadGrades = async () => {
    const select = document.getElementById('standardGradeInput');
    if (!select) return;
    try {
      const grades = await api(`/v1/admin/grades?schoolId=${encodeURIComponent(state.schoolId)}`);
      const previous = select.value;
      select.innerHTML = `<option value="">全校通用</option>${(grades || []).map((grade) => `<option value="${escapeHtml(grade.id)}">${escapeHtml(grade.name)}${grade.academicYear ? ` · ${escapeHtml(grade.academicYear)}` : ''}</option>`).join('')}`;
      select.value = previous;
    } catch { select.innerHTML = '<option value="">全校通用</option>'; }
  };
  const loadStandards = async () => {
    const table = document.getElementById('standardTable');
    if (table) table.innerHTML = '<tr><td colspan="6"><div class="standard-empty">正在同步标准版本…</div></td></tr>';
    try {
      const status = document.getElementById('standardStatusFilter')?.value || '';
      const result = await api(`/v1/admin/assessment-standards?schoolId=${encodeURIComponent(state.schoolId)}${status ? `&status=${encodeURIComponent(status)}` : ''}`);
      standards = result || [];
      renderStandards();
    } catch (error) {
      if (table) table.innerHTML = `<tr><td colspan="6"><div class="standard-empty">无法读取标准版本：${escapeHtml(error.message)}</div></td></tr>`;
    }
  };
  const open = async () => {
    modal.classList.remove('hidden');
    document.getElementById('standardEffectiveDate').value = new Date().toISOString().slice(0, 10);
    await Promise.all([loadGrades(), loadStandards()]);
  };
  button.addEventListener('click', open);
  document.getElementById('standardRefreshBtn')?.addEventListener('click', loadStandards);
  document.getElementById('standardStatusFilter')?.addEventListener('change', loadStandards);
  document.getElementById('createAssessmentStandard')?.addEventListener('click', async () => {
    try {
      const version = document.getElementById('standardVersionInput').value.trim();
      const effectiveDate = document.getElementById('standardEffectiveDate').value;
      if (!version || !effectiveDate) throw new Error('请填写标准版本和生效日期');
      const poverty = document.getElementById('standardPovertyInput').value;
      await api('/v1/admin/assessment-standards', {
        method: 'POST', headers: { 'Idempotency-Key': `assessment-standard-${Date.now()}-${Math.random().toString(16).slice(2)}` },
        body: JSON.stringify({ schoolId: state.schoolId, gradeId: document.getElementById('standardGradeInput').value || null, region: document.getElementById('standardRegionInput').value.trim(), povertyArea: poverty === '' ? null : poverty === 'true', standardVersion: version, effectiveDate, status: document.getElementById('standardCreateStatus').value, ruleConfig: parseConfig('standardRuleConfig', '评分规则'), reportConfig: parseConfig('standardReportConfig', '报告配置'), courseConfig: parseConfig('standardCourseConfig', '课程建议') })
      });
      document.getElementById('standardVersionInput').value = '';
      document.getElementById('standardRegionInput').value = '';
      document.getElementById('standardPovertyInput').value = '';
      toast('标准版本已创建；新启动的场地会话将自动解析并锁定该版本');
      await loadStandards();
    } catch (error) { toast(error.message, true); }
  });
  document.addEventListener('click', async (event) => {
    const action = event.target.closest('[data-standard-id]');
    if (!action) return;
    const status = action.dataset.standardStatus;
    if (!window.confirm(status === 'archived' ? '归档后新会话不再使用该版本，历史快照不会受影响。确认归档？' : '确认将该草稿标准设为生效？')) return;
    try {
      await api(`/v1/admin/assessment-standards/${encodeURIComponent(action.dataset.standardId)}/status`, { method: 'PATCH', headers: { 'Idempotency-Key': `assessment-standard-status-${Date.now()}` }, body: JSON.stringify({ status }) });
      toast(status === 'archived' ? '标准已归档' : '标准已设为生效');
      await loadStandards();
    } catch (error) { toast(error.message, true); }
  });
  document.getElementById('schoolId')?.addEventListener('change', () => { if (!modal.classList.contains('hidden')) void Promise.all([loadGrades(), loadStandards()]); });
})();

(function addHardOperations() {
  const hardStyle = document.createElement('style');
  hardStyle.textContent = '.hard-modal{max-width:760px}.hard-modal-body{padding:0 22px 22px}.hard-form-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.hard-form-grid .full{grid-column:1/-1}.hard-form-grid textarea{width:100%;resize:vertical;border:1px solid var(--line);border-radius:8px;padding:10px}.import-preview{margin-top:14px;padding:12px;border:1px dashed var(--line);border-radius:10px;background:#f8fbff;min-height:70px}.import-summary{display:flex;gap:10px;align-items:center;flex-wrap:wrap}.import-errors{margin-top:10px;color:#b42318;display:grid;gap:5px;font-size:12px}.period-row,.queue-item{display:flex;align-items:center;gap:10px;padding:11px 0;border-bottom:1px solid var(--line)}.period-row strong,.queue-item strong{flex:1}.period-row span,.queue-item small{color:var(--muted);font-size:11px}.operation-queue-list{max-height:460px;overflow:auto}.queue-item small{display:block;margin-top:4px}.queue-filter{margin-bottom:12px}.queue-filter select{min-width:180px}.detail-actions{display:flex;gap:8px;flex-wrap:wrap;margin:14px 0}.detail-actions .secondary-btn{font-size:12px}@media(max-width:680px){.hard-form-grid{grid-template-columns:1fr}.hard-form-grid .full{grid-column:auto}.hard-modal-body{padding:0 14px 14px}}';
  document.head.append(hardStyle);
  const makeModal = (id, title, subtitle, body) => {
    let node = document.getElementById(id);
    if (node) return node;
    node = document.createElement('div');
    node.id = id;
    node.className = 'modal-backdrop hidden';
    node.innerHTML = `<div class="modal hard-modal"><div class="modal-head"><div><h2>${escapeHtml(title)}</h2><p>${escapeHtml(subtitle)}</p></div><button class="modal-close" aria-label="关闭">×</button></div><div class="hard-modal-body">${body}</div></div>`;
    document.body.append(node);
    node.querySelector('.modal-close').addEventListener('click', () => node.classList.add('hidden'));
    node.addEventListener('click', (event) => { if (event.target === node) node.classList.add('hidden'); });
    return node;
  };

  const importButton = document.createElement('button');
  importButton.id = 'studentImportBtn';
  importButton.className = 'secondary-btn';
  importButton.textContent = '批量导入';
  document.querySelector('#studentsSection .section-tools')?.prepend(importButton);
  const importModal = makeModal('studentImportModal', '批量导入学生', '支持多学校、多年级、多班级 CSV / Excel；先预览校验，再正式写入。', '<div class="hard-form-grid"><div class="field full"><label for="studentImportFile">CSV / Excel 文件</label><input id="studentImportFile" type="file" accept=".csv,.xlsx,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"><span class="hint">字段：schoolId、gradeId、classId、studentNo、name、gender、birthDate、region、isPovertyArea。多学校导入时每行填写 schoolId，单文件不超过 8MB。</span></div><div class="field"><label for="studentImportPolicy">重复学生处理</label><select id="studentImportPolicy"><option value="skip">跳过重复</option><option value="update">更新已有档案</option></select></div><div class="field"><label>模板</label><button id="downloadStudentTemplate" type="button" class="ghost-btn">下载导入模板</button></div></div><div class="import-preview" id="studentImportPreview">请选择 CSV 或 Excel 文件后预览。</div><div class="modal-footer"><button id="previewStudentImport" type="button" class="secondary-btn">校验并预览</button><button id="commitStudentImport" type="button" class="primary-btn" disabled>确认导入</button></div>');
  let importPayload = null;
  const readImportFile = () => new Promise((resolve, reject) => {
    const file = document.getElementById('studentImportFile')?.files?.[0];
    if (!file) return reject(new Error('请先选择 CSV 或 Excel 文件'));
    if (file.size > 8 * 1024 * 1024) return reject(new Error('导入文件不能超过 8MB'));
    const reader = new FileReader();
    reader.onload = () => {
      if (/\.xlsx$/i.test(file.name)) {
        const bytes = new Uint8Array(reader.result);
        let binary = '';
        const chunkSize = 0x8000;
        for (let index = 0; index < bytes.length; index += chunkSize) binary += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
        resolve({ fileBase64: btoa(binary), filename: file.name });
      } else resolve({ csvText: new TextDecoder('utf-8').decode(reader.result), filename: file.name });
    };
    reader.onerror = () => reject(new Error('文件读取失败'));
    reader.readAsArrayBuffer(file);
  });
  const renderImportPreview = (data) => {
    const box = document.getElementById('studentImportPreview');
    if (!box) return;
    const errors = data.errors || [];
    box.innerHTML = `<div class="import-summary"><strong>共 ${Number(data.totalRows || 0)} 行</strong><span class="status done">可导入 ${Number(data.validRows || 0)}</span><span class="status ${errors.length ? 'review' : 'done'}">错误 ${errors.length}</span></div>${errors.length ? `<div class="import-errors">${errors.slice(0, 20).map((item) => `<div>第 ${item.line} 行：${escapeHtml(item.name || '')} · ${escapeHtml(item.errors.join('、'))}</div>`).join('')}</div>` : '<div class="empty-chart">校验通过，可以确认导入。</div>'}`;
  };
  importButton.addEventListener('click', () => { importModal.classList.remove('hidden'); importPayload = null; document.getElementById('commitStudentImport').disabled = true; document.getElementById('studentImportPreview').textContent = '请选择 CSV 或 Excel 文件后预览。'; });
  document.getElementById('downloadStudentTemplate')?.addEventListener('click', () => {
    const csv = '\ufeffschoolId,gradeId,classId,studentNo,name,gender,birthDate,region,isPovertyArea\nschool-1,grade-3,class-3,XS-S03,王小新,男,2017-10-01,本地,false\n';
    const link = document.createElement('a'); link.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' })); link.download = '学生导入模板.csv'; link.click(); URL.revokeObjectURL(link.href);
  });
  document.getElementById('previewStudentImport')?.addEventListener('click', async () => {
    try {
      const file = await readImportFile();
      const duplicatePolicy = document.getElementById('studentImportPolicy')?.value || 'skip';
      importPayload = { ...file, duplicatePolicy };
      const result = await api('/v1/admin/students/import/preview', { method: 'POST', headers: { 'Idempotency-Key': `student-import-preview-${Date.now()}` }, body: JSON.stringify(importPayload) });
      renderImportPreview(result);
      document.getElementById('commitStudentImport').disabled = Number(result.errorRows || 0) > 0 || !Number(result.validRows || 0);
    } catch (error) { document.getElementById('studentImportPreview').textContent = error.message; document.getElementById('commitStudentImport').disabled = true; }
  });
  document.getElementById('commitStudentImport')?.addEventListener('click', async () => {
    if (!importPayload) return;
    try {
      const result = await api('/v1/admin/students/import', { method: 'POST', headers: { 'Idempotency-Key': `student-import-${Date.now()}` }, body: JSON.stringify(importPayload) });
      toast(`已导入 ${result.importedCount || 0} 名学生，跳过 ${result.skippedCount || 0} 名重复学生`);
      importModal.classList.add('hidden'); await loadAll();
    } catch (error) { document.getElementById('studentImportPreview').textContent = error.message; }
  });

  const orgButton = document.createElement('button');
  orgButton.id = 'organizationBtn'; orgButton.className = 'secondary-btn'; orgButton.textContent = '组织管理';
  document.querySelector('.heading-actions')?.append(orgButton);
  const orgModal = makeModal('organizationModal', '组织与学年管理', '先建立学年学期，再创建年级和班级；导入学生时使用这些范围。', '<div class="hard-form-grid"><div class="field"><label for="periodYear">学年</label><input id="periodYear" placeholder="2026-2027"></div><div class="field"><label for="periodTerm">学期</label><select id="periodTerm"><option>全年</option><option>秋季</option><option>春季</option></select></div><div class="field"><label for="periodStarts">开始日期</label><input id="periodStarts" type="date"></div><div class="field"><label for="periodEnds">结束日期</label><input id="periodEnds" type="date"></div><div class="field full"><button id="createPeriodBtn" type="button" class="primary-btn">创建学年学期</button></div></div><div id="periodList" class="import-preview">正在读取学年学期...</div><div class="hard-form-grid"><div class="field"><label for="newGradeName">新年级名称</label><input id="newGradeName" placeholder="例如：四年级"></div><div class="field"><label for="newGradeYear">学年</label><input id="newGradeYear" placeholder="2026-2027"></div><div class="field full"><button id="createGradeBtn" type="button" class="secondary-btn">创建年级</button></div><div class="field"><label for="newClassGrade">所属年级 ID</label><input id="newClassGrade" placeholder="grade-xxx"></div><div class="field"><label for="newClassName">新班级名称</label><input id="newClassName" placeholder="例如：四年级1班"></div><div class="field full"><button id="createClassBtn" type="button" class="secondary-btn">创建班级</button></div></div>');
  const schoolBlock = document.createElement('div');
  schoolBlock.className = 'hard-form-grid';
  schoolBlock.innerHTML = '<div class="field full"><h3>学校目录</h3><span class="hint">平台管理员可创建学校、维护基础信息并停用已退出平台的学校。</span></div><div class="field"><label for="newSchoolName">学校名称</label><input id="newSchoolName" placeholder="例如：向上实验小学"></div><div class="field"><label for="newSchoolCampus">校区</label><input id="newSchoolCampus" placeholder="主校区"></div><div class="field"><label for="newSchoolRegion">地区</label><input id="newSchoolRegion" placeholder="北京市海淀区"></div><div class="field"><label><input id="newSchoolPoverty" type="checkbox"> 重点帮扶地区</label></div><div class="field full"><button id="createSchoolBtn" type="button" class="secondary-btn">创建学校</button></div><div class="field full"><div id="schoolList" class="import-preview">正在读取学校目录...</div></div>';
  orgModal.querySelector('.hard-modal-body')?.prepend(schoolBlock);
  const promoteBlock = document.createElement('div');
  promoteBlock.className = 'hard-form-grid';
  promoteBlock.innerHTML = '<div class="field full"><h3>批量升班</h3><span class="hint">选择来源班级和目标班级，系统会记录每名学生的升班历史。</span></div><div class="field"><label for="promoteFromClass">来源班级</label><select id="promoteFromClass"></select></div><div class="field"><label for="promoteToClass">目标班级</label><select id="promoteToClass"></select></div><div class="field full"><button id="promoteClassBtn" type="button" class="secondary-btn">执行批量升班</button></div>';
  orgModal.querySelector('.hard-modal-body')?.append(promoteBlock);
  const refreshPromoteOptions = () => { const classes = state.dashboard?.classes || []; ['promoteFromClass', 'promoteToClass'].forEach((id) => { const select = document.getElementById(id); if (select) select.innerHTML = classes.map((item) => `<option value="${escapeHtml(item.id)}" data-grade-id="${escapeHtml(item.gradeId)}">${escapeHtml(item.name)} · ${escapeHtml(item.teacherName || '未分配')}</option>`).join(''); }); };
  refreshPromoteOptions();
  document.getElementById('promoteClassBtn')?.addEventListener('click', async () => { const fromClassId = document.getElementById('promoteFromClass')?.value; const target = document.getElementById('promoteToClass')?.selectedOptions?.[0]; if (!fromClassId || !target || fromClassId === target.value) { toast('请选择不同的来源班级和目标班级', true); return; } try { const result = await api('/v1/admin/students/batch-promote', { method: 'POST', headers: { 'Idempotency-Key': `promote-${Date.now()}` }, body: JSON.stringify({ sourceClassId: fromClassId, toGradeId: target.dataset.gradeId, toClassId: target.value }) }); toast(`已完成 ${result.updatedCount || 0} 名学生升班`); loadAll(); } catch (error) { toast(error.message, true); } });
  const loadSchools = async () => { const list = document.getElementById('schoolList'); if (!list) return; try { const result = await api('/v1/admin/schools?paged=1&page=1&pageSize=100'); const schools = result.items || result || []; list.innerHTML = schools.length ? schools.map((school) => `<div class="period-row"><strong>${escapeHtml(school.name)}</strong><span>${escapeHtml(school.region || '未填写')} · ${school.status === 'active' ? '正常' : '已停用'}</span><button class="ghost-btn" data-school-id="${escapeHtml(school.id)}" data-school-status="${school.status === 'active' ? 'inactive' : 'active'}">${school.status === 'active' ? '停用' : '启用'}</button></div>`).join('') : '<div class="empty-chart">尚未创建学校</div>'; } catch (error) { list.textContent = error.message; } };
  const loadPeriods = async () => { try { const periods = await api(`/v1/admin/school-periods?schoolId=${encodeURIComponent(state.schoolId)}`); document.getElementById('periodList').innerHTML = periods.length ? periods.map((period) => `<div class="period-row"><strong>${escapeHtml(period.academicYear)} · ${escapeHtml(period.term)}</strong><span class="status ${period.status === 'active' ? 'done' : 'gray'}">${period.status === 'active' ? '进行中' : '已归档'}</span><button class="ghost-btn" data-period-id="${escapeHtml(period.id)}" data-period-status="${period.status === 'active' ? 'archived' : 'active'}">${period.status === 'active' ? '归档' : '启用'}</button></div>`).join('') : '<div class="empty-chart">尚未建立学年学期</div>'; } catch (error) { document.getElementById('periodList').textContent = error.message; } };
  orgButton.addEventListener('click', () => { orgModal.classList.remove('hidden'); refreshPromoteOptions(); loadSchools(); loadPeriods(); });
  document.getElementById('createSchoolBtn')?.addEventListener('click', async () => { try { await api('/v1/admin/schools', { method: 'POST', headers: { 'Idempotency-Key': `school-${Date.now()}` }, body: JSON.stringify({ name: document.getElementById('newSchoolName').value, campus: document.getElementById('newSchoolCampus').value, region: document.getElementById('newSchoolRegion').value, isPovertyArea: document.getElementById('newSchoolPoverty').checked }) }); toast('学校已创建'); loadSchools(); } catch (error) { toast(error.message, true); } });
  document.getElementById('createPeriodBtn')?.addEventListener('click', async () => { try { await api('/v1/admin/school-periods', { method: 'POST', headers: { 'Idempotency-Key': `period-${Date.now()}` }, body: JSON.stringify({ schoolId: state.schoolId, academicYear: document.getElementById('periodYear').value, term: document.getElementById('periodTerm').value, startsOn: document.getElementById('periodStarts').value || null, endsOn: document.getElementById('periodEnds').value || null }) }); toast('学年学期已创建'); loadPeriods(); } catch (error) { toast(error.message, true); } });
  document.getElementById('createGradeBtn')?.addEventListener('click', async () => { try { await api('/v1/admin/grades', { method: 'POST', headers: { 'Idempotency-Key': `grade-${Date.now()}` }, body: JSON.stringify({ schoolId: state.schoolId, name: document.getElementById('newGradeName').value, academicYear: document.getElementById('newGradeYear').value }) }); toast('年级已创建'); loadAll(); } catch (error) { toast(error.message, true); } });
  document.getElementById('createClassBtn')?.addEventListener('click', async () => { try { await api('/v1/admin/classes', { method: 'POST', headers: { 'Idempotency-Key': `class-${Date.now()}` }, body: JSON.stringify({ schoolId: state.schoolId, gradeId: document.getElementById('newClassGrade').value, name: document.getElementById('newClassName').value }) }); toast('班级已创建'); loadAll(); } catch (error) { toast(error.message, true); } });
  document.addEventListener('click', async (event) => { const button = event.target.closest('[data-period-id]'); if (!button) return; try { await api(`/v1/admin/school-periods/${encodeURIComponent(button.dataset.periodId)}/status`, { method: 'PATCH', headers: { 'Idempotency-Key': `period-status-${Date.now()}` }, body: JSON.stringify({ status: button.dataset.periodStatus }) }); toast('学年学期状态已更新'); loadPeriods(); } catch (error) { toast(error.message, true); } });
  document.addEventListener('click', async (event) => { const button = event.target.closest('[data-school-id]'); if (!button) return; if (!window.confirm(button.dataset.schoolStatus === 'inactive' ? '停用学校后，该学校将不能继续导入和维护新数据，确认继续？' : '确认重新启用该学校？')) return; try { await api(`/v1/admin/schools/${encodeURIComponent(button.dataset.schoolId)}/status`, { method: 'PATCH', headers: { 'Idempotency-Key': `school-status-${Date.now()}` }, body: JSON.stringify({ status: button.dataset.schoolStatus }) }); toast('学校状态已更新'); loadSchools(); } catch (error) { toast(error.message, true); } });

  const operationPanel = document.getElementById('operationsSection');
  const queueModal = makeModal('operationQueueModal', '运营待办', '打开后可以查看明细并完成处理。', '<div class="queue-filter"><select id="operationTypeFilter"><option value="all">全部待办</option><option value="reviews">待复核成绩</option><option value="activities">活动报名</option><option value="appointments">专家预约</option><option value="courseUploads">课程上传</option><option value="support">客服咨询</option><option value="privacy">隐私申请</option></select></div><div id="operationQueueList" class="operation-queue-list">正在加载...</div>');
  const loadQueue = async () => { const list = document.getElementById('operationQueueList'); try { const type = document.getElementById('operationTypeFilter')?.value || 'all'; const items = await api(`/v1/admin/operations/items?schoolId=${encodeURIComponent(state.schoolId)}&type=${encodeURIComponent(type)}`); list.innerHTML = items.length ? items.map((item) => `<div class="queue-item"><div><strong>${escapeHtml(item.studentName || item.title || item.content || item.expertName || item.attachmentName || item.requestType || '待处理')}</strong><small>${escapeHtml(item.className || item.contactName || item.userName || item.preferredDate || item.taskTitle || '')} · ${escapeHtml(String(item.createdAt || '').slice(0, 16))}</small></div><button class="secondary-btn" data-operation-type="${escapeHtml(item.type)}" data-operation-id="${escapeHtml(item.id)}">处理</button></div>`).join('') : '<div class="empty-chart">当前没有待处理事项</div>'; } catch (error) { list.textContent = error.message; } };
  operationPanel?.querySelector('#refreshOperationsBtn')?.addEventListener('click', () => { queueModal.classList.remove('hidden'); loadQueue(); });
  document.getElementById('operationTypeFilter')?.addEventListener('change', loadQueue);
  document.addEventListener('click', async (event) => { const button = event.target.closest('[data-operation-type]'); if (!button) return; const statusMap = { reviews: 'passed', activities: 'confirmed', appointments: 'confirmed', courseUploads: 'approved', support: 'resolved', privacy: 'completed' }; const status = statusMap[button.dataset.operationType]; if (!status || !window.confirm('确认将该事项标记为已处理？')) return; try { await api(`/v1/admin/operations/${encodeURIComponent(button.dataset.operationType)}/${encodeURIComponent(button.dataset.operationId)}/status`, { method: 'PATCH', headers: { 'Idempotency-Key': `operation-${Date.now()}` }, body: JSON.stringify({ status }) }); toast('事项已处理'); loadQueue(); loadAll(); } catch (error) { toast(error.message, true); } });

  const noticeButton = document.createElement('button'); noticeButton.id = 'sendNoticeBtn'; noticeButton.className = 'secondary-btn'; noticeButton.textContent = '发送通知'; document.querySelector('#settingsSection .panel-head')?.append(noticeButton);
  const noticeModal = makeModal('notificationModal', '发送学校通知', '当前提供站内通知；短信、微信和推送需要配置对应服务商。', '<div class="hard-form-grid"><div class="field full"><label for="noticeTitle">通知标题</label><input id="noticeTitle" placeholder="例如：秋季测评安排提醒"></div><div class="field full"><label for="noticeContent">通知内容</label><textarea id="noticeContent" rows="5" placeholder="填写需要发送给学校成员的内容"></textarea></div><div class="field"><label for="noticeAudience">发送范围</label><select id="noticeAudience"><option value="school">全校</option><option value="grade">指定年级</option><option value="class">指定班级</option></select></div><div class="field"><label for="noticeScopeId">范围 ID</label><input id="noticeScopeId" placeholder="年级或班级 ID"></div></div><div class="modal-footer"><button id="sendNoticeConfirm" type="button" class="primary-btn">发送站内通知</button></div>');
  noticeButton.addEventListener('click', () => noticeModal.classList.remove('hidden'));
  document.getElementById('sendNoticeConfirm')?.addEventListener('click', async () => { try { const audienceType = document.getElementById('noticeAudience').value; const scopeId = document.getElementById('noticeScopeId').value; await api('/v1/admin/notifications/campaigns', { method: 'POST', headers: { 'Idempotency-Key': `notification-${Date.now()}` }, body: JSON.stringify({ schoolId: state.schoolId, title: document.getElementById('noticeTitle').value, content: document.getElementById('noticeContent').value, audienceType, ...(audienceType === 'grade' ? { gradeId: scopeId } : {}), ...(audienceType === 'class' ? { classId: scopeId } : {}) }) }); toast('站内通知已发送'); noticeModal.classList.add('hidden'); } catch (error) { toast(error.message, true); } });

  const securityButton = document.createElement('button'); securityButton.id = 'mfaSecurityBtn'; securityButton.className = 'ghost-btn'; securityButton.type = 'button'; securityButton.textContent = '账户安全'; document.querySelector('.top-actions')?.prepend(securityButton);
  const mfaModal = makeModal('mfaSecurityModal', '账户安全', '为当前账户启用基于身份验证器的双重验证。密钥只在本次设置时显示；恢复码请保存到企业密码库。', '<div id="mfaSecurityStatus" class="detail-note">正在读取安全状态…</div><div class="hard-form-grid"><div class="field"><label for="mfaCurrentPassword">当前密码</label><input id="mfaCurrentPassword" type="password" autocomplete="current-password" placeholder="用于确认安全操作"></div><div class="field"><label for="mfaTotpCode">身份验证器验证码</label><input id="mfaTotpCode" inputmode="numeric" autocomplete="one-time-code" placeholder="6 位动态口令"></div><div class="field full"><button id="mfaStartSetup" type="button" class="secondary-btn">生成身份验证器密钥</button><div id="mfaSetupSecret" class="field-key-notice hidden"></div></div><div class="field full"><button id="mfaConfirmSetup" type="button" class="primary-btn" disabled>确认启用并显示恢复码</button><button id="mfaDisable" type="button" class="ghost-btn">关闭双重验证</button></div></div>');
  const loadMfaSecurity = async () => {
    const status = document.getElementById('mfaSecurityStatus');
    try { const data = await api('/v1/me/mfa'); status.textContent = data.enabled ? `双重验证已启用 · 剩余 ${data.recoveryCodesRemaining} 个恢复码。` : data.pendingExpiresAt ? `设置已生成，至 ${fieldNow(data.pendingExpiresAt)} 前完成验证码确认。` : '双重验证尚未启用。建议管理员、校长和数据治理人员启用。'; document.getElementById('mfaDisable').disabled = !data.enabled; } catch (error) { status.textContent = error.message; }
  };
  securityButton.addEventListener('click', () => { mfaModal.classList.remove('hidden'); loadMfaSecurity(); });
  document.getElementById('mfaStartSetup')?.addEventListener('click', async () => {
    try { const result = await api('/v1/me/mfa/totp/setup', { method: 'POST', body: JSON.stringify({ currentPassword: document.getElementById('mfaCurrentPassword').value }) }); const secret = document.getElementById('mfaSetupSecret'); secret.classList.remove('hidden'); secret.innerHTML = `<strong>身份验证器密钥（仅本次显示）</strong><code>${escapeHtml(result.secret)}</code><span>在 Microsoft/Google Authenticator、1Password 等应用中选择“手动输入密钥”，账户名称为“向上少年”。</span>`; document.getElementById('mfaConfirmSetup').disabled = false; document.getElementById('mfaSecurityStatus').textContent = `请在 ${fieldNow(result.pendingExpiresAt)} 前输入验证码确认。`; } catch (error) { toast(error.message, true); }
  });
  document.getElementById('mfaConfirmSetup')?.addEventListener('click', async () => {
    try { const result = await api('/v1/me/mfa/totp/confirm', { method: 'POST', body: JSON.stringify({ code: document.getElementById('mfaTotpCode').value }) }); const secret = document.getElementById('mfaSetupSecret'); secret.classList.remove('hidden'); secret.innerHTML = `<strong>恢复码（仅显示一次）</strong><code>${result.recoveryCodes.map(escapeHtml).join('<br>')}</code><span>请立即保存到企业密码库。每个恢复码只能使用一次。</span>`; document.getElementById('mfaConfirmSetup').disabled = true; toast('双重验证已启用'); await loadMfaSecurity(); } catch (error) { toast(error.message, true); }
  });
  document.getElementById('mfaDisable')?.addEventListener('click', async () => {
    if (!window.confirm('关闭后，其他已登录设备将退出。确认关闭双重验证？')) return;
    try { await api('/v1/me/mfa/totp/disable', { method: 'POST', body: JSON.stringify({ currentPassword: document.getElementById('mfaCurrentPassword').value, code: document.getElementById('mfaTotpCode').value }) }); toast('双重验证已关闭'); document.getElementById('mfaSetupSecret').classList.add('hidden'); await loadMfaSecurity(); } catch (error) { toast(error.message, true); }
  });
  const auditIntegrityButton = document.createElement('button'); auditIntegrityButton.id = 'auditIntegrityBtn'; auditIntegrityButton.className = 'ghost-btn'; auditIntegrityButton.type = 'button'; auditIntegrityButton.textContent = '校验审计'; document.querySelector('#settingsSection .panel-head')?.append(auditIntegrityButton);
  auditIntegrityButton.addEventListener('click', async () => {
    try { const data = await api(`/v1/admin/audit-integrity?schoolId=${encodeURIComponent(state.schoolId)}`); toast(data.valid ? `审计链完整：已校验 ${data.checked} 条记录` : `审计链异常，首个异常记录：${data.failedEntryId || '未知'}`, !data.valid); } catch (error) { if (error.message.includes('权限')) auditIntegrityButton.classList.add('hidden'); toast(error.message, true); }
  });
  const failedJobsButton = document.createElement('button'); failedJobsButton.id = 'failedJobsBtn'; failedJobsButton.className = 'ghost-btn'; failedJobsButton.type = 'button'; failedJobsButton.textContent = '失败任务'; document.querySelector('#settingsSection .panel-head')?.append(failedJobsButton);
  const failedJobsModal = makeModal('failedJobsModal', '失败后台任务', '仅显示已进入失败队列的任务。确认原因后可重试；每次重试都会写入审计链。', '<div id="failedJobsList" class="operation-queue-list">正在加载...</div>');
  const loadFailedJobs = async () => {
    const list = document.getElementById('failedJobsList');
    try { const result = await api('/v1/admin/jobs?status=failed&paged=1&page=1&pageSize=100'); const jobs = result.items || []; list.innerHTML = jobs.length ? jobs.map((job) => `<div class="queue-item"><div><strong>${escapeHtml(job.jobType)} · 尝试 ${job.attempts} 次</strong><small>${escapeHtml(job.lastError || '未提供失败原因')} · ${fieldNow(job.createdAt)}</small></div><button class="secondary-btn" data-retry-job-id="${escapeHtml(job.id)}">重试</button></div>`).join('') : '<div class="empty-chart">当前没有失败后台任务</div>'; } catch (error) { if (error.message.includes('权限')) { failedJobsButton.classList.add('hidden'); failedJobsModal.classList.add('hidden'); } else list.textContent = error.message; }
  };
  failedJobsButton.addEventListener('click', () => { failedJobsModal.classList.remove('hidden'); loadFailedJobs(); });
  document.addEventListener('click', async (event) => { const button = event.target.closest('[data-retry-job-id]'); if (!button) return; if (!window.confirm('确认重新投递此失败任务？系统会保留原失败原因并写入审计。')) return; try { await api(`/v1/admin/jobs/${encodeURIComponent(button.dataset.retryJobId)}/retry`, { method: 'POST', headers: { 'Idempotency-Key': `job-retry-${button.dataset.retryJobId}-${Date.now()}` }, body: '{}' }); toast('后台任务已重新投递'); await loadFailedJobs(); } catch (error) { toast(error.message, true); } });

  const directory = { page: 1, pageSize: 20, total: 0, loading: false };
  const renderServerStudents = (items) => {
    const table = document.getElementById('studentTable');
    if (!table) return;
    table.innerHTML = items.length ? items.map((student) => `<tr class="clickable-row" tabindex="0" data-student-id="${escapeHtml(student.id)}"><td><div class="student-cell"><span class="student-mini">${escapeHtml(String(student.name || '').slice(0, 1))}</span><span><strong>${escapeHtml(student.name)}</strong><small>${escapeHtml(student.gender || '')} · ${escapeHtml(student.birthDate ? dateText(student.birthDate) : '未填写生日')}</small></span></div></td><td>${escapeHtml(student.grade || '—')} / ${escapeHtml(student.className || '—')}</td><td><span class="status ${statusClass(student.taskStatus)}">${escapeHtml(student.taskStatus || '未签到')}</span></td><td><strong>${student.totalScore == null ? '-' : Number(student.totalScore).toFixed(1)}</strong><span class="hint"> / 35</span></td><td>${student.isPovertyArea ? '<span class="status attention">重点帮扶</span>' : escapeHtml(student.region || '—')}</td></tr>`).join('') : '<tr><td colspan="5"><div class="empty-chart">没有匹配的学生</div></td></tr>';
    const pager = document.getElementById('studentPager');
    if (pager) { const pages = Math.max(1, Math.ceil(directory.total / directory.pageSize)); pager.innerHTML = `<span>第 ${directory.page} / ${pages} 页，共 ${directory.total} 条</span><span class="pager-actions"><button class="ghost-btn" data-server-student-page="${Math.max(1, directory.page - 1)}" ${directory.page <= 1 ? 'disabled' : ''}>上一页</button><button class="ghost-btn" data-server-student-page="${Math.min(pages, directory.page + 1)}" ${directory.page >= pages ? 'disabled' : ''}>下一页</button></span>`; }
  };
  const loadServerStudents = async (page = 1) => {
    if (directory.loading || !state.schoolId) return;
    directory.loading = true; directory.page = page;
    try {
      const search = String(state.search || '').trim();
      const data = await api(`/v1/schools/${encodeURIComponent(state.schoolId)}/students?paged=1&page=${page}&pageSize=${directory.pageSize}${search ? `&search=${encodeURIComponent(search)}` : ''}`);
      directory.total = Number(data?.total || 0); renderServerStudents(data?.items || []);
    } catch (error) { toast(error.message, true); } finally { directory.loading = false; }
  };
  renderStudents = () => { void loadServerStudents(1); };
  document.addEventListener('click', (event) => { const pageButton = event.target.closest('[data-server-student-page]'); if (pageButton) void loadServerStudents(Number(pageButton.dataset.serverStudentPage)); });
  const originalLoadAllForDirectory = loadAll;
  loadAll = async () => { await originalLoadAllForDirectory(); await loadServerStudents(1); };

  const fieldButton = document.createElement('button');
  fieldButton.id = 'fieldOperationsBtn'; fieldButton.className = 'secondary-btn'; fieldButton.textContent = '场地中控';
  document.querySelector('.heading-actions')?.append(fieldButton);
  const fieldModal = makeModal('fieldOperationsModal', '场地中控', '设备、测试点与采集会话使用同一套学校任务与学生数据。设备密钥只在注册或轮换时显示一次。', `
    <div class="field-command-bar"><div><strong id="fieldOpsSummary">正在读取场地状态…</strong><span>设备心跳、离线同步和人工复核均可追溯</span></div><button id="fieldOpsRefresh" class="ghost-btn" type="button">刷新</button></div>
    <div class="field-ops-grid"><section><h3>测试点</h3><div id="fieldStationList" class="field-ops-list"></div></section><section><h3>边缘设备</h3><div id="fieldDeviceList" class="field-ops-list"></div></section></div>
    <section class="field-session-panel"><div class="detail-list-head"><strong>候测队列分流</strong><span class="hint">只会重新分配“候测”学生；已叫号、签到或测试中的学生不会被迁移。</span></div><div class="field-command-bar"><select id="fieldDispatchTask" aria-label="选择待分流的测评任务"></select><button id="fieldRebalanceQueue" class="secondary-btn" type="button">重新均衡候测队列</button></div><span id="fieldDispatchHint" class="hint">加载任务中</span></section>
    <section class="field-session-panel"><div class="detail-list-head"><strong>最近采集会话</strong><span id="fieldSessionHint" class="hint">加载中</span></div><div id="fieldSessionList" class="field-session-list"></div></section>
    <div class="hard-form-grid field-admin-forms"><div class="field full"><h3>注册测试点</h3></div><div class="field"><label for="fieldStationCode">测试点编码</label><input id="fieldStationCode" placeholder="例如 A-01"></div><div class="field"><label for="fieldStationName">测试点名称</label><input id="fieldStationName" placeholder="例如 操场跳跃区"></div><div class="field"><label for="fieldStationItem">测评项目</label><input id="fieldStationItem" placeholder="连续双脚障碍跳"></div><div class="field"><label for="fieldStationCapacity">队列容量</label><input id="fieldStationCapacity" type="number" value="20" min="1" max="500"></div><div class="field full"><button id="createFieldStation" type="button" class="secondary-btn">创建测试点</button></div>
      <div class="field full"><h3>注册 Windows 边缘主机</h3></div><div class="field"><label for="fieldDeviceStation">绑定测试点</label><select id="fieldDeviceStation"></select></div><div class="field"><label for="fieldDeviceCode">设备编码</label><input id="fieldDeviceCode" placeholder="例如 EDGE-A-01"></div><div class="field"><label for="fieldDeviceName">设备名称</label><input id="fieldDeviceName" placeholder="例如 A 区采集主机"></div><div class="field"><label for="fieldDeviceVersion">软件版本</label><input id="fieldDeviceVersion" value="field-client/0.1"></div><div class="field full"><button id="createFieldDevice" type="button" class="primary-btn">注册并显示设备密钥</button><div id="fieldDeviceKeyNotice" class="field-key-notice hidden"></div></div>
      <div class="field full"><h3>下发并激活标定</h3><span class="hint">正式采集必须有已激活的标定。提交新版本会自动归档当前有效标定；请使用设备校准工具生成的 SHA-256 校验值。</span></div><div class="field"><label for="fieldCalibrationStation">测试点</label><select id="fieldCalibrationStation"></select></div><div class="field"><label for="fieldCalibrationVersion">标定版本</label><input id="fieldCalibrationVersion" placeholder="例如 CAL-2026-09-A01"></div><div class="field full"><label for="fieldCalibrationChecksum">配置 SHA-256</label><input id="fieldCalibrationChecksum" maxlength="64" placeholder="64 位十六进制校验值"></div><div class="field full"><label for="fieldCalibrationConfig">标定配置 JSON</label><textarea id="fieldCalibrationConfig" rows="4" placeholder='例如 {"cameraHeightCm":130,"captureZone":"2m x 3m","operator":"校准员"}'></textarea></div><div class="field full"><button id="createFieldCalibration" type="button" class="secondary-btn">下发并激活标定</button></div>
    </div>`);
  let fieldStations = [];
  let fieldDispatchTaskId = '';
  const fieldNow = (value) => value ? new Date(value).toLocaleString('zh-CN', { hour12: false }) : '从未连接';
  const loadFieldOperations = async () => {
    const schoolId = state.schoolId;
    const summary = document.getElementById('fieldOpsSummary');
    try {
      const [stations, devices, sessions, tasksResult] = await Promise.all([
        api(`/v1/admin/test-stations?schoolId=${encodeURIComponent(schoolId)}`),
        api(`/v1/admin/test-devices?schoolId=${encodeURIComponent(schoolId)}`),
        api(`/v1/admin/test-sessions?schoolId=${encodeURIComponent(schoolId)}&pageSize=12`),
        api(`/v1/schools/${encodeURIComponent(schoolId)}/tasks?paged=1&pageSize=100`)
      ]);
      fieldStations = stations || [];
      const online = (devices || []).filter((item) => item.status === 'online').length;
      const formalReady = (devices || []).filter((item) => item.readiness?.ready).length;
      summary.textContent = `${fieldStations.length} 个测试点 · ${online}/${(devices || []).length} 台设备在线 · ${formalReady} 台通过正式开测自检 · ${(sessions || []).filter((item) => item.status === 'needs_review').length} 个会话待复核`;
      document.getElementById('fieldStationList').innerHTML = fieldStations.length ? fieldStations.map((item) => `<article class="field-ops-card"><div><strong>${escapeHtml(item.stationCode)} · ${escapeHtml(item.name)}</strong><small>${escapeHtml(item.itemCode || '未绑定项目')} · 队列容量 ${item.queueCapacity} · 标定 ${escapeHtml(item.activeCalibrationVersion || '未下发')}</small></div><span class="status ${item.status === 'online' && item.activeCalibrationVersion ? 'done' : item.status === 'maintenance' ? 'review' : 'gray'}">${item.activeCalibrationVersion ? escapeHtml(item.status) : '待标定'}</span></article>`).join('') : '<div class="empty-chart">尚未注册测试点</div>';
      document.getElementById('fieldDeviceList').innerHTML = (devices || []).length ? devices.map((item) => { const keyStatus = item.apiKeyStatus || 'legacy_unbounded'; const keyLabel = { valid: '密钥有效', expiring: '密钥即将到期', expired: '密钥已过期', legacy_unbounded: '需轮换旧密钥', rotation_required: '需轮换启用签名' }[keyStatus] || keyStatus; const keyClass = keyStatus === 'valid' ? 'done' : keyStatus === 'expiring' ? 'review' : 'pending'; const readiness = item.readiness || {}; const hardware = readiness.hardware || {}; const preflightLabel = readiness.ready ? '可正式开测' : '自检未通过'; const preflightClass = readiness.ready ? 'done' : item.status === 'online' ? 'review' : 'gray'; const preflightDetail = readiness.ready ? `自检通过 · 同步 ${hardware.frameSyncOffsetMs ?? '—'}ms · 标定误差 ${hardware.calibrationErrorCm ?? '—'}cm` : (readiness.blockers || []).slice(0, 2).join('；') || '等待自检上报'; return `<article class="field-ops-card"><div><strong>${escapeHtml(item.deviceCode)} · ${escapeHtml(item.name)}</strong><small>${escapeHtml(item.stationCode || '未绑定测试点')} · ${escapeHtml(item.softwareVersion || '版本未上报')} · 心跳 ${fieldNow(item.lastHeartbeatAt)} · ${escapeHtml(preflightDetail)} · 密钥到期 ${fieldNow(item.apiKeyExpiresAt)}</small></div><div class="field-card-actions"><span class="status ${item.status === 'online' ? 'done' : 'gray'}">${escapeHtml(item.status)}</span><span class="status ${preflightClass}">${escapeHtml(preflightLabel)}</span><span class="status ${keyClass}">${escapeHtml(keyLabel)}</span><button class="ghost-btn" data-field-command-device="${escapeHtml(item.id)}" type="button">同步配置</button><button class="ghost-btn" data-field-rotate-device="${escapeHtml(item.id)}" type="button">轮换密钥</button></div></article>`; }).join('') : '<div class="empty-chart">尚未注册边缘主机</div>';
      document.getElementById('fieldSessionHint').textContent = `最近 ${(sessions || []).length} 条`;
      document.getElementById('fieldSessionList').innerHTML = (sessions || []).length ? sessions.map((item) => `<button class="field-session-row" data-field-session-id="${escapeHtml(item.id)}" type="button"><span><strong>${escapeHtml(item.studentName)} · ${escapeHtml(item.taskTitle)}</strong><small>${escapeHtml(item.stationCode || '未分配测试点')} · ${fieldNow(item.startedAt)}</small></span><span class="status ${item.status === 'completed' ? 'done' : item.status === 'needs_review' ? 'review' : 'pending'}">${escapeHtml(item.status)}</span></button>`).join('') : '<div class="empty-chart">尚无场地采集会话</div>';
      const stationOptions = `<option value="">请选择测试点</option>${fieldStations.map((item) => `<option value="${escapeHtml(item.id)}">${escapeHtml(item.stationCode)} · ${escapeHtml(item.name)}</option>`).join('')}`;
      document.getElementById('fieldDeviceStation').innerHTML = stationOptions;
      document.getElementById('fieldCalibrationStation').innerHTML = stationOptions;
      const fieldTasks = Array.isArray(tasksResult) ? tasksResult : (tasksResult?.items || []);
      const dispatchableTasks = fieldTasks.filter((item) => item.status === '未签到');
      if (!dispatchableTasks.some((item) => item.id === fieldDispatchTaskId)) fieldDispatchTaskId = dispatchableTasks[0]?.id || '';
      const dispatchSelect = document.getElementById('fieldDispatchTask');
      dispatchSelect.innerHTML = dispatchableTasks.length ? dispatchableTasks.map((item) => `<option value="${escapeHtml(item.id)}" ${item.id === fieldDispatchTaskId ? 'selected' : ''}>${escapeHtml(item.title)} · ${escapeHtml(String(item.date || '').slice(0, 10))} · ${item.completedCount || 0}/${item.totalCount || 0}</option>`).join('') : '<option value="">暂无已发布任务</option>';
      document.getElementById('fieldRebalanceQueue').disabled = !dispatchableTasks.length;
      document.getElementById('fieldDispatchHint').textContent = dispatchableTasks.length ? '将按测试点容量和当前占用比例均衡分流；不改变进行中的现场流程。' : '当前没有可分流的已发布任务。';
    } catch (error) { summary.textContent = error.message || '场地状态加载失败'; }
  };
  fieldButton.addEventListener('click', () => { fieldModal.classList.remove('hidden'); loadFieldOperations(); });
  document.getElementById('fieldOpsRefresh')?.addEventListener('click', loadFieldOperations);
  document.getElementById('fieldDispatchTask')?.addEventListener('change', (event) => { fieldDispatchTaskId = event.target.value; });
  document.getElementById('fieldRebalanceQueue')?.addEventListener('click', async () => {
    try {
      const taskId = document.getElementById('fieldDispatchTask').value;
      if (!taskId) throw new Error('请选择已发布的测评任务');
      if (!window.confirm('将重新均衡候测学生。已叫号、签到或测试中的学生不会被移动，确认继续？')) return;
      const result = await api('/v1/admin/test-queues/rebalance', { method: 'POST', headers: { 'Idempotency-Key': `field-rebalance-${taskId}-${Date.now()}` }, body: JSON.stringify({ taskId }) });
      const stations = (result.eligibleStations || []).map((item) => item.stationCode).join('、') || '无';
      document.getElementById('fieldDispatchHint').textContent = `已分流 ${result.assignments?.length || 0} 人，合格测试点：${stations}，未分配候测：${result.unassignedCount || 0} 人。`;
      toast(`候测队列已重新均衡：${result.assignments?.length || 0} 人`);
      await loadFieldOperations();
    } catch (error) { toast(error.message, true); }
  });
  document.getElementById('createFieldStation')?.addEventListener('click', async () => {
    try {
      await api('/v1/admin/test-stations', { method: 'POST', headers: { 'Idempotency-Key': `field-station-${Date.now()}` }, body: JSON.stringify({ schoolId: state.schoolId, stationCode: document.getElementById('fieldStationCode').value, name: document.getElementById('fieldStationName').value, itemCode: document.getElementById('fieldStationItem').value, queueCapacity: Number(document.getElementById('fieldStationCapacity').value || 20) }) });
      toast('测试点已创建'); await loadFieldOperations();
    } catch (error) { toast(error.message, true); }
  });
  document.getElementById('createFieldDevice')?.addEventListener('click', async () => {
    try {
      const result = await api('/v1/admin/test-devices', { method: 'POST', body: JSON.stringify({ schoolId: state.schoolId, stationId: document.getElementById('fieldDeviceStation').value, deviceCode: document.getElementById('fieldDeviceCode').value, name: document.getElementById('fieldDeviceName').value, deviceType: 'edge_host', softwareVersion: document.getElementById('fieldDeviceVersion').value, capabilities: { offline: true } }) });
      const notice = document.getElementById('fieldDeviceKeyNotice'); notice.classList.remove('hidden'); notice.innerHTML = `<strong>仅显示一次的设备密钥</strong><code>${escapeHtml(result.deviceKey)}</code><span>请立即导入 Windows Credential Manager；关闭此窗口后无法再次查看。</span>`;
      toast('边缘主机已注册'); await loadFieldOperations();
    } catch (error) { toast(error.message, true); }
  });
  document.getElementById('createFieldCalibration')?.addEventListener('click', async () => {
    try {
      const stationId = document.getElementById('fieldCalibrationStation').value;
      const version = document.getElementById('fieldCalibrationVersion').value.trim();
      const checksumSha256 = document.getElementById('fieldCalibrationChecksum').value.trim();
      let config;
      try { config = JSON.parse(document.getElementById('fieldCalibrationConfig').value); } catch { throw new Error('标定配置必须是有效 JSON'); }
      if (!config || Array.isArray(config) || typeof config !== 'object' || !Object.keys(config).length) throw new Error('标定配置不能为空');
      await api(`/v1/admin/test-stations/${encodeURIComponent(stationId)}/calibrations`, { method: 'POST', headers: { 'Idempotency-Key': `field-calibration-${Date.now()}` }, body: JSON.stringify({ version, checksumSha256, config }) });
      toast('标定已下发并激活，场地端下次同步后可开始正式采集');
      document.getElementById('fieldCalibrationVersion').value = '';
      document.getElementById('fieldCalibrationChecksum').value = '';
      document.getElementById('fieldCalibrationConfig').value = '';
      await loadFieldOperations();
    } catch (error) { toast(error.message, true); }
  });
  document.addEventListener('click', async (event) => {
    const rotate = event.target.closest('[data-field-rotate-device]');
    if (rotate) {
      if (!window.confirm('轮换后该电脑端必须立即更新密钥；确认继续？')) return;
      try {
        const result = await api(`/v1/admin/test-devices/${encodeURIComponent(rotate.dataset.fieldRotateDevice)}/rotate-key`, { method: 'POST', body: '{}' });
        const notice = document.getElementById('fieldDeviceKeyNotice'); notice.classList.remove('hidden'); notice.innerHTML = `<strong>仅显示一次的新设备密钥</strong><code>${escapeHtml(result.deviceKey)}</code><span>有效至 ${escapeHtml(fieldNow(result.apiKeyExpiresAt))}，请立即导入 Windows Credential Manager。</span>`;
        toast('设备密钥已轮换，旧密钥已失效'); await loadFieldOperations();
      } catch (error) { toast(error.message, true); }
      return;
    }
    const command = event.target.closest('[data-field-command-device]');
    if (command) {
      try { await api('/v1/admin/device-commands', { method: 'POST', body: JSON.stringify({ deviceId: command.dataset.fieldCommandDevice, commandType: 'refresh_config', payload: { requestedFrom: 'admin' } }) }); toast('配置同步指令已下发'); await loadFieldOperations(); } catch (error) { toast(error.message, true); }
      return;
    }
    const session = event.target.closest('[data-field-session-id]');
    if (!session) return;
    try {
      const detail = await api(`/v1/admin/test-sessions/${encodeURIComponent(session.dataset.fieldSessionId)}`);
      const title = document.getElementById('detailTitle'); const subtitle = document.getElementById('detailSubtitle'); const body = document.getElementById('detailBody');
      title.textContent = `${detail.studentName} · 场地会话`; subtitle.textContent = `${detail.stationCode || '未分配测试点'} · ${detail.status}`;
      const evidenceSummary = detail.evidence.length ? detail.evidence.map((evidence) => evidence.purgedAt ? `${escapeHtml(evidence.evidenceType)}：已按保留策略清理` : `${escapeHtml(evidence.evidenceType)}：保留至 ${fieldNow(evidence.retentionUntil)}`).join(' · ') : '尚未关联证据';
      body.innerHTML = `<div class="detail-grid"><div><span>规则版本</span><strong>${escapeHtml(detail.rule_version || detail.ruleVersion || '—')}</strong></div><div><span>算法 / 标定</span><strong>${escapeHtml(detail.algorithm_version || detail.algorithmVersion || '—')} / ${escapeHtml(detail.calibration_version || detail.calibrationVersion || '—')}</strong></div><div><span>采集事件</span><strong>${detail.events.length} 条</strong></div><div><span>证据文件</span><strong>${detail.evidence.length} 个</strong></div></div><div class="detail-note">成绩：${detail.scores.map((score) => `${escapeHtml(score.item)} ${Number(score.score).toFixed(1)}（${Math.round(Number(score.confidence) * 100)}%）`).join(' · ') || '尚未提交'}</div><div class="detail-note">证据保留：${evidenceSummary}</div>`;
      fieldModal.classList.add('hidden');
      detailModal.classList.remove('hidden'); document.body.classList.add('modal-open');
    } catch (error) { toast(error.message, true); }
  });
})();
