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
    const all = (state.dashboard?.tasks || []).filter((task) => task.lifecycleStatus !== 'draft').filter((task) => !query || `${task.title}${task.gradeName}${task.className}`.toLowerCase().includes(query));
    const pages = Math.max(1, Math.ceil(all.length / pageState.pageSize));
    pageState.tasks = Math.min(pageState.tasks, pages);
    const items = all.slice((pageState.tasks - 1) * pageState.pageSize, pageState.tasks * pageState.pageSize);
    table.innerHTML = items.length ? items.map((task) => {
      const rate = task.totalCount ? Math.round(task.completedCount / task.totalCount * 100) : 0;
      const progressStatus = task.progressStatus || task.status || '未开始';
      const lifecycleLabel = { draft: '草稿', published: '已发布', closed: '已关闭', archived: '已归档' }[task.lifecycleStatus] || task.lifecycleStatus || '—';
      return `<tr class="clickable-row" tabindex="0" data-task-id="${escapeHtml(task.id)}"><td><strong>${escapeHtml(task.title)}</strong></td><td>${escapeHtml(task.gradeName || '全校')} / ${escapeHtml(task.className || '全校')}</td><td><div class="progress-cell"><div class="mini-progress"><i style="width:${rate}%"></i></div><span>${task.completedCount || 0}/${task.totalCount || 0}</span></div></td><td><span class="task-status-stack"><span class="status ${statusClass(progressStatus)}">${escapeHtml(progressStatus)}</span><small>${escapeHtml(lifecycleLabel)}</small></span></td><td>${dateText(task.date)}</td></tr>`;
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

  const taskClosureModal = document.createElement('div');
  taskClosureModal.id = 'taskClosureModal';
  taskClosureModal.className = 'modal-backdrop hidden';
  taskClosureModal.innerHTML = `<div class="modal task-closure-modal"><div class="modal-head"><div><h2 id="taskClosureTitle">安全关闭现场任务</h2><p>停止场地端下发，并为每名未完成学生保留明确去向。</p></div><button class="modal-close" type="button" aria-label="关闭">×</button></div><div class="task-closure-body"><div id="taskClosureSummary" class="task-closure-summary"></div><div class="task-closure-guard"><strong>关闭前系统会自动检查</strong><span>正在测试的会话、待复核记录和缺少有效成绩的“已完成”记录都会阻止关闭。</span></div><div class="field"><label for="taskClosureReason">关闭原因</label><textarea id="taskClosureReason" maxlength="500" rows="3" placeholder="例如：当日测评时间结束，其余学生转入下周补测"></textarea><span class="hint">必填；将写入学生状态、队列事件和审计记录。</span></div><fieldset class="task-closure-options"><legend>未完成学生去向</legend><label><input type="radio" name="taskClosureAction" value="create_followup" checked><span><strong>创建后续补测任务</strong><small>新建草稿任务，只带入本次未完成学生；确认日期后再发布。</small></span></label><label><input type="radio" name="taskClosureAction" value="close_incomplete"><span><strong>本次结束，不创建后续任务</strong><small>未完成学生保留为“未完成”，不会被误记为缺席或已完成。</small></span></label></fieldset><div id="taskClosureFollowUp" class="task-closure-followup"><div class="field"><label for="taskClosureFollowUpDate">后续测评日期</label><input id="taskClosureFollowUpDate" type="date"></div><div class="field"><label for="taskClosureFollowUpTitle">后续任务标题</label><input id="taskClosureFollowUpTitle" maxlength="160"></div></div><div id="taskClosureError" class="task-closure-error hidden"></div><div class="modal-footer"><button id="cancelTaskClosure" class="ghost-btn" type="button">取消</button><button id="confirmTaskClosure" class="primary-btn" type="button">检查并关闭任务</button></div></div></div>`;
  taskClosureModal.setAttribute('role', 'dialog');
  taskClosureModal.setAttribute('aria-modal', 'true');
  taskClosureModal.setAttribute('aria-labelledby', 'taskClosureTitle');
  document.body.append(taskClosureModal);
  let taskBeingClosed = null;
  const closeTaskClosure = () => { taskClosureModal.classList.add('hidden'); taskBeingClosed = null; };
  taskClosureModal.querySelector('.modal-close').addEventListener('click', closeTaskClosure);
  document.getElementById('cancelTaskClosure').addEventListener('click', closeTaskClosure);
  taskClosureModal.addEventListener('click', (event) => { if (event.target === taskClosureModal) closeTaskClosure(); });
  const updateTaskClosureFields = () => {
    const action = taskClosureModal.querySelector('input[name="taskClosureAction"]:checked')?.value;
    document.getElementById('taskClosureFollowUp').classList.toggle('hidden', action !== 'create_followup');
  };
  taskClosureModal.querySelectorAll('input[name="taskClosureAction"]').forEach((input) => input.addEventListener('change', updateTaskClosureFields));
  const openTaskClosure = (task) => {
    taskBeingClosed = task;
    const total = Number(task?.totalCount || 0);
    const completed = Number(task?.completedCount || 0);
    const incomplete = Math.max(0, total - completed);
    document.getElementById('taskClosureTitle').textContent = `安全关闭 · ${task?.title || '测评任务'}`;
    document.getElementById('taskClosureSummary').innerHTML = `<div><span>任务人数</span><strong>${total}</strong></div><div><span>有效完成</span><strong>${completed}</strong></div><div class="is-attention"><span>未完成</span><strong>${incomplete}</strong></div>`;
    document.getElementById('taskClosureReason').value = '';
    const followUpRadio = taskClosureModal.querySelector('input[value="create_followup"]');
    const closeOnlyRadio = taskClosureModal.querySelector('input[value="close_incomplete"]');
    followUpRadio.checked = incomplete > 0;
    closeOnlyRadio.checked = incomplete === 0;
    followUpRadio.disabled = incomplete === 0;
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    document.getElementById('taskClosureFollowUpDate').value = `${tomorrow.getFullYear()}-${String(tomorrow.getMonth() + 1).padStart(2, '0')}-${String(tomorrow.getDate()).padStart(2, '0')}`;
    document.getElementById('taskClosureFollowUpTitle').value = `${task?.title || '测评任务'}（后续补测）`;
    document.getElementById('taskClosureError').classList.add('hidden');
    document.getElementById('taskClosureError').textContent = '';
    updateTaskClosureFields();
    taskClosureModal.classList.remove('hidden');
    document.body.classList.add('modal-open');
    setTimeout(() => document.getElementById('taskClosureReason')?.focus(), 0);
  };
  document.getElementById('confirmTaskClosure').addEventListener('click', async () => {
    if (!taskBeingClosed) return;
    const button = document.getElementById('confirmTaskClosure');
    const reason = document.getElementById('taskClosureReason').value.trim();
    const unfinishedAction = taskClosureModal.querySelector('input[name="taskClosureAction"]:checked')?.value;
    const errorNode = document.getElementById('taskClosureError');
    if (!reason) { errorNode.textContent = '请填写关闭原因。'; errorNode.classList.remove('hidden'); return; }
    const payload = { status: 'closed', reason, unfinishedAction };
    if (unfinishedAction === 'create_followup') {
      payload.followUpDate = document.getElementById('taskClosureFollowUpDate').value;
      payload.followUpTitle = document.getElementById('taskClosureFollowUpTitle').value.trim();
      if (!payload.followUpDate) { errorNode.textContent = '请选择后续测评日期。'; errorNode.classList.remove('hidden'); return; }
    }
    button.disabled = true;
    button.textContent = '正在检查现场状态…';
    errorNode.classList.add('hidden');
    try {
      const result = await api(`/v1/admin/tasks/${encodeURIComponent(taskBeingClosed.id)}/status`, { method: 'PATCH', headers: { 'Idempotency-Key': `task-close-${Date.now()}-${Math.random().toString(16).slice(2)}` }, body: JSON.stringify(payload) });
      const followUpText = result.followUpTask ? `，后续草稿已带入 ${result.followUpTask.studentCount} 人` : '';
      toast(`任务已安全关闭：${result.completedStudentCount || 0} 人完成，${result.incompleteStudentCount || 0} 人未完成${followUpText}`);
      closeTaskClosure();
      closeDetail();
      await loadAll();
    } catch (error) {
      errorNode.textContent = error.message || '任务关闭失败';
      errorNode.classList.remove('hidden');
    } finally {
      button.disabled = false;
      button.textContent = '检查并关闭任务';
    }
  });
  const openDetail = async (kind, id) => {
    const title = document.getElementById('detailTitle');
    const subtitle = document.getElementById('detailSubtitle');
    const body = document.getElementById('detailBody');
    detailModal.classList.remove('hidden');
    document.body.classList.add('modal-open');
    detailModal.querySelector('.modal')?.classList.toggle('task-detail-modal', kind === 'task');
    if (kind === 'task') {
      const task = (state.dashboard?.tasks || []).find((item) => item.id === id);
      title.textContent = task?.title || '测评任务详情';
      subtitle.textContent = '任务范围与完成进度';
      body.innerHTML = `<div class="detail-grid"><div><span>测评范围</span><strong>${escapeHtml(task?.gradeName || '全校')} / ${escapeHtml(task?.className || '全校')}</strong></div><div><span>测评日期</span><strong>${escapeHtml(dateText(task?.date))}</strong></div><div><span>任务 / 现场</span><strong>${escapeHtml(({ draft: '草稿', published: '已发布', closed: '已关闭', archived: '已归档' })[task?.lifecycleStatus] || task?.lifecycleStatus || '—')} · ${escapeHtml(task?.progressStatus || task?.status || '—')}</strong></div><div><span>完成进度</span><strong>${task?.completedCount || 0} / ${task?.totalCount || 0}</strong></div></div><div class="detail-note">测评项目：${escapeHtml((task?.items || []).join('、') || '未配置')}</div><div class="detail-actions">${task?.lifecycleStatus === 'published' ? `<button class="primary-btn" data-task-open-field="${escapeHtml(id)}">打开现场运行</button>` : ''}<button class="secondary-btn" data-task-admin="sync" data-task-id="${escapeHtml(id)}">同步新增学生</button><button class="secondary-btn" data-task-admin="clone" data-task-id="${escapeHtml(id)}">复制任务</button>${['closed', 'archived'].includes(task?.lifecycleStatus) ? '' : `<button class="secondary-btn" data-task-admin="close" data-task-id="${escapeHtml(id)}">关闭任务</button>`}</div><div id="taskStudentList" class="task-student-list">正在读取任务学生...</div>`;
      try {
        const students = await api(`/v1/tasks/${encodeURIComponent(id)}/students`);
        const list = students || [];
        const eligibleStatuses = new Set(['测试中', '待复核']);
        const eligibleCount = list.filter((item) => item.completionReady === true && eligibleStatuses.has(item.status)).length;
        const studentGroup = (item) => {
          const completed = item.status === '已完成';
          if (item.status === '未完成') return 'incomplete';
          if (completed && item.completionReady !== true) return 'anomaly';
          if (Number(item.pendingReviewCount || 0) > 0) return 'review';
          if (item.completionReady === true && eligibleStatuses.has(item.status)) return 'ready';
          if (completed) return 'completed';
          return 'pending';
        };
        const groups = Object.fromEntries(['pending', 'review', 'ready', 'completed', 'anomaly', 'incomplete'].map((group) => [group, list.filter((item) => studentGroup(item) === group).length]));
        const taskList = document.getElementById('taskStudentList');
        taskList.innerHTML = list.length ? `<div class="task-situation-grid"><button data-task-student-filter="pending"><strong>${groups.pending}</strong><span>待推进</span></button><button data-task-student-filter="review"><strong>${groups.review}</strong><span>待复核</span></button><button data-task-student-filter="ready"><strong>${groups.ready}</strong><span>成绩已齐</span></button><button data-task-student-filter="completed"><strong>${groups.completed}</strong><span>有效完成</span></button><button class="${groups.anomaly ? 'is-alert' : ''}" data-task-student-filter="anomaly"><strong>${groups.anomaly}</strong><span>完成异常</span></button><button class="${groups.incomplete ? 'is-alert' : ''}" data-task-student-filter="incomplete"><strong>${groups.incomplete}</strong><span>任务未完成</span></button></div><div class="detail-list-head"><span><strong>任务学生</strong><small>成绩齐全且无待复核项后，才可人工确认完成</small></span><button class="secondary-btn" data-batch-task="${escapeHtml(id)}" ${eligibleCount ? '' : 'disabled'}>确认成绩完成${eligibleCount ? `（可选 ${eligibleCount} 人）` : ''}</button></div><div class="task-student-toolbar"><div class="field-filter-tabs"><button class="is-active" data-task-student-filter="all" type="button">全部 ${list.length}</button><button data-task-student-filter="pending" type="button">待推进 ${groups.pending}</button><button data-task-student-filter="review" type="button">待复核 ${groups.review}</button><button data-task-student-filter="ready" type="button">成绩已齐 ${groups.ready}</button><button data-task-student-filter="incomplete" type="button">未完成 ${groups.incomplete}</button><button data-task-student-filter="anomaly" type="button">异常 ${groups.anomaly}</button></div><input id="taskStudentSearch" type="search" placeholder="搜索学生或班级"></div><div id="taskStudentRows"></div>${groups.review || groups.anomaly ? `<button class="task-anomaly-entry" data-operation-filter="completionAnomalies" type="button">处理待复核与完成异常 <span>${groups.review + groups.anomaly} 人需要处理 →</span></button>` : ''}` : '<div class="empty-chart">该任务暂无学生</div>';
        if (!list.length) return;
        let taskStudentFilter = 'all';
        const renderTaskStudentRows = () => {
          const query = String(document.getElementById('taskStudentSearch')?.value || '').trim().toLowerCase();
          const visible = list.filter((item) => (taskStudentFilter === 'all' || studentGroup(item) === taskStudentFilter) && (!query || `${item.studentName || ''}${item.className || ''}`.toLowerCase().includes(query)));
          document.querySelectorAll('[data-task-student-filter]').forEach((button) => button.classList.toggle('is-active', button.dataset.taskStudentFilter === taskStudentFilter));
          document.getElementById('taskStudentRows').innerHTML = visible.length ? visible.map((item) => {
          const completed = item.status === '已完成';
          const eligible = item.completionReady === true && eligibleStatuses.has(item.status);
          const measured = Number(item.measuredItemCount || 0);
          const required = Number(item.requiredItemCount || 0);
          const pending = Number(item.pendingReviewCount || 0);
          const missing = Math.max(0, required - measured);
          const completionAnomaly = completed && item.completionReady !== true;
          const incomplete = item.status === '未完成';
          const readiness = incomplete ? '本次任务已结束，保留未完成记录'
            : completionAnomaly
            ? `历史异常：${[missing ? `缺 ${missing} 项` : '', pending ? `${pending} 项待复核` : ''].filter(Boolean).join(' · ')}`
            : completed ? '有效完成'
              : pending > 0 ? `${pending} 项待复核` : measured < required ? `还缺 ${missing} 项` : eligible ? '成绩已齐，可确认' : '请先推进到测试中';
            return `<label class="task-student-item ${incomplete ? 'is-incomplete' : completionAnomaly ? 'is-anomaly' : completed ? 'is-complete' : eligible ? 'is-ready' : 'is-locked'}"><input type="checkbox" value="${escapeHtml(item.studentId)}" data-task-version="${escapeHtml(item.version)}" ${completed ? 'checked disabled' : eligible ? '' : 'disabled'}><span><strong>${escapeHtml(item.studentName)}</strong><small>${escapeHtml(item.className || '')} · ${escapeHtml(item.status)} · ${measured}/${required} 项成绩</small></span><em>${escapeHtml(readiness)}</em></label>`;
          }).join('') : '<div class="empty-chart">当前筛选没有匹配学生</div>';
        };
        taskList.querySelectorAll('[data-task-student-filter]').forEach((button) => button.addEventListener('click', () => { taskStudentFilter = button.dataset.taskStudentFilter; renderTaskStudentRows(); }));
        document.getElementById('taskStudentSearch')?.addEventListener('input', renderTaskStudentRows);
        renderTaskStudentRows();
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
  window.adminOpenDetail = openDetail;
  document.addEventListener('click', (event) => {
    const taskAdmin = event.target.closest('[data-task-admin]');
    if (taskAdmin) {
      const action = taskAdmin.dataset.taskAdmin;
      const taskId = taskAdmin.dataset.taskId;
      if (action === 'close') {
        const task = (state.dashboard?.tasks || []).find((item) => item.id === taskId);
        if (!task) { toast('任务信息已变化，请刷新后重试', true); return; }
        openTaskClosure(task);
        return;
      }
      const request = action === 'sync'
        ? api(`/v1/admin/tasks/${encodeURIComponent(taskId)}/sync-students`, { method: 'POST', headers: { 'Idempotency-Key': `task-sync-${Date.now()}` }, body: '{}' })
        : api(`/v1/admin/tasks/${encodeURIComponent(taskId)}/clone`, { method: 'POST', headers: { 'Idempotency-Key': `task-clone-${Date.now()}` }, body: '{}' });
      request.then((result) => { toast(action === 'sync' ? `已新增 ${result.addedCount || 0} 名学生` : '任务副本已创建'); closeDetail(); loadAll(); }).catch((error) => toast(error.message, true));
      return;
    }
    const batchButton = event.target.closest('[data-batch-task]');
    if (batchButton) {
      if (batchButton.disabled) return;
      const selected = [...document.querySelectorAll('#taskStudentList input[type="checkbox"]:checked:not(:disabled)')];
      if (!selected.length) { toast('请选择“成绩已齐，可确认”的学生', true); return; }
      api('/v1/admin/tasks/batch-status', { method: 'POST', headers: { 'Idempotency-Key': `batch-status-${Date.now()}-${Math.random().toString(16).slice(2)}` }, body: JSON.stringify({ updates: selected.map((input) => ({ taskId: batchButton.dataset.batchTask, studentId: input.value, status: '已完成', expectedVersion: Number(input.dataset.taskVersion) })) }) }).then((result) => { toast(`已确认 ${result.updated || selected.length} 名学生成绩完成`); closeDetail(); loadAll(); }).catch((error) => toast(error.message, true));
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
  operationsPanel.id = 'operationsSection';
  operationsPanel.className = 'panel operations-panel';
  operationsPanel.innerHTML = '<div class="panel-head"><div><h3>统一待办中心</h3><p>先确认现场能否开测，再处理异常、补测、复核和数据治理事项</p></div><button class="panel-action" id="refreshOperationsBtn">查看全部待办</button></div><div id="fieldRuntimeSummary" class="field-runtime-summary"><div class="loading-skeleton">正在读取现场运行状态...</div></div><div class="operations-grid" id="operationsGrid"><div class="loading-skeleton">正在读取运营队列...</div></div>';
  const settingsSection = document.getElementById('settingsSection');
  settingsSection?.parentElement?.insertBefore(operationsPanel, settingsSection);
  const operationLabels = {
    completionAnomalies: ['完成异常', '状态已完成但成绩不齐或仍待复核', 'completionAnomalies', 'danger'],
    attentionFieldSessions: ['场地会话', '缺证据、中断或等待人工复核', 'fieldSessions', 'alert'],
    pendingRetests: ['待补测学生', '需要重新排队并再次完成正式采集', 'retests', 'alert'],
    openFieldSyncConflicts: ['同步冲突', '场地端与中央状态需要人工核对', 'syncConflicts', 'danger'],
    pendingReviews: ['人工录入复核', '非场地成绩需要教师或管理员核验', 'reviews', ''],
    pendingReports: ['待发布报告', '重点风险或数据不足报告尚未发布', 'reports', 'alert'],
    pendingActivities: ['活动报名', '等待运营确认', 'activities', ''],
    pendingAppointments: ['专家预约', '等待安排时间', 'appointments', ''],
    pendingCourseUploads: ['课程上传', '等待教师材料处理', 'courseUploads', ''],
    pendingSupportMessages: ['客服咨询', '等待服务人员回复', 'support', ''],
    pendingPrivacyRequests: ['隐私申请', '需要数据治理处理', 'privacy', ''],
    bodyAssessmentsLast30Days: ['家庭测评', '近 30 天已回写记录', '', ''],
    auditEventsLast24Hours: ['审计事件', '近 24 小时操作记录', '', '']
  };
  const renderOperations = (data) => {
    const grid = document.getElementById('operationsGrid');
    if (!grid) return;
    const runtimePanel = document.getElementById('fieldRuntimeSummary');
    const runtime = data?.fieldRuntime || {};
    if (runtimePanel) {
      const stateLabel = ({ ready: '可以开测', attention: '开测中 · 有积压', blocked: '设备检查未通过', offline: '设备全部离线', no_device: '尚未接入设备', no_queue: '尚未生成名单', no_task: '尚未发布任务' })[runtime.state] || '状态待确认';
      const runtimeAction = runtime.primaryAction || { target: 'queue', label: '打开现场运行' };
      const runtimeFocus = runtime.focusDevice || {};
      const runtimeTitle = runtimeFocus.name ? `优先处理：${runtimeFocus.name}${runtimeFocus.stationName ? ` · ${runtimeFocus.stationName}` : ''}` : '打开现场运行中心';
      runtimePanel.innerHTML = `<button class="field-runtime-card is-${escapeHtml(runtime.state || 'unknown')}" data-open-field-runtime data-field-runtime-target="${escapeHtml(runtimeAction.target || 'queue')}" data-field-runtime-device="${escapeHtml(runtimeFocus.id || '')}" title="${escapeHtml(runtimeTitle)}" type="button"><div class="field-runtime-copy"><span>当前现场任务</span><strong>${escapeHtml(stateLabel)}</strong><small>${escapeHtml(runtime.message || '打开现场运行中心查看任务、学生和设备。')}</small></div><div class="field-runtime-metrics"><span><b>${Number(runtime.onlineDevices || 0)}/${Number(runtime.totalDevices || 0)}</b>设备在线</span><span><b>${Number(runtime.readyDevices || 0)}</b>可开测</span><span><b>${Number(runtime.activeQueueCount || 0)}</b>任务队列</span><span><b>${Number(runtime.testingCount || 0)}</b>采集中</span></div><em>${escapeHtml(runtimeAction.label || '打开现场运行')} →</em></button>`;
    }
    const actionableKeys = Object.entries(operationLabels).filter(([, [, , filter]]) => Boolean(filter)).map(([key]) => key);
    const actionableTotal = actionableKeys.reduce((sum, key) => sum + Number(data?.[key] || 0), 0);
    const heroPending = document.getElementById('heroPending');
    if (heroPending) {
      heroPending.textContent = actionableTotal;
      heroPending.title = actionableTotal ? `统一待办中心共有 ${actionableTotal} 项需要处理` : '当前没有待处理事项';
    }
    const entries = Object.entries(operationLabels);
    const visibleEntries = entries.filter(([key, [, , filter]]) => !filter || Number(data?.[key] || 0) > 0);
    const zeroActionCount = entries.filter(([key, [, , filter]]) => filter && Number(data?.[key] || 0) === 0).length;
    grid.innerHTML = visibleEntries.map(([key, [label, hint, filter, tone]]) => {
      const content = `<strong>${Number(data?.[key] || 0)}</strong><span>${label}</span><small>${hint}</small>`;
      return filter ? `<button class="operation-card ${tone ? `is-${tone}` : ''}" data-operation-filter="${filter}" type="button">${content}</button>` : `<article class="operation-card">${content}</article>`;
    }).join('') + (zeroActionCount ? `<article class="operation-card is-clear"><strong>✓ 其余正常</strong><span>${zeroActionCount} 类待办为 0</span><small>无需现场或运营人员处理</small></article>` : '');
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
  const queueModal = makeModal('operationQueueModal', '统一待办', '现场异常会进入对应处理工作台，业务待办可在此直接确认。', '<div class="queue-filter"><select id="operationTypeFilter"><option value="all">全部待办</option><option value="completionAnomalies">完成异常</option><option value="fieldSessions">场地会话</option><option value="retests">待补测学生</option><option value="syncConflicts">同步冲突</option><option value="reviews">人工录入复核</option><option value="reports">待发布报告</option><option value="activities">活动报名</option><option value="appointments">专家预约</option><option value="courseUploads">课程上传</option><option value="support">客服咨询</option><option value="privacy">隐私申请</option></select></div><div id="operationQueueList" class="operation-queue-list">正在加载...</div>');
  const loadQueue = async () => {
    const list = document.getElementById('operationQueueList');
    try {
      const type = document.getElementById('operationTypeFilter')?.value || 'all';
      const items = await api(`/v1/admin/operations/items?schoolId=${encodeURIComponent(state.schoolId)}&type=${encodeURIComponent(type)}`);
      list.innerHTML = items.length ? items.map((item) => {
        const title = item.studentName || item.title || item.content || item.expertName || item.attachmentName || item.requestType || item.deviceName || '待处理';
        const time = escapeHtml(String(item.createdAt || '').slice(0, 16));
        const detail = item.type === 'completionAnomalies'
          ? `${item.className || ''} · ${item.taskTitle || ''} · ${Number(item.measuredItemCount || 0)}/${Number(item.requiredItemCount || 0)} 项成绩${Number(item.pendingReviewCount || 0) ? ` · ${Number(item.pendingReviewCount)} 项待复核` : ''}`
          : item.type === 'retests'
            ? `${item.className || ''} · ${item.taskTitle || ''} · ${item.stationCode || '待分配测试点'} · 第 ${Number(item.retestCount || 0) + 1} 次采集`
            : item.type === 'fieldSessions'
              ? `${item.className || ''} · ${item.taskTitle || ''} · ${item.recoveryEligible ? '设备中断待恢复' : fieldSessionStatus(item.status)} · ${Number(item.evidenceCount || 0)} 份有效证据`
              : item.type === 'syncConflicts'
                ? `${item.deviceName || item.deviceCode || '场地设备'} · ${item.stationCode || '未绑定测试点'} · ${item.message || '同步状态待核对'}`
                : item.type === 'reports'
                  ? `${item.className || ''} · ${{ high: '高风险', attention: '需要关注', unavailable: '数据不足' }[item.riskLevel] || item.riskLevel || '风险待核对'} · ${item.taskTitle || '诊断报告'}`
                : item.className || item.contactName || item.userName || item.preferredDate || item.taskTitle || '';
        const action = item.type === 'fieldSessions'
          ? `<button class="secondary-btn" data-operation-field-session="${escapeHtml(item.sessionId)}">查看证据并处理</button>`
          : item.type === 'retests'
            ? `<button class="secondary-btn" data-operation-retest-task="${escapeHtml(item.taskId)}">打开补测队列</button>`
            : item.type === 'completionAnomalies'
              ? `<button class="secondary-btn" data-operation-anomaly-task="${escapeHtml(item.taskId)}">核对任务成绩</button>`
              : item.type === 'syncConflicts'
                ? `<button class="secondary-btn" data-operation-sync-conflict="${escapeHtml(item.id)}">核对同步冲突</button>`
                : item.type === 'reports'
                  ? `<button class="secondary-btn" data-operation-report="${escapeHtml(item.id)}" data-operation-report-risk="${escapeHtml(item.riskLevel || 'all')}">打开报告中心</button>`
                : `<button class="secondary-btn" data-operation-type="${escapeHtml(item.type)}" data-operation-id="${escapeHtml(item.id)}">处理</button>`;
        return `<div class="queue-item"><div><strong>${escapeHtml(title)}</strong><small>${escapeHtml(detail)} · ${time}</small></div>${action}</div>`;
      }).join('') : '<div class="empty-chart">当前没有待处理事项</div>';
    } catch (error) { list.textContent = error.message; }
  };
  operationPanel?.querySelector('#refreshOperationsBtn')?.addEventListener('click', () => { queueModal.classList.remove('hidden'); loadQueue(); });
  document.addEventListener('click', (event) => {
    const card = event.target.closest('[data-operation-filter]');
    if (!card) return;
    document.getElementById('detailModal')?.classList.add('hidden');
    const select = document.getElementById('operationTypeFilter');
    if (select) select.value = card.dataset.operationFilter;
    queueModal.classList.remove('hidden');
    void loadQueue();
  });
  document.getElementById('operationTypeFilter')?.addEventListener('change', loadQueue);
  document.addEventListener('click', async (event) => {
    const fieldReview = event.target.closest('[data-operation-field-session]');
    if (fieldReview) {
      queueModal.classList.add('hidden'); fieldSessionFilter = 'attention'; fieldSessionPage = 1; fieldModal.classList.remove('hidden');
      const search = document.getElementById('fieldSessionSearch'); if (search) search.value = fieldReview.dataset.operationFieldSession;
      await loadFieldOperations();
      document.querySelector(`[data-field-session-id="${CSS.escape(fieldReview.dataset.operationFieldSession)}"]`)?.click();
      return;
    }
    const retest = event.target.closest('[data-operation-retest-task]');
    if (retest) {
      queueModal.classList.add('hidden'); fieldDispatchTaskId = retest.dataset.operationRetestTask; fieldQueueFilter = 'exception'; fieldModal.classList.remove('hidden');
      await loadFieldOperations(); document.getElementById('fieldQueueBoard')?.scrollIntoView({ behavior: 'smooth', block: 'start' }); return;
    }
    const anomaly = event.target.closest('[data-operation-anomaly-task]');
    if (anomaly) { queueModal.classList.add('hidden'); await window.adminOpenDetail?.('task', anomaly.dataset.operationAnomalyTask); return; }
    const syncConflict = event.target.closest('[data-operation-sync-conflict]');
    if (syncConflict) {
      queueModal.classList.add('hidden'); fieldSyncConflictFilter = 'open'; fieldModal.classList.remove('hidden');
      await loadFieldOperations(); document.getElementById('fieldSyncConflictBoard')?.scrollIntoView({ behavior: 'smooth', block: 'start' }); return;
    }
    const report = event.target.closest('[data-operation-report]');
    if (report) {
      queueModal.classList.add('hidden');
      const filter = document.getElementById('reportFilter');
      if (filter) { filter.value = report.dataset.operationReportRisk || 'all'; filter.dispatchEvent(new Event('change')); }
      document.getElementById('reportsSection')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      return;
    }
    const button = event.target.closest('[data-operation-type]');
    if (!button) return;
    const statusMap = { reviews: 'passed', activities: 'confirmed', appointments: 'confirmed', courseUploads: 'approved', support: 'resolved', privacy: 'completed' };
    const status = statusMap[button.dataset.operationType];
    if (!status || !window.confirm('确认将该事项标记为已处理？')) return;
    try {
      await api(`/v1/admin/operations/${encodeURIComponent(button.dataset.operationType)}/${encodeURIComponent(button.dataset.operationId)}/status`, { method: 'PATCH', headers: { 'Idempotency-Key': `operation-${Date.now()}` }, body: JSON.stringify({ status }) });
      toast('事项已处理'); loadQueue(); loadAll();
    } catch (error) { toast(error.message, true); }
  });

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
  const fieldModal = makeModal('fieldOperationsModal', '现场运行中心', '统一调度候测学生、测试点和 Windows 场地端。', `
    <div class="field-control-head">
      <div><span class="field-live-dot"></span><strong id="fieldOpsSummary">正在读取现场状态…</strong><small>打开中控时每 15 秒自动更新</small></div>
      <div class="field-control-actions"><button id="fieldOpsPrimaryAction" class="primary-btn" type="button" disabled>正在判断下一步</button><button id="fieldOpsRefresh" class="ghost-btn" type="button">刷新数据</button></div>
    </div>
    <div class="field-metric-grid" aria-label="场地核心指标">
      <article><span>测试点</span><strong id="fieldMetricStations">—</strong><small>已建立</small></article>
      <article><span>在线设备</span><strong id="fieldMetricDevices">—</strong><small>已连接 / 全部</small></article>
      <article><span>可开测设备</span><strong id="fieldMetricReady">—</strong><small>自检与标定通过</small></article>
      <article><span>待升级设备</span><strong id="fieldMetricUpdates">—</strong><small>低于当前发布版</small></article>
      <article><span>当前候测</span><strong id="fieldMetricQueue">—</strong><small id="fieldMetricQueueDetail">名学生</small></article>
      <article><span>待处理</span><strong id="fieldMetricReviews">—</strong><small>异常与复核会话</small></article>
    </div>
    <section class="field-issue-center"><div><strong>现场待处理</strong><span id="fieldIssueSummary">正在汇总设备、队列和采集异常</span></div><div id="fieldIssueChips" class="field-issue-chips"></div></section>
    <section class="field-runway" aria-label="开测流程">
      <article data-field-runway="task"><span>1</span><div><strong>选择任务</strong><small>加载中</small></div></article>
      <article data-field-runway="queue"><span>2</span><div><strong>候测名单</strong><small>加载中</small></div></article>
      <article data-field-runway="device"><span>3</span><div><strong>设备就绪</strong><small>加载中</small></div></article>
      <article data-field-runway="start"><span>4</span><div><strong>开始叫号</strong><small>加载中</small></div></article>
    </section>
    <section class="field-dispatch-bar">
      <div><label for="fieldDispatchTask">当前测评任务</label><select id="fieldDispatchTask" aria-label="选择待分流的测评任务"></select><span id="fieldDispatchHint">加载任务中</span></div>
      <button id="fieldRebalanceQueue" class="primary-btn" type="button">生成 / 重新分流</button>
    </section>
    <section class="field-protocol-route" aria-label="当前测试方案"><div class="field-protocol-copy"><span>COMPLETE LANE PROTOCOL</span><strong id="fieldProtocolName">等待选择测试方案</strong><small id="fieldProtocolMeta">一次签到 · 一名学生 · 固定顺序 · 一次提交</small></div><ol id="fieldProtocolItems"><li>加载七项完整通道…</li></ol></section>
    <section class="field-handoff" aria-label="测试点并行运行">
      <div class="field-handoff-head"><div><span class="field-board-kicker">LIVE STATION BOARD</span><strong>测试点并行运行</strong></div><small>每个测试点的采集、签到、叫号与下一位独立展示 · 15 秒同步</small></div>
      <div id="fieldHandoffList" class="field-handoff-list"><div class="field-empty">正在读取学生流转状态</div></div>
    </section>
    <div class="field-dashboard-grid">
      <section id="fieldQueueBoard" class="field-board field-queue-board">
        <div class="field-board-head"><div><span class="field-board-kicker">STUDENT FLOW</span><h3>候测队列</h3></div><span id="fieldQueueHint" class="field-count-badge">加载中</span></div>
        <div class="field-queue-tools"><div id="fieldQueueFilters" class="field-filter-tabs" aria-label="队列状态筛选"><button class="is-active" data-field-queue-filter="active" type="button">现场中 <b>0</b></button><button data-field-queue-filter="timing" type="button">时间超时 <b>0</b></button><button data-field-queue-filter="exception" type="button">异常 / 补测 <b>0</b></button><button data-field-queue-filter="completed" type="button">已完成 <b>0</b></button><button data-field-queue-filter="all" type="button">全部 <b>0</b></button></div><div class="field-queue-query"><select id="fieldQueueStationFilter" aria-label="按测试点筛选学生"><option value="all">全部测试点</option><option value="__unassigned__">待分配学生</option></select><input id="fieldQueueSearch" type="search" aria-label="搜索候测学生" placeholder="搜索学生、班级或学籍号"></div></div>
        <div class="field-queue-columns"><span>学生</span><span>分配测试点</span><span>状态</span><span>调度</span></div>
        <div id="fieldQueueList" class="field-queue-list"></div>
      </section>
      <aside class="field-side-stack">
        <section id="fieldStationBoard" class="field-board"><div class="field-board-head"><div><span class="field-board-kicker">STATIONS</span><h3>测试点</h3></div></div><div id="fieldStationList" class="field-ops-list"></div></section>
        <section id="fieldDeviceBoard" class="field-board"><div class="field-board-head"><div><span class="field-board-kicker">DEVICES</span><h3>场地设备</h3></div><label class="field-device-archive-toggle"><input id="fieldShowDisabledDevices" type="checkbox">显示已停用</label></div><div id="fieldDeviceList" class="field-ops-list field-device-list"></div></section>
      </aside>
    </div>
    <section id="fieldSessionBoard" class="field-board field-session-board"><div class="field-board-head"><div><span class="field-board-kicker">RECENT SESSIONS</span><h3>最近采集记录</h3></div><span id="fieldSessionHint" class="field-count-badge">加载中</span></div><div class="field-session-tools"><div id="fieldSessionFilters" class="field-filter-tabs" aria-label="采集会话筛选"><button class="is-active" data-field-session-filter="attention" type="button">待处理 <b>0</b></button><button data-field-session-filter="active" type="button">进行中 <b>0</b></button><button data-field-session-filter="completed" type="button">已完成 <b>0</b></button><button data-field-session-filter="all" type="button">全部 <b>0</b></button></div><input id="fieldSessionSearch" type="search" aria-label="搜索采集会话" placeholder="搜索学生、学籍号、任务、测试点或设备"></div><div id="fieldSessionList" class="field-session-list"></div><div id="fieldSessionPager" class="field-session-pager"></div></section>
    <section id="fieldSyncConflictBoard" class="field-board field-sync-conflict-board"><div class="field-board-head"><div><span class="field-board-kicker">SYNC EXCEPTIONS</span><h3>同步冲突工作台</h3></div><span id="fieldSyncConflictHint" class="field-count-badge">加载中</span></div><div id="fieldSyncConflictFilters" class="field-filter-tabs field-conflict-filters"><button class="is-active" data-field-conflict-filter="open" type="button">待核对 <b>0</b></button><button data-field-conflict-filter="resolved" type="button">已处理 <b>0</b></button><button data-field-conflict-filter="all" type="button">全部 <b>0</b></button></div><div id="fieldSyncConflictList" class="field-sync-conflict-list"></div></section>
    <details class="field-config-panel">
      <summary><span><strong>部署与设备配置</strong><small>仅首次建场、新增设备或重新标定时使用</small></span><b>展开配置</b></summary>
      <div class="field-setup-grid">
        <section class="field-setup-card"><div class="field-step">01</div><h3>建立测试点</h3><p>“整套任务通道”完成任务中的全部项目；单项通道只承接同项目的单项任务。</p><div class="hard-form-grid"><div class="field"><label for="fieldStationCode">测试点编码</label><input id="fieldStationCode" placeholder="A-01"></div><div class="field"><label for="fieldStationName">测试点名称</label><input id="fieldStationName" placeholder="A 区综合测试通道"></div><div class="field full"><label for="fieldStationItem">测试能力</label><select id="fieldStationItem"><option value="">整套任务通道（推荐）</option><option>连续双脚障碍跳</option><option>侧向滑步</option><option>倒退平衡</option><option>接球-上手掷准</option><option>手运球绕杆</option><option>脚运球变向</option><option>定点踢准</option></select><span class="hint">当前场地端是一人一次完成一个任务；多项目任务必须使用整套任务通道。</span></div><div class="field"><label for="fieldStationCapacity">队列容量</label><input id="fieldStationCapacity" type="number" value="20" min="1" max="500"></div><div class="field full"><button id="createFieldStation" type="button" class="secondary-btn">创建测试点</button></div></div></section>
        <section class="field-setup-card"><div class="field-step">02</div><h3>安装并绑定 Windows 场地端</h3><p>先下载自包含客户端，再注册设备并填写一次性接入信息。正式采集还需项目交付方提供的厂商适配器 DLL。</p><div id="fieldClientRelease" class="field-client-release"><div><strong>Windows 10/11 · 64 位</strong><span id="fieldClientReleaseMeta">正在检查安装包…</span></div><a id="fieldClientDownload" class="secondary-btn is-disabled" aria-disabled="true">安装包准备中</a><small id="fieldClientChecksum">无需安装 .NET SDK，也不要运行 .ps1；安装包不包含厂商硬件 DLL</small></div><div class="hard-form-grid"><div class="field full"><label for="fieldDeviceStation">绑定测试点</label><select id="fieldDeviceStation"></select></div><div class="field"><label for="fieldDeviceCode">设备编码</label><input id="fieldDeviceCode" placeholder="EDGE-A-01"></div><div class="field"><label for="fieldDeviceName">设备名称</label><input id="fieldDeviceName" placeholder="A 区采集主机"></div><div class="field full"><label for="fieldDeviceVersion">软件版本</label><input id="fieldDeviceVersion" value="field-client/0.4.27"></div><div class="field full"><button id="createFieldDevice" type="button" class="primary-btn">注册并显示接入信息</button><div id="fieldDeviceKeyNotice" class="field-key-notice hidden"></div></div></div></section>
        <section class="field-setup-card"><div class="field-step">03</div><h3>下发场地标定</h3><p>正式采集前必须激活并通过标定。</p><div class="hard-form-grid"><div class="field"><label for="fieldCalibrationStation">测试点</label><select id="fieldCalibrationStation"></select></div><div class="field"><label for="fieldCalibrationVersion">标定版本</label><input id="fieldCalibrationVersion" placeholder="CAL-2026-09-A01"></div><div class="field full"><label for="fieldCalibrationChecksum">SHA-256 校验值</label><input id="fieldCalibrationChecksum" maxlength="64" placeholder="64 位十六进制校验值"></div><div class="field full"><label for="fieldCalibrationConfig">标定配置 JSON</label><textarea id="fieldCalibrationConfig" rows="3" placeholder='例如 {"cameraHeightCm":130,"captureZone":"2m x 3m"}'></textarea></div><div class="field full"><button id="createFieldCalibration" type="button" class="secondary-btn">下发并激活标定</button></div></div></section>
      </div>
    </details>`);
  fieldModal.querySelector('.modal')?.classList.add('field-control-modal');
  const fieldAssignmentModal = makeModal('fieldAssignmentModal', '调整学生测试点', '仅候测或待重测学生可调整；目标测试点必须已通过开测检查且仍有容量。', `
    <div id="fieldAssignmentStudent" class="field-assignment-student"></div>
    <div class="hard-form-grid">
      <div class="field full"><label for="fieldAssignmentStation">目标测试点</label><select id="fieldAssignmentStation"></select><span id="fieldAssignmentCapacity" class="hint"></span></div>
      <div class="field full"><label for="fieldAssignmentReason">换点原因</label><input id="fieldAssignmentReason" maxlength="500" placeholder="例如：原测试点设备故障，转至 B-01"></div>
    </div>
    <div class="modal-footer"><button id="cancelFieldAssignment" class="ghost-btn" type="button">取消</button><button id="confirmFieldAssignment" class="primary-btn" type="button">确认换点</button></div>`);
  fieldAssignmentModal.querySelector('.modal')?.classList.add('field-assignment-modal');
  const fieldIdentityModal = makeModal('fieldIdentityModal', '学生身份核验', '签到前必须当面核对本人、现场名册或腕带信息，后台将记录本次明确确认。', `
    <div class="field-identity-grid">
      <div><span>姓名</span><strong id="fieldIdentityName">—</strong></div>
      <div><span>班级</span><strong id="fieldIdentityClass">—</strong></div>
      <div><span>学籍号</span><strong id="fieldIdentityStudentNo">—</strong></div>
      <div><span>性别</span><strong id="fieldIdentityGender">—</strong></div>
      <div class="full"><span>出生日期</span><strong id="fieldIdentityBirthDate">—</strong></div>
    </div>
    <div class="field-identity-warning"><strong>核对要求</strong><span>仅在学生本人、姓名、班级和学籍信息一致时确认；信息不一致请取消并检查学校名册。</span></div>
    <div class="modal-footer"><button id="cancelFieldIdentity" class="ghost-btn" type="button">取消</button><button id="confirmFieldIdentity" class="primary-btn" type="button">身份一致，确认签到</button></div>`);
  fieldIdentityModal.querySelector('.modal')?.classList.add('field-identity-modal');
  const fieldQueueDecisionModal = makeModal('fieldQueueDecisionModal', '确认队列处置', '缺席、跳过、取消或补测会改变学生当前现场流程，必须确认影响并留下可追溯原因。', `
    <div id="fieldQueueDecisionStudent" class="field-assignment-student"></div>
    <div id="fieldQueueDecisionImpact" class="field-queue-decision-impact"></div>
    <div class="hard-form-grid"><div class="field full"><label for="fieldQueueDecisionReason">处理原因</label><textarea id="fieldQueueDecisionReason" maxlength="500" rows="3" placeholder="请填写现场事实，例如：再次呼叫两次仍未到场"></textarea><span class="hint">必填；将写入队列事件和审计记录。</span></div></div>
    <div class="modal-footer"><button id="cancelFieldQueueDecision" class="ghost-btn" type="button">取消</button><button id="confirmFieldQueueDecision" class="primary-btn" type="button">确认处置</button></div>`);
  fieldQueueDecisionModal.querySelector('.modal')?.classList.add('field-queue-decision-modal');
  const fieldQueueHistoryModal = makeModal('fieldQueueHistoryModal', '学生现场记录', '按时间查看队列流转、处置原因和采集尝试，便于现场交接与问题追溯。', '<div id="fieldQueueHistoryBody">正在读取现场记录…</div>');
  fieldQueueHistoryModal.querySelector('.modal')?.classList.add('field-queue-history-modal');
  const fieldDeviceDetailModal = makeModal('fieldDeviceDetailModal', '设备详情', '集中查看连接、版本、开测检查与设备控制；高风险操作不会出现在日常设备卡片上。', '<div id="fieldDeviceDetailBody">正在读取设备状态...</div>');
  fieldDeviceDetailModal.querySelector('.modal')?.classList.add('field-device-detail-modal');
  const fieldStationEditModal = makeModal('fieldStationEditModal', '编辑测试点', '名称和编码会同步显示到后台与场地端；运行中的测试能力和容量受现场安全规则保护。', `
    <div class="hard-form-grid field-maintenance-form">
      <div class="field"><label for="fieldEditStationCode">测试点编码</label><input id="fieldEditStationCode" maxlength="64" autocomplete="off"></div>
      <div class="field"><label for="fieldEditStationName">测试点名称</label><input id="fieldEditStationName" maxlength="120" autocomplete="off"></div>
      <div class="field"><label for="fieldEditStationCapacity">队列容量</label><input id="fieldEditStationCapacity" type="number" min="1" max="500"></div>
      <div class="field"><label for="fieldEditStationItem">测试能力</label><select id="fieldEditStationItem"></select></div>
      <div class="field full"><label for="fieldEditStationStatus">运行状态</label><select id="fieldEditStationStatus"></select><span id="fieldEditStationStatusHint" class="hint"></span></div>
      <div id="fieldEditStationReasonField" class="field full hidden"><label for="fieldEditStationReason">状态变更原因</label><textarea id="fieldEditStationReason" maxlength="500" rows="2" placeholder="例如：相机维护，预计 15:30 恢复"></textarea><span class="hint">状态改变时必填，将写入审计记录。停用前必须先清空本站现场队列。</span></div>
      <div class="field full"><span class="hint">有学生已叫号、签到、测试中或暂停时，测试能力不能修改；容量不能低于当前现场人数。临时停测请选择“暂停”或“维护”，不要直接停用。</span></div>
    </div>
    <div class="modal-footer"><button id="cancelFieldStationEdit" class="ghost-btn" type="button">取消</button><button id="saveFieldStationEdit" class="primary-btn" type="button">保存测试点</button></div>`);
  fieldStationEditModal.querySelector('.modal')?.classList.add('field-maintenance-modal');
  let fieldStations = [];
  let pendingFieldRuntimeTarget = null;
  let pendingFieldRuntimeDeviceId = null;
  let fieldStationEditId = null;
  let fieldSelectedTask = null;
  let fieldTaskPlanningStationCount = 0;
  let fieldTaskReadyStationCount = 0;
  let fieldDispatchTaskId = '';
  let fieldOperationsLoading = false;
  let fieldOperationsReloadPending = false;
  let fieldRefreshTimer = null;
  let fieldQueueItems = [];
  let fieldQueueFilter = 'active';
  let fieldQueueStationId = 'all';
  let fieldDeviceItems = [];
  let fieldSessionItems = [];
  let fieldSessionFilter = 'attention';
  let fieldSessionPage = 1;
  let fieldSessionPageSize = 20;
  let fieldSessionTotal = 0;
  let fieldSessionCounts = { attention: 0, active: 0, completed: 0, all: 0 };
  let fieldSessionSearchTimer = null;
  let fieldSyncConflictItems = [];
  let fieldSyncConflictFilter = 'open';
  let fieldSyncConflictCounts = { open: 0, resolved: 0, all: 0 };
  let fieldAssignmentItem = null;
  let fieldIdentityQueueAction = null;
  let fieldQueueDecisionAction = null;
  let fieldDeviceDetailId = null;
  let fieldClientReleaseInfo = null;
  document.addEventListener('click', (event) => {
    const runtimeButton = event.target.closest('[data-open-field-runtime]');
    if (!runtimeButton) return;
    pendingFieldRuntimeTarget = runtimeButton.dataset.fieldRuntimeTarget || 'queue';
    pendingFieldRuntimeDeviceId = runtimeButton.dataset.fieldRuntimeDevice || '';
    fieldButton.click();
  });
  const submitFieldQueueTransition = async (queueAction, identityVerified = false, reason = '') => {
    const status = queueAction.dataset.fieldQueueStatus;
    const studentName = queueAction.dataset.fieldQueueStudent || '该学生';
    const needsReason = ['absent', 'skipped', 'cancelled', 'retest'].includes(status);
    const note = String(reason || '').trim();
    if (needsReason && !note) { toast('请填写处理原因，便于现场追溯', true); return; }
    queueAction.disabled = true;
    try {
      await api(`/v1/admin/test-queues/${encodeURIComponent(queueAction.dataset.fieldQueueId)}/transition`, {
        method: 'POST',
        body: JSON.stringify({ status, expectedVersion: Number(queueAction.dataset.fieldQueueVersion), identityVerified, note, reason: note })
      });
      toast(`${studentName}：${({ called: '已叫号', checked_in: '已签到', waiting: '已恢复候测', absent: '已标记缺席', skipped: '已跳过', paused: '已暂停', retest: '已安排补测', cancelled: '已取消补测' })[status] || '状态已更新'}`);
      await loadFieldOperations();
    } catch (error) { toast(error.message, true); queueAction.disabled = false; }
  };
  const fieldFileSize = (bytes) => bytes >= 1024 * 1024 ? `${(bytes / 1024 / 1024).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;
  const loadFieldClientRelease = async () => {
    const download = document.getElementById('fieldClientDownload');
    const meta = document.getElementById('fieldClientReleaseMeta');
    const checksum = document.getElementById('fieldClientChecksum');
    try {
      const response = await fetch('/v1/public/field-client-release', { headers: { Accept: 'application/json' } });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.message || '安装包状态读取失败');
      fieldClientReleaseInfo = payload.data;
      if (!fieldClientReleaseInfo?.available) throw new Error('服务器尚未生成安装包');
      download.href = fieldClientReleaseInfo.downloadUrl;
      download.setAttribute('download', '');
      download.removeAttribute('aria-disabled');
      download.classList.remove('is-disabled');
      download.textContent = '下载 Windows 客户端';
      meta.textContent = `v${fieldClientReleaseInfo.version} · ${fieldFileSize(fieldClientReleaseInfo.sizeBytes)} · 自包含版`;
      checksum.textContent = `SHA-256 ${fieldClientReleaseInfo.sha256} · 当前为内部未签名验收包`;
      document.getElementById('fieldDeviceVersion').value = `field-client/${fieldClientReleaseInfo.version}`;
      renderFieldDevices();
      renderFieldIssues();
      document.getElementById('fieldMetricUpdates').textContent = fieldOutdatedDeviceCount();
    } catch (error) {
      fieldClientReleaseInfo = null;
      download.removeAttribute('href');
      download.removeAttribute('download');
      download.setAttribute('aria-disabled', 'true');
      download.classList.add('is-disabled');
      download.textContent = '安装包尚未生成';
      meta.textContent = error.message || '安装包不可用';
      checksum.textContent = '请由发布人员运行 field-client/package-windows.sh；现场电脑无需运行脚本';
    }
  };
  const fieldNow = (value) => value ? new Date(value).toLocaleString('zh-CN', { hour12: false }) : '从未连接';
  const fieldSessionStatus = (status) => ({ created: '已创建', checked_in: '已签到', testing: '采集中', completed: '已完成', needs_review: '待复核', retest: '待重测', cancelled: '已取消', aborted: '已中止', sync_conflict: '同步冲突' })[status] || status || '未知状态';
  const fieldEvidenceType = (type) => ({ video: '视频', image: '图像', skeleton: '骨架数据', timeline: '动作时间线', calibration: '标定记录', log: '设备日志', other: '其他证据' })[type] || type || '证据';
  const fieldEventType = (type) => ({ 'capture.started': '开始采集', 'capture.stopped': '结束采集', 'capture.frame': '采集帧', 'capture.warning': '设备告警', 'capture.completed': '设备完成' })[type] || type || '采集事件';
  const selectFieldPrimaryAction = window.XiangshangFieldOperationsPolicy.selectPrimaryAction;
  const fieldCopyText = async (value) => {
    if (window.isSecureContext && navigator.clipboard?.writeText) {
      try { await navigator.clipboard.writeText(value); return; } catch { }
    }
    const textarea = document.createElement('textarea');
    textarea.value = value;
    textarea.setAttribute('readonly', '');
    textarea.style.cssText = 'position:fixed;left:-9999px;top:0;opacity:0';
    document.body.appendChild(textarea);
    textarea.select();
    textarea.setSelectionRange(0, value.length);
    const copied = document.execCommand('copy');
    textarea.remove();
    if (!copied) throw new Error('clipboard unavailable');
  };
  const showFieldDeviceCredentials = (result, rotated = false, targetId = 'fieldDeviceKeyNotice') => {
    const notice = document.getElementById(targetId);
    if (!notice) return;
    const marker = `field-credential-${Date.now()}`;
    const currentOrigin = window.location.origin;
    const localAddressWarning = /^(localhost|127\.0\.0\.1)$/i.test(window.location.hostname)
      ? '如果 Windows 场地端不在服务器这台电脑上，请把 localhost 改为服务器的局域网 IP。'
      : 'Windows 场地端应使用能从现场电脑访问的这个地址。';
    notice.classList.remove('hidden');
    notice.innerHTML = `<div class="field-key-title"><strong>${rotated ? '新密钥已生成，旧密钥立即失效' : 'Windows 场地端接入信息'}</strong><span>仅本次显示</span></div><div class="field-credential-row"><span>服务器地址</span><code id="${marker}-url">${escapeHtml(currentOrigin)}</code><button class="ghost-btn" data-field-copy-target="${marker}-url" type="button">复制</button></div><div class="field-credential-row"><span>设备 ID</span><code id="${marker}-id">${escapeHtml(result.id)}</code><button class="ghost-btn" data-field-copy-target="${marker}-id" type="button">复制</button></div><div class="field-credential-row"><span>设备密钥</span><code id="${marker}-key">${escapeHtml(result.deviceKey)}</code><button class="ghost-btn" data-field-copy-target="${marker}-key" type="button">复制</button></div><button class="secondary-btn field-connection-bundle" data-field-copy-connection="${marker}" type="button">一次复制三项接入信息（含密钥）</button><small class="field-connection-bundle-hint">复制后在 Windows 客户端点击“从剪贴板粘贴”；保存成功会自动清除匹配的剪贴板内容。</small><p>${escapeHtml(localAddressWarning)}</p><ol><li>${fieldClientReleaseInfo?.available ? '<a href="' + escapeHtml(fieldClientReleaseInfo.downloadUrl) + '" download>下载客户端</a>，解压到固定目录' : '先下载并解压 Windows 客户端'}</li><li>双击 FieldClient.Windows.exe，不要运行 .ps1</li><li>点击“一次复制三项接入信息”</li><li>在“连接场地端”中点击“从剪贴板粘贴”，再点击“测试并保存”</li><li>正式开测前，将项目交付方提供的厂商目录复制到“采集适配器”，再点击右侧开测条件中的“接入采集设备”选择 DLL</li></ol>`;
  };
  const showFieldDeviceGuide = (deviceId, deviceCode) => {
    const notice = document.getElementById('fieldDeviceKeyNotice');
    const marker = `field-guide-${Date.now()}`;
    const currentOrigin = window.location.origin;
    const localAddressWarning = /^(localhost|127\.0\.0\.1)$/i.test(window.location.hostname)
      ? '当前页面地址是 localhost。若 Windows 场地端在另一台电脑上，请改填服务器的局域网 IP，例如 http://192.168.x.x:8080。'
      : '请确认 Windows 场地端能够访问这个服务器地址。';
    notice.classList.remove('hidden');
    notice.innerHTML = `<div class="field-key-title"><strong>${escapeHtml(deviceCode)} · Windows 接入指南</strong><span>可随时查看</span></div><div class="field-credential-row"><span>服务器地址</span><code id="${marker}-url">${escapeHtml(currentOrigin)}</code><button class="ghost-btn" data-field-copy-target="${marker}-url" type="button">复制</button></div><div class="field-credential-row"><span>设备 ID</span><code id="${marker}-id">${escapeHtml(deviceId)}</code><button class="ghost-btn" data-field-copy-target="${marker}-id" type="button">复制</button></div><div class="field-credential-row"><span>设备密钥</span><code>为安全起见不可再次查看</code><span></span></div><p><strong>${escapeHtml(localAddressWarning)}</strong></p><p>${fieldClientReleaseInfo?.available ? `<a href="${escapeHtml(fieldClientReleaseInfo.downloadUrl)}" download>下载 Windows 自包含客户端</a>，解压后双击 FieldClient.Windows.exe；` : '解压客户端后双击 FieldClient.Windows.exe；'}不要运行 .ps1，也不需要安装 SDK。先点击“检查中央连接”填写服务器地址和设备 ID；再将项目交付方提供的厂商完整目录复制到“采集适配器”，点击右侧开测条件中的“接入采集设备”选择 DLL 并测试保存。安装包默认不包含硬件 DLL。若密钥没有保存，请点击该设备的“轮换密钥”生成新密钥；旧密钥会立即失效。</p>`;
    document.querySelector('details.field-config-panel')?.setAttribute('open', '');
    notice.scrollIntoView({ behavior: 'smooth', block: 'center' });
  };
  const fieldRelativeHeartbeat = (value) => {
    if (!value) return '从未连接';
    const elapsed = Date.now() - new Date(value).getTime();
    if (!Number.isFinite(elapsed) || elapsed < 0) return fieldNow(value);
    if (elapsed < 60_000) return '刚刚';
    if (elapsed < 3_600_000) return `${Math.floor(elapsed / 60_000)} 分钟前`;
    if (elapsed < 86_400_000) return `${Math.floor(elapsed / 3_600_000)} 小时前`;
    return `${Math.floor(elapsed / 86_400_000)} 天前`;
  };
  const fieldMovementItems = ['连续双脚障碍跳', '侧向滑步', '倒退平衡', '接球-上手掷准', '手运球绕杆', '脚运球变向', '定点踢准'];
  const fieldStationProfile = (station) => !station?.itemCode
    ? { compatible: true, label: '整套任务通道' }
    : !fieldMovementItems.includes(station.itemCode)
      ? { compatible: false, label: `旧配置：${station.itemCode}` }
      : { compatible: Array.isArray(fieldSelectedTask?.items) && fieldSelectedTask.items.length === 1 && fieldSelectedTask.items[0] === station.itemCode, label: `单项通道 · ${station.itemCode}` };
  const fieldStationProfileOptions = (selected) => [{ value: '', label: '整套任务通道' }, ...fieldMovementItems.map((value) => ({ value, label: `单项 · ${value}` }))]
    .map((option) => `<option value="${escapeHtml(option.value)}" ${option.value === (selected || '') ? 'selected' : ''}>${escapeHtml(option.label)}</option>`).join('');
  const fieldStationStatusOptions = (station) => [
    ...(station?.status === 'online' ? [{ value: 'online', label: '在线（由设备心跳保持）' }] : []),
    { value: 'offline', label: station?.status === 'online' ? '设为离线等待重连' : '恢复待连接（心跳后自动在线）' },
    { value: 'paused', label: '暂停现场操作' },
    { value: 'maintenance', label: '进入设备维护' },
    { value: 'disabled', label: '停用测试点' }
  ].map((option) => `<option value="${option.value}" ${option.value === station?.status ? 'selected' : ''}>${option.label}</option>`).join('');
  const fieldStationStatusHint = (status) => ({
    online: '设备心跳正常；若临时停测请选择暂停或维护。',
    offline: '等待边缘主机下一次有效心跳后自动恢复在线。',
    paused: '保留设备和队列，禁止新叫号与采集；恢复时改为“恢复待连接”。',
    maintenance: '用于检修相机、网络或采集主机；恢复时改为“恢复待连接”。',
    disabled: '用于退役空测试点；存在现场学生时后台会拒绝停用。'
  }[status] || '请选择测试点运行状态。');
  const queueStatusLabels = { waiting: '候测', called: '已叫号', checked_in: '已签到', testing: '测试中', completed: '已完成', absent: '缺席', skipped: '已跳过', paused: '已暂停', retest: '待重测', cancelled: '已取消' };
  const fieldActiveQueueStatuses = ['waiting', 'called', 'checked_in', 'testing', 'retest', 'paused'];
  const fieldQueueAgeMinutes = (item) => Math.max(0, Math.floor(Number(item?.stateAgeSeconds || 0) / 60));
  const fieldQueueTimingSeverity = (item) => ['normal', 'warning', 'critical'].includes(item?.timingSeverity)
    ? item.timingSeverity
    : item?.calledOverdue === true || ['waiting', 'retest'].includes(item?.status) && Number(item?.stateAgeSeconds || 0) >= 30 * 60
      ? 'critical'
      : ['waiting', 'retest'].includes(item?.status) && Number(item?.stateAgeSeconds || 0) >= 15 * 60 ? 'warning' : 'normal';
  const fieldQueueLongWaiting = (item) => ['warning', 'critical'].includes(fieldQueueTimingSeverity(item)) && ['waiting', 'retest'].includes(item?.status);
  const fieldQueueTimingOverdue = (item) => ['warning', 'critical'].includes(fieldQueueTimingSeverity(item));
  const fieldQueueOperationalPriority = (item) => {
    const severity = fieldQueueTimingSeverity(item);
    if (item?.status === 'testing') return 0;
    if (item?.status === 'checked_in') return 10;
    if (item?.status === 'called') return severity === 'critical' ? 20 : 30;
    if (item?.status === 'retest') return severity === 'critical' ? 40 : severity === 'warning' ? 60 : 80;
    if (item?.status === 'waiting') return severity === 'critical' ? 50 : severity === 'warning' ? 70 : 90;
    return 100;
  };
  const fieldQueueTimingLabel = (item) => {
    const minutes = fieldQueueAgeMinutes(item);
    const duration = minutes < 1 ? '不到 1 分钟' : `${minutes} 分钟`;
    if (item?.status === 'called') return fieldQueueTimingSeverity(item) === 'critical' ? `叫号后 ${duration} · 到场超时` : `叫号后 ${duration}`;
    if (item?.status === 'checked_in') return `签到后 ${duration}`;
    if (item?.status === 'testing') return `采集 ${duration}`;
    if (item?.status === 'retest') return fieldQueueTimingSeverity(item) === 'critical' ? `补测候测 ${duration} · 严重积压` : fieldQueueLongWaiting(item) ? `补测候测 ${duration} · 等待过久` : `补测候测 ${duration}`;
    if (item?.status === 'waiting') return fieldQueueTimingSeverity(item) === 'critical' ? `候测 ${duration} · 严重积压` : fieldQueueLongWaiting(item) ? `候测 ${duration} · 等待过久` : `候测 ${duration}`;
    return `${queueStatusLabels[item?.status] || item?.status || '状态待确认'} ${duration}`;
  };
  const fieldCaptureProgress = (item) => {
    if (item?.status !== 'testing' || !item?.activeSessionId) return null;
    const payload = item.latestCapturePayload && typeof item.latestCapturePayload === 'object' && !Array.isArray(item.latestCapturePayload) ? item.latestCapturePayload : {};
    const text = (...keys) => keys.map((key) => typeof payload[key] === 'string' ? payload[key].trim() : '').find(Boolean) || '';
    const context = text('item', 'itemName', 'movement', 'exercise', 'phase', 'stage');
    const type = String(item.latestCaptureEventType || '').toLowerCase();
    const label = ({
      'capture.started': '采集已开始', 'session.started': '采集已开始', 'capture.ready': '学生已就位', 'subject.ready': '学生已就位',
      'item.started': '项目开始', 'movement.started': '项目开始', 'exercise.started': '项目开始',
      'item.completed': '项目完成', 'movement.completed': '项目完成', 'exercise.completed': '项目完成',
      'rep.detected': '识别到有效动作', 'repetition.detected': '识别到有效动作',
      'quality.warning': '采集质量提醒', 'capture.warning': '采集质量提醒', 'quality.recovered': '采集质量已恢复',
      'capture.completed': '设备采集完成', 'session.completed': '设备采集完成'
    })[type] || (type.includes('warning') || type.includes('error') ? '设备反馈需关注' : item.captureEventCount ? '设备正在反馈' : '等待设备首条反馈');
    const count = Number(item.captureEventCount || 0);
    return { title: context ? `${context} · ${label}` : label, meta: `${count} 条设备事件${item.lastCaptureEventAt ? ` · 最近 ${fieldNow(item.lastCaptureEventAt)}` : ''}` };
  };
  const fieldParallelLane = (label, tone, items, empty, waitingRemainder = 0) => `<section class="field-parallel-lane is-${tone}"><header><span>${escapeHtml(label)}</span><b>${items.length + waitingRemainder}</b></header><div>${items.length ? items.map((entry) => {
    const capture = fieldCaptureProgress(entry);
    return `<button data-field-handoff-student="${escapeHtml(entry.id)}" type="button"><strong>${escapeHtml(entry.studentName)}</strong><small>${escapeHtml(entry.className || '班级待补')} · ${escapeHtml(capture?.title || fieldQueueTimingLabel(entry))}</small></button>`;
  }).join('') : `<p>${escapeHtml(empty)}</p>`}${waitingRemainder ? `<em>另有 ${waitingRemainder} 人在本站候测，可进入本站队列查看</em>` : ''}</div></section>`;
  const renderFieldParallelBoard = () => {
    const board = document.getElementById('fieldHandoffList');
    if (!board) return;
    const stationRows = fieldStations.map((station) => {
      const queue = fieldQueueItems.filter((entry) => entry.stationId === station.id && fieldActiveQueueStatuses.includes(entry.status))
        .sort((left, right) => fieldQueueOperationalPriority(left) - fieldQueueOperationalPriority(right) || Number(left.queueOrder || 0) - Number(right.queueOrder || 0));
      const testing = queue.filter((entry) => entry.status === 'testing');
      const checkedIn = queue.filter((entry) => entry.status === 'checked_in');
      const called = queue.filter((entry) => entry.status === 'called');
      const waiting = queue.filter((entry) => entry.status === 'retest' || entry.status === 'waiting');
      const devices = fieldDeviceItems.filter((device) => device.stationId === station.id && device.status !== 'disabled');
      const readyDevices = devices.filter((device) => device.readiness?.ready);
      const onlineDevices = devices.filter((device) => device.status === 'online');
      const critical = queue.filter((entry) => fieldQueueTimingSeverity(entry) === 'critical').length;
      const warning = queue.filter((entry) => fieldQueueTimingSeverity(entry) === 'warning').length;
      const capacity = Number(station.queueCapacity || 0);
      const congestion = critical || capacity > 0 && queue.length / capacity >= .9 ? 'critical' : warning || capacity > 0 && queue.length / capacity >= .7 ? 'warning' : 'normal';
      const stationState = readyDevices.length ? '可开测' : onlineDevices.length ? '检查未通过' : devices.length ? '设备离线' : '未绑定设备';
      return `<article class="field-parallel-station is-${congestion}" data-field-parallel-station="${escapeHtml(station.id)}"><header><div><strong>${escapeHtml(station.stationCode)} · ${escapeHtml(station.name)}</strong><small>${escapeHtml(fieldStationProfile(station).label)} · ${queue.length}/${capacity || '—'} 人 · ${onlineDevices.length}/${devices.length} 台在线</small></div><span class="status ${readyDevices.length ? 'done' : onlineDevices.length ? 'review' : 'gray'}">${escapeHtml(stationState)}</span><button class="ghost-btn" data-field-station-focus="${escapeHtml(station.id)}" type="button">查看本站队列</button></header><div class="field-parallel-lanes">${fieldParallelLane('正在采集', 'testing', testing, '当前无人采集')}${fieldParallelLane('已签到待开测', 'checked', checkedIn, '当前无人待开测')}${fieldParallelLane('已叫号待到场', 'called', called, '当前无人等待签到')}${fieldParallelLane('下一位候测', 'waiting', waiting.slice(0, 1), '本站候测队列已空', Math.max(0, waiting.length - 1))}</div></article>`;
    });
    const unassigned = fieldQueueItems.filter((entry) => !entry.stationId && fieldActiveQueueStatuses.includes(entry.status));
    if (unassigned.length) stationRows.push(`<article class="field-parallel-station is-unassigned" data-field-parallel-station="unassigned"><header><div><strong>待分配学生</strong><small>${unassigned.length} 人尚未进入测试点，请先生成或重新分流</small></div><span class="status attention">需调度</span><button class="ghost-btn" data-field-station-focus="__unassigned__" type="button">查看待分配</button></header><div class="field-unassigned-students">${unassigned.map((entry) => `<button data-field-handoff-student="${escapeHtml(entry.id)}" type="button"><strong>${escapeHtml(entry.studentName)}</strong><small>${escapeHtml(entry.className || '班级待补')} · ${escapeHtml(fieldQueueTimingLabel(entry))}</small></button>`).join('')}</div></article>`);
    board.innerHTML = stationRows.length ? stationRows.join('') : '<div class="field-empty"><strong>尚未建立测试点</strong><span>先在下方部署配置中创建测试点，再生成候测名单。</span></div>';
  };
  const eligibleAssignmentStations = (item) => fieldStations
    .filter((station) => station.id !== item.stationId && fieldStationProfile(station).compatible && fieldDeviceItems.some((device) => device.stationId === station.id && device.status !== 'disabled' && device.readiness?.ready))
    .map((station) => {
      const load = fieldQueueItems.filter((entry) => entry.id !== item.id && entry.stationId === station.id && fieldActiveQueueStatuses.includes(entry.status)).length;
      const capacity = Number(station.queueCapacity || 0);
      return { ...station, load, capacity, available: capacity > load };
    });
  const renderFieldStations = () => {
    const list = document.getElementById('fieldStationList');
    list.innerHTML = fieldStations.length ? fieldStations.map((item) => {
      const stationQueue = fieldQueueItems.filter((entry) => entry.stationId === item.id && fieldActiveQueueStatuses.includes(entry.status));
      const waiting = stationQueue.filter((entry) => entry.status === 'waiting' || entry.status === 'retest').length;
      const processing = stationQueue.filter((entry) => ['called', 'checked_in', 'testing', 'paused'].includes(entry.status)).length;
      const oldestWaitingMinutes = stationQueue.filter((entry) => ['waiting', 'retest'].includes(entry.status)).reduce((max, entry) => Math.max(max, fieldQueueAgeMinutes(entry)), 0);
      const capabilityLocked = stationQueue.some((entry) => ['called', 'checked_in', 'testing', 'paused'].includes(entry.status));
      const currentStudent = stationQueue.find((entry) => entry.status === 'testing') || stationQueue.find((entry) => entry.status === 'checked_in') || stationQueue.find((entry) => entry.status === 'called');
      const nextStudent = stationQueue.find((entry) => entry.status === 'retest') || stationQueue.find((entry) => entry.status === 'waiting');
      const capacity = Number(item.queueCapacity || 0);
      const load = stationQueue.length;
      const loadPercent = capacity > 0 ? Math.min(100, Math.round(load / capacity * 100)) : 0;
      const criticalTimingCount = stationQueue.filter((entry) => fieldQueueTimingSeverity(entry) === 'critical').length;
      const warningTimingCount = stationQueue.filter((entry) => fieldQueueTimingSeverity(entry) === 'warning').length;
      const congestionSeverity = criticalTimingCount || capacity > 0 && load / capacity >= .9 ? 'critical' : warningTimingCount || capacity > 0 && load / capacity >= .7 ? 'warning' : 'normal';
      const congestionLabel = congestionSeverity === 'critical' ? `严重积压 · ${criticalTimingCount || load} 人` : congestionSeverity === 'warning' ? `需关注 · ${warningTimingCount || load} 人` : '流转正常';
      const ready = fieldDeviceItems.some((device) => device.stationId === item.id && device.status !== 'disabled' && device.readiness?.ready);
      const profile = fieldStationProfile(item);
      const statusLabel = ready ? '可开测' : !item.activeCalibrationVersion ? '待标定' : ({ online: '检查未通过', offline: '离线', maintenance: '维护', paused: '暂停', disabled: '停用' }[item.status] || item.status);
      const statusActor = item.statusChangedByName || '系统自动更新';
      const statusContext = item.status !== 'online' && item.statusReason ? `<span class="field-station-status-context"><b>状态说明</b>${escapeHtml(item.statusReason)}${item.statusChangedAt ? ` · ${escapeHtml(statusActor)} · ${escapeHtml(fieldNow(item.statusChangedAt))}` : ''}</span>` : '';
      return `<article class="field-station-card is-flow-${congestionSeverity} ${load >= capacity && capacity > 0 ? 'is-full' : ''} ${!profile.compatible && fieldSelectedTask ? 'is-mismatch' : ''}"><div class="field-station-icon">${escapeHtml(String(item.stationCode || 'S').slice(0, 1).toUpperCase())}</div><div class="field-station-content"><strong>${escapeHtml(item.name)}</strong><small>${escapeHtml(item.stationCode)} · ${escapeHtml(profile.label)}</small><span class="field-station-flow is-${congestionSeverity}">${escapeHtml(congestionLabel)}</span><span class="field-station-profile-static">${escapeHtml(profile.label)}${capabilityLocked ? ' · 运行中已锁定' : ''}</span>${statusContext}<div class="field-station-students"><button data-field-handoff-student="${escapeHtml(currentStudent?.id || '')}" type="button" ${currentStudent ? '' : 'disabled'}><span>当前</span><strong>${escapeHtml(currentStudent?.studentName || '暂无')}</strong><small>${escapeHtml(currentStudent ? fieldQueueTimingLabel(currentStudent) : '等待叫号')}</small></button><button data-field-handoff-student="${escapeHtml(nextStudent?.id || '')}" type="button" ${nextStudent ? '' : 'disabled'}><span>下一位</span><strong>${escapeHtml(nextStudent?.studentName || '暂无')}</strong><small>${escapeHtml(nextStudent ? fieldQueueTimingLabel(nextStudent) : '队列已空')}</small></button></div><div class="field-station-load"><span><b>${load}</b> / ${capacity} 人</span><em>待叫号 ${waiting} · 处理中 ${processing}${waiting ? ` · 最长候测 ${oldestWaitingMinutes} 分` : ''}</em></div><i><u style="width:${loadPercent}%"></u></i><small>${!profile.compatible && fieldSelectedTask ? '与当前任务不匹配 · ' : ''}标定 ${escapeHtml(item.activeCalibrationVersion || '未下发')}</small></div><div class="field-station-card-side"><span class="status ${!profile.compatible && fieldSelectedTask ? 'attention' : ready ? 'done' : item.status === 'maintenance' || item.status === 'paused' ? 'review' : 'gray'}">${escapeHtml(!profile.compatible && fieldSelectedTask ? '项目不匹配' : statusLabel)}</span><button class="ghost-btn" data-field-station-edit="${escapeHtml(item.id)}" type="button">编辑信息</button></div></article>`;
    }).join('') : '<div class="field-empty">尚未建立测试点</div>';
  };
  const queueActions = (item) => {
    const assignedStation = item.stationId ? fieldStations.find((station) => station.id === item.stationId) : null;
    const assignedDevice = item.stationId ? fieldDeviceItems.find((device) => device.stationId === item.stationId && device.status === 'online' && device.status !== 'disabled') : null;
    const assignedStationReady = Boolean(assignedStation && fieldStationProfile(assignedStation).compatible && fieldDeviceItems.some((device) => device.stationId === assignedStation.id && device.status !== 'disabled' && device.readiness?.ready));
    const callBlocker = !item.stationId ? '先生成或调整候测名单' : !assignedStationReady ? '已分配测试点尚未通过开测检查' : '';
    const actions = {
      waiting: [['called', '叫号'], ['absent', '缺席']],
      called: [['checked_in', '签到'], ['waiting', '撤销叫号'], ['skipped', '跳过']],
      checked_in: [['called', '重新叫号'], ['absent', '缺席']],
      testing: [],
      completed: [['retest', '安排补测']],
      retest: [['waiting', '重新排队'], ['cancelled', '取消补测']],
      absent: [['waiting', '恢复候测']],
      skipped: [['waiting', '恢复候测']],
      paused: [['waiting', '恢复候测']]
    }[item.status] || [];
    const transitionButtons = actions.map(([status, label]) => {
      const blocked = status === 'called' && callBlocker;
      const identityAttributes = status === 'checked_in' ? ` data-field-queue-class="${escapeHtml(item.className || '班级待补')}" data-field-queue-student-no="${escapeHtml(item.studentNo || '学籍号待补')}" data-field-queue-gender="${escapeHtml(item.gender || '性别待补')}" data-field-queue-birth-date="${escapeHtml(item.birthDate ? dateText(item.birthDate) : '生日待补')}"` : '';
      return `<button class="ghost-btn field-queue-action" data-field-queue-id="${escapeHtml(item.id)}" data-field-queue-status="${status}" data-field-queue-version="${item.stateVersion}" data-field-queue-student="${escapeHtml(item.studentName)}"${identityAttributes} type="button" ${blocked ? `disabled title="${escapeHtml(callBlocker)}"` : ''}>${blocked ? escapeHtml(item.stationId ? '设备未就绪' : '待分配') : label}</button>`;
    }).join('');
    const canAssign = ['waiting', 'retest'].includes(item.status);
    const assignmentOptions = canAssign ? eligibleAssignmentStations(item) : [];
    const assignmentButton = canAssign ? `<button class="ghost-btn field-queue-action field-assign-action" data-field-assign-id="${escapeHtml(item.id)}" type="button" ${assignmentOptions.some((station) => station.available) ? '' : 'disabled'} title="${assignmentOptions.length ? '调整到其他已就绪测试点' : '当前没有其他已就绪测试点'}">换点</button>` : '';
    const recallButton = item.status === 'called' ? `<button class="ghost-btn field-queue-action field-recall-action" data-field-recall-device="${escapeHtml(assignedDevice?.id || '')}" data-field-recall-queue="${escapeHtml(item.id)}" data-field-recall-student-id="${escapeHtml(item.studentId || '')}" data-field-recall-student="${escapeHtml(item.studentName)}" type="button" ${assignedDevice ? '' : 'disabled title="场地设备离线，无法立即提醒"'}>${assignedDevice ? '再次提醒' : '设备离线'}</button>` : '';
    const historyButton = `<button class="ghost-btn field-queue-action field-history-action" data-field-queue-history="${escapeHtml(item.id)}" type="button">记录</button>`;
    return `${historyButton}${assignmentButton}${recallButton}${transitionButtons}`;
  };
  const showFieldQueueHistory = async (queueEntryId) => {
    const body = document.getElementById('fieldQueueHistoryBody');
    fieldQueueHistoryModal.classList.remove('hidden');
    body.innerHTML = '<div class="field-empty">正在读取学生现场记录…</div>';
    try {
      const data = await api(`/v1/admin/test-queues/${encodeURIComponent(queueEntryId)}/history`);
      const item = data.queue || {};
      const events = data.events || [];
      const sessions = data.sessions || [];
      const eventRows = events.length ? events.map((entry) => {
        const statusText = entry.oldStatus === entry.newStatus
          ? '测试点或队列位置调整'
          : `${queueStatusLabels[entry.oldStatus] || entry.oldStatus || '进入队列'} → ${queueStatusLabels[entry.newStatus] || entry.newStatus}`;
        return `<li><i></i><div><strong>${escapeHtml(statusText)}</strong><span>${escapeHtml(entry.reason || '历史记录未填写处理说明')}</span><small>${escapeHtml(entry.actorName || '现场人员')} · ${escapeHtml(entry.stationCode || '未分配测试点')}</small></div><time>${escapeHtml(fieldNow(entry.happenedAt))}</time></li>`;
      }).join('') : '<div class="field-empty">尚无队列流转事件</div>';
      const sessionRows = sessions.length ? sessions.map((session) => `<article><div><strong>第 ${Number(session.attemptNo || 1)} 次采集 · ${escapeHtml(fieldSessionStatus(session.status))}</strong><span>${escapeHtml(session.stationCode || '未分配测试点')} · ${escapeHtml(session.deviceName || '设备待确认')}</span><small>${Number(session.scoreCount || 0)} 项成绩 · ${Number(session.evidenceCount || 0)} 份有效证据 · ${escapeHtml(session.algorithmVersion || '算法版本待确认')}</small></div><time>${escapeHtml(fieldNow(session.startedAt || session.endedAt))}</time></article>`).join('') : '<div class="field-empty">尚无采集尝试</div>';
      body.innerHTML = `<section class="field-history-summary"><div class="field-student-avatar">${escapeHtml(String(item.studentName || '学').slice(0, 1))}</div><div><strong>${escapeHtml(item.studentName || '学生')}</strong><span>${escapeHtml(item.className || '班级待补')} · ${escapeHtml(item.studentNo || '学籍号待补')} · ${escapeHtml(item.taskTitle || '任务待确认')}</span><small>${escapeHtml(item.stationCode || '待分配测试点')} · 当前${escapeHtml(queueStatusLabels[item.status] || item.status || '状态待确认')} · 队列版本 ${Number(item.stateVersion || 0)}</small></div><span class="status ${['absent', 'skipped', 'cancelled', 'retest'].includes(item.status) ? 'attention' : item.status === 'completed' ? 'done' : 'review'}">${escapeHtml(queueStatusLabels[item.status] || item.status || '未知')}</span></section>
        <div class="field-history-current-note"><strong>当前现场说明</strong><span>${escapeHtml(item.note || '当前状态没有单独说明；可查看下方历史事件。')}</span><small>最后更新 ${escapeHtml(fieldNow(item.updatedAt))}${item.lastCalledAt ? ` · 最近叫号 ${escapeHtml(fieldNow(item.lastCalledAt))}` : ''}</small></div>
        <div class="field-history-columns"><section><h4>队列流转时间线 <span>${events.length} 条</span></h4><ol class="field-history-timeline">${eventRows}</ol></section><section><h4>采集尝试 <span>${sessions.length} 次</span></h4><div class="field-history-sessions">${sessionRows}</div></section></div>`;
    } catch (error) {
      body.innerHTML = `<div class="field-empty"><strong>现场记录读取失败</strong><span>${escapeHtml(error.message)}</span></div>`;
    }
  };
  const fieldVersionParts = (value, requireClientPrefix = true) => {
    const source = String(value || '').trim();
    const match = source.match(requireClientPrefix ? /^field-client\/v?(\d+)\.(\d+)(?:\.(\d+))?/i : /^v?(\d+)\.(\d+)(?:\.(\d+))?/i);
    return match ? [Number(match[1]), Number(match[2]), Number(match[3] || 0)] : null;
  };
  const fieldCompareVersion = (left, right) => {
    for (let index = 0; index < 3; index += 1) { if (left[index] !== right[index]) return left[index] > right[index] ? 1 : -1; }
    return 0;
  };
  const fieldDeviceVersionState = (item) => {
    const reported = String(item.softwareVersion || '').trim();
    if (!fieldClientReleaseInfo?.available) return { status: 'unavailable', label: reported || '版本未上报', detail: '当前发布包不可用' };
    const current = fieldVersionParts(reported, true);
    const latest = fieldVersionParts(fieldClientReleaseInfo.version, false);
    if (!current || !latest) return { status: 'unknown', label: reported || '版本未上报', detail: `无法识别为 Windows 场地端 · 可安装 v${fieldClientReleaseInfo.version}` };
    const comparison = fieldCompareVersion(current, latest);
    if (comparison < 0) return { status: 'outdated', label: reported, detail: `待升级至 v${fieldClientReleaseInfo.version}` };
    if (comparison > 0) return { status: 'ahead', label: reported, detail: `高于当前发布版 v${fieldClientReleaseInfo.version}` };
    return { status: 'current', label: reported, detail: '已是最新版' };
  };
  const showFieldDeviceDetail = (deviceId) => {
    const item = fieldDeviceItems.find((device) => device.id === deviceId);
    const body = document.getElementById('fieldDeviceDetailBody');
    if (!item || !body) {
      if (body) body.innerHTML = '<div class="field-empty">设备信息已更新，请关闭后重新打开。</div>';
      return;
    }
    fieldDeviceDetailId = item.id;
    const readiness = item.readiness || {};
    const checks = Array.isArray(readiness.checks) ? readiness.checks : [];
    const passed = checks.filter((check) => check.status === 'passed').length;
    const controlState = item.controlState || 'running';
    const controlLabel = { running: '运行中', paused: '已暂停', stopped: '已停止' }[controlState] || controlState;
    const deviceStatusLabel = { online: '在线', offline: '离线', maintenance: '维护中', disabled: '已停用' }[item.status] || item.status;
    const keyLabel = { valid: '密钥有效', expiring: '密钥即将到期', expired: '密钥已过期', legacy_unbounded: '需轮换密钥', rotation_required: '需轮换密钥' }[item.apiKeyStatus || 'legacy_unbounded'] || item.apiKeyStatus;
    const version = fieldDeviceVersionState(item);
    const stationOptions = `<option value="">未绑定测试点</option>${fieldStations.map((station) => `<option value="${escapeHtml(station.id)}" ${station.id === item.stationId ? 'selected' : ''}>${escapeHtml(station.stationCode)} · ${escapeHtml(station.name)}</option>`).join('')}`;
    const controlActions = controlState === 'running'
      ? `<button class="secondary-btn" data-field-control-device="${escapeHtml(item.id)}" data-field-control-name="${escapeHtml(item.name)}" data-field-control-command="pause" type="button">暂停现场操作</button><button class="secondary-btn danger-text" data-field-control-device="${escapeHtml(item.id)}" data-field-control-name="${escapeHtml(item.name)}" data-field-control-command="stop" type="button">停止现场操作</button>`
      : `<button class="secondary-btn field-resume-btn" data-field-control-device="${escapeHtml(item.id)}" data-field-control-name="${escapeHtml(item.name)}" data-field-control-command="resume" type="button">恢复现场运行</button>`;
    const checksHtml = checks.length ? checks.map((check) => `<li class="is-${escapeHtml(check.status)}"><i>${check.status === 'passed' ? '✓' : check.status === 'pending' ? '○' : '!'}</i><span><strong>${escapeHtml(check.label)}</strong><small>${escapeHtml(check.status === 'passed' ? check.detail : `${check.detail} · ${check.remediation}`)}</small></span></li>`).join('') : '<li class="is-pending"><i>○</i><span><strong>等待设备上报</strong><small>设备联网并发送心跳后显示完整开测检查。</small></span></li>';
    body.innerHTML = `<div class="field-device-detail-hero"><div><span class="field-online-indicator ${item.status === 'online' ? 'is-online' : ''}">${escapeHtml(deviceStatusLabel)}</span><h3>${escapeHtml(item.name)}</h3><p>${escapeHtml(item.deviceCode)} · ${escapeHtml(item.stationCode || '未绑定测试点')}</p></div><span class="field-control-state is-${escapeHtml(controlState)}">${escapeHtml(controlLabel)}</span></div><div class="field-device-detail-grid"><div><span>最近心跳</span><strong>${escapeHtml(fieldRelativeHeartbeat(item.lastHeartbeatAt))}</strong></div><div><span>设备密钥</span><strong>${escapeHtml(keyLabel)}</strong></div><div><span>客户端版本</span><strong>${escapeHtml(version.label)}</strong><small>${escapeHtml(version.detail)}</small></div><div><span>开测检查</span><strong>${passed}/${checks.length || '—'} 项通过</strong><small>${readiness.ready ? '已经具备正式开测条件' : '仍有条件未完成'}</small></div></div><section class="field-device-detail-checks"><div><strong>完整开测检查</strong><span>${readiness.ready ? '所有强制条件已经通过' : escapeHtml((readiness.blockers || []).join('；') || '等待设备上报详细状态')}</span></div><ul>${checksHtml}</ul></section><section class="field-maintenance-editor"><div class="field-maintenance-editor-head"><div><strong>设备基础信息</strong><span>修改后后台和场地端会自动同步；在线设备改绑前需先退出客户端。</span></div></div><div class="hard-form-grid field-maintenance-form"><div class="field"><label for="fieldEditDeviceName">设备名称</label><input id="fieldEditDeviceName" maxlength="120" value="${escapeHtml(item.name)}"></div><div class="field"><label for="fieldEditDeviceCode">设备编码</label><input id="fieldEditDeviceCode" maxlength="64" value="${escapeHtml(item.deviceCode)}"></div><div class="field"><label for="fieldEditDeviceStation">所属测试点</label><select id="fieldEditDeviceStation">${stationOptions}</select></div><div class="field"><label for="fieldEditDeviceSerial">设备序列号</label><input id="fieldEditDeviceSerial" maxlength="120" value="${escapeHtml(item.serialNumber || '')}" placeholder="可选，用于资产核对"></div></div><div class="field-maintenance-editor-actions"><span>有活动采集或现场处理中学生时不能改绑。</span><button class="primary-btn" data-field-save-device="${escapeHtml(item.id)}" type="button">保存设备信息</button></div></section><div id="fieldDeviceDetailCredential" class="field-key-notice hidden"></div><div class="field-device-detail-actions"><button class="secondary-btn" data-field-device-guide="${escapeHtml(item.id)}" data-field-device-code="${escapeHtml(item.deviceCode)}" type="button">查看接入指南</button>${item.status === 'disabled' ? `<button class="primary-btn" data-field-device-status="offline" data-field-device-id="${escapeHtml(item.id)}" data-field-device-name="${escapeHtml(item.name)}" type="button">恢复设备</button>` : `<button class="secondary-btn" data-field-command-device="${escapeHtml(item.id)}" type="button">重新同步配置</button>${controlActions}</div><div class="field-device-danger-zone"><div><strong>安全与停用</strong><span>密钥轮换会立即使旧密钥失效；停用设备会取消未处理指令。</span></div><button class="secondary-btn" data-field-rotate-device="${escapeHtml(item.id)}" type="button">轮换设备密钥</button><button class="secondary-btn danger-text" data-field-device-status="disabled" data-field-device-id="${escapeHtml(item.id)}" data-field-device-name="${escapeHtml(item.name)}" type="button">停用设备</button>`}</div>`;
    fieldDeviceDetailModal.classList.remove('hidden');
  };
  const fieldOutdatedDeviceCount = () => fieldDeviceItems.filter((item) => item.status !== 'disabled' && fieldDeviceVersionState(item).status === 'outdated').length;
  const renderFieldQueue = () => {
    const query = String(document.getElementById('fieldQueueSearch')?.value || '').trim().toLowerCase();
    const groups = {
      active: ['waiting', 'called', 'checked_in', 'testing', 'retest'],
      timing: null,
      exception: ['retest', 'absent', 'skipped', 'paused', 'cancelled'],
      completed: ['completed'],
      all: null
    };
    const stationScopedItems = fieldQueueItems.filter((item) => fieldQueueStationId === 'all'
      || fieldQueueStationId === '__unassigned__' && !item.stationId
      || item.stationId === fieldQueueStationId);
    document.querySelectorAll('[data-field-queue-filter]').forEach((button) => {
      const statuses = groups[button.dataset.fieldQueueFilter];
      const count = button.dataset.fieldQueueFilter === 'timing' ? stationScopedItems.filter(fieldQueueTimingOverdue).length : statuses ? stationScopedItems.filter((item) => statuses.includes(item.status)).length : stationScopedItems.length;
      button.classList.toggle('is-active', button.dataset.fieldQueueFilter === fieldQueueFilter);
      const badge = button.querySelector('b'); if (badge) badge.textContent = count;
    });
    const statuses = groups[fieldQueueFilter];
    const visible = stationScopedItems.filter((item) => (fieldQueueFilter === 'timing' ? fieldQueueTimingOverdue(item) : !statuses || statuses.includes(item.status)) && (!query || `${item.studentName || ''}${item.studentNo || ''}${item.className || ''}`.toLowerCase().includes(query)))
      .sort((left, right) => fieldQueueOperationalPriority(left) - fieldQueueOperationalPriority(right) || (fieldQueueTimingOverdue(right) ? Number(right.stateAgeSeconds || 0) : 0) - (fieldQueueTimingOverdue(left) ? Number(left.stateAgeSeconds || 0) : 0) || Number(left.queueOrder || 0) - Number(right.queueOrder || 0));
    renderFieldParallelBoard();
    const selectedStation = fieldStations.find((station) => station.id === fieldQueueStationId);
    const scopeLabel = fieldQueueStationId === '__unassigned__' ? '待分配' : selectedStation ? `${selectedStation.stationCode} · ${selectedStation.name}` : '全部测试点';
    document.getElementById('fieldQueueHint').textContent = `${scopeLabel} · ${stationScopedItems.length}/${fieldQueueItems.length} 人`;
    const list = document.getElementById('fieldQueueList');
    list.innerHTML = visible.length ? visible.map((item, index) => { const timingSeverity = fieldQueueTimingSeverity(item); const capture = fieldCaptureProgress(item); return `<article class="field-queue-row ${fieldQueueTimingOverdue(item) ? 'is-timing-overdue' : ''} ${timingSeverity === 'critical' ? 'is-timing-critical' : ''}" data-field-queue-entry="${escapeHtml(item.id)}"><span class="field-queue-number">${String(item.queueOrder || index + 1).padStart(2, '0')}</span><span class="field-student-avatar">${escapeHtml(String(item.studentName || '学').slice(0, 1))}</span><span class="field-student-info"><strong>${escapeHtml(item.studentName)}</strong><small>${escapeHtml(item.className)} · ${escapeHtml(item.studentNo || '学籍号待补')} · ${escapeHtml(item.gender || '性别待补')} · ${escapeHtml(item.birthDate ? dateText(item.birthDate) : '生日待补')}</small><em>${escapeHtml(fieldQueueTimingLabel(item))}</em>${capture ? `<em class="field-capture-live">${escapeHtml(capture.title)} · ${escapeHtml(capture.meta)}</em>` : ''}</span><span class="field-station-assignment">${escapeHtml(item.stationCode || '待分配')}</span><span class="status ${timingSeverity === 'critical' ? 'attention' : timingSeverity === 'warning' ? 'review' : item.status === 'completed' ? 'done' : item.status === 'testing' || item.status === 'checked_in' ? 'review' : item.status === 'absent' || item.status === 'skipped' || item.status === 'cancelled' ? 'attention' : 'pending'}">${escapeHtml(timingSeverity === 'critical' ? '严重超时' : timingSeverity === 'warning' ? '时间超时' : queueStatusLabels[item.status] || item.status)}</span><span class="field-queue-actions">${queueActions(item)}</span></article>`; }).join('') : `<div class="field-empty field-empty-large"><strong>${fieldQueueItems.length ? stationScopedItems.length ? fieldQueueFilter === 'timing' ? '当前没有时间超时学生' : '没有匹配的学生' : '当前测试点没有学生' : '尚未生成候测队列'}</strong><span>${fieldQueueItems.length ? stationScopedItems.length ? '调整状态筛选或搜索条件' : '请选择其他测试点，或重新分流候测名单' : '选择任务后点击“生成 / 重新分流”'}</span></div>`;
  };
  const renderFieldDevices = () => {
    const showDisabled = Boolean(document.getElementById('fieldShowDisabledDevices')?.checked);
    const visible = fieldDeviceItems.filter((item) => showDisabled || item.status !== 'disabled');
    document.getElementById('fieldDeviceList').innerHTML = visible.length ? visible.map((item) => {
      const keyStatus = item.apiKeyStatus || 'legacy_unbounded';
      const keyLabel = { valid: '密钥有效', expiring: '密钥即将到期', expired: '密钥已过期', legacy_unbounded: '需轮换密钥', rotation_required: '需轮换密钥' }[keyStatus] || keyStatus;
      const readiness = item.readiness || {};
      const controlState = item.controlState || 'running';
      const controlLabel = { running: '运行中', paused: '已暂停', stopped: '已停止' }[controlState] || controlState;
      const blockers = item.status === 'disabled' ? '该设备已停用，不再接受设备请求' : controlState === 'paused' ? '中央已暂停现场操作，等待恢复指令' : controlState === 'stopped' ? '中央已停止现场操作，需人工确认后恢复' : readiness.ready ? '自检通过，可正式开测' : (readiness.blockers || []).slice(0, 1).join('；') || '等待设备上报自检';
      const readinessChecks = Array.isArray(readiness.checks) ? readiness.checks : [];
      const adapterBlocked = readinessChecks.some((check) => check.key === 'capture_adapter' && check.status === 'blocked');
      const passedChecks = readinessChecks.filter((check) => check.status === 'passed').length;
      const neverConnected = !item.lastHeartbeatAt;
      const statusLabel = neverConnected ? '从未连接' : ({ online: '在线', offline: '离线', maintenance: '维护中', disabled: '已停用' }[item.status] || item.status);
      const version = fieldDeviceVersionState(item);
      const versionDownload = ['outdated', 'unknown'].includes(version.status) && fieldClientReleaseInfo?.available ? `<a class="ghost-btn field-upgrade-download" href="${escapeHtml(fieldClientReleaseInfo.downloadUrl)}" download>下载新版</a>` : '';
      const primaryBlocker = neverConnected ? '等待首次连接：在 Windows 双击客户端并粘贴三项接入信息' : adapterBlocked ? '未接入认证采集设备；请在 Windows 客户端点击右侧“接入采集设备”选择厂商 DLL' : blockers;
      const cardActions = neverConnected
        ? `<button class="primary-btn" data-field-device-guide="${escapeHtml(item.id)}" data-field-device-code="${escapeHtml(item.deviceCode)}" type="button">开始连接</button><button class="ghost-btn" data-field-device-detail="${escapeHtml(item.id)}" type="button">设备详情</button>`
        : `<button class="primary-btn" data-field-device-detail="${escapeHtml(item.id)}" type="button">查看设备</button><button class="ghost-btn" data-field-device-guide="${escapeHtml(item.id)}" data-field-device-code="${escapeHtml(item.deviceCode)}" type="button">接入指南</button>`;
      return `<article class="field-device-card ${item.status === 'disabled' ? 'is-disabled' : ''} ${controlState !== 'running' ? 'is-control-locked' : ''} ${version.status === 'outdated' ? 'is-update-required' : ''}" data-field-device-card="${escapeHtml(item.id)}"><div class="field-device-top"><div><strong>${escapeHtml(item.name)}</strong><small>${escapeHtml(item.deviceCode)} · ${escapeHtml(item.stationCode || '未绑定测试点')}</small></div><div class="field-device-badges"><span class="field-control-state is-${escapeHtml(controlState)}">${escapeHtml(controlLabel)}</span><span class="field-online-indicator ${item.status === 'online' ? 'is-online' : ''}">${escapeHtml(statusLabel)}</span></div></div><div class="field-device-version is-${escapeHtml(version.status)}"><span><b>${escapeHtml(version.label)}</b><small>${escapeHtml(version.detail)}</small></span>${versionDownload}</div><p>${escapeHtml(primaryBlocker)}</p><div class="field-device-meta"><span>心跳 ${escapeHtml(fieldRelativeHeartbeat(item.lastHeartbeatAt))}</span><span>${escapeHtml(keyLabel)}</span></div><div class="field-device-readiness-summary ${readiness.ready ? 'is-ready' : ''}"><span>开测检查</span><strong>${passedChecks}/${readinessChecks.length || '—'} 项通过</strong></div><div class="field-card-actions">${cardActions}</div></article>`;
    }).join('') : `<div class="field-empty">${fieldDeviceItems.length ? '已停用设备已隐藏' : '尚未注册场地设备'}</div>`;
  };
  const renderFieldSessions = () => {
    document.querySelectorAll('[data-field-session-filter]').forEach((button) => {
      button.classList.toggle('is-active', button.dataset.fieldSessionFilter === fieldSessionFilter);
      const badge = button.querySelector('b');
      if (badge) badge.textContent = Number(fieldSessionCounts[button.dataset.fieldSessionFilter] || 0);
    });
    document.getElementById('fieldSessionList').innerHTML = fieldSessionItems.length ? fieldSessionItems.map((item) => {
      const evidenceCount = Number(item.evidenceCount || 0);
      const totalEvidenceCount = Number(item.totalEvidenceCount || 0);
      const interrupted = item.recoveryEligible === true;
      const statusClassName = item.status === 'completed' && totalEvidenceCount > 0 ? 'done' : interrupted || ['needs_review', 'retest', 'aborted', 'sync_conflict'].includes(item.status) || (['completed', 'needs_review'].includes(item.status) && totalEvidenceCount === 0) ? 'review' : 'pending';
      const evidenceLabel = evidenceCount > 0 ? `${evidenceCount} 份有效证据` : totalEvidenceCount > 0 ? '证据已按保留期清理' : ['completed', 'needs_review'].includes(item.status) ? '从未提交证据' : '等待证据';
      const statusLabel = interrupted ? `${fieldSessionStatus(item.status)} · 设备中断` : fieldSessionStatus(item.status);
      return `<button class="field-session-row ${interrupted ? 'is-recoverable' : ''}" data-field-session-id="${escapeHtml(item.id)}" type="button"><span><strong>${escapeHtml(item.studentName)}</strong><small>${escapeHtml(item.taskTitle)} · ${escapeHtml(item.stationCode || '未分配测试点')} · ${fieldNow(item.startedAt)} · ${evidenceLabel}</small>${interrupted ? '<em>设备已掉线或已停止，可安全收口并转补测</em>' : ''}</span><span class="status ${statusClassName}">${escapeHtml(statusLabel)}</span></button>`;
    }).join('') : `<div class="field-empty">${String(document.getElementById('fieldSessionSearch')?.value || '').trim() ? '没有匹配的采集记录' : fieldSessionTotal ? '当前页没有采集记录' : '当前分组暂无采集记录'}</div>`;
    const pages = Math.max(1, Math.ceil(fieldSessionTotal / fieldSessionPageSize));
    document.getElementById('fieldSessionPager').innerHTML = `<span>第 ${fieldSessionPage} / ${pages} 页，共 ${fieldSessionTotal} 条</span><span><button class="ghost-btn" data-field-session-page="${fieldSessionPage - 1}" type="button" ${fieldSessionPage <= 1 ? 'disabled' : ''}>上一页</button><button class="ghost-btn" data-field-session-page="${fieldSessionPage + 1}" type="button" ${fieldSessionPage >= pages ? 'disabled' : ''}>下一页</button></span>`;
  };
  const renderFieldSyncConflicts = () => {
    document.querySelectorAll('[data-field-conflict-filter]').forEach((button) => {
      button.classList.toggle('is-active', button.dataset.fieldConflictFilter === fieldSyncConflictFilter);
      const badge = button.querySelector('b'); if (badge) badge.textContent = Number(fieldSyncConflictCounts[button.dataset.fieldConflictFilter] || 0);
    });
    const eventLabels = { 'queue.transition': '队列状态变更', 'session.open': '开始采集', 'session.events': '采集时间线', 'session.complete': '提交成绩', 'session.abort': '中止并补测' };
    document.getElementById('fieldSyncConflictHint').textContent = fieldSyncConflictCounts.open ? `${fieldSyncConflictCounts.open} 条待核对` : '没有待处理冲突';
    document.getElementById('fieldSyncConflictList').innerHTML = fieldSyncConflictItems.length ? fieldSyncConflictItems.map((item) => {
      const failed = item.failedEvent || {};
      const subject = item.studentName ? `${item.studentName}${item.studentNo ? ` · ${item.studentNo}` : ''}` : failed.clientSessionId || failed.sessionId || failed.queueEntryId || '未关联学生';
      const eventLabel = eventLabels[failed.eventType] || failed.eventType || '未知事件';
      const context = failed.eventType === 'queue.transition' ? `${eventLabel}：${queueStatusLabels[failed.status] || failed.status || '未知状态'} · 期望版本 ${failed.expectedVersion ?? '—'}` : `${eventLabel}${failed.eventCount != null ? ` · ${failed.eventCount} 条动作` : ''}${failed.scoreCount != null ? ` · ${failed.scoreCount} 项成绩` : ''}`;
      const progress = `已确认 ${item.acceptedEventIds?.length || 0} · 失败 1 · 未处理 ${item.unprocessedEventIds?.length || 0}`;
      const resolution = item.resolutionStatus === 'resolved' ? `<div class="field-conflict-resolution"><strong>已由 ${escapeHtml(item.resolvedByName || '管理员')} 处理</strong><span>${escapeHtml(item.resolutionNote || '已确认中央状态')}</span><time>${fieldNow(item.resolvedAt)}</time></div>` : `<button class="primary-btn" data-field-resolve-conflict="${escapeHtml(item.id)}" data-field-resolve-device="${escapeHtml(item.deviceName || item.deviceCode || '场地设备')}" type="button">核对并关闭</button>`;
      return `<article class="field-sync-conflict ${item.resolutionStatus === 'resolved' ? 'is-resolved' : ''}"><div class="field-conflict-main"><div class="field-conflict-title"><span class="status ${item.resolutionStatus === 'resolved' ? 'done' : 'attention'}">${item.resolutionStatus === 'resolved' ? '已处理' : '待核对'}</span><strong>${escapeHtml(subject)}</strong></div><p>${escapeHtml(item.message || item.code || '同步冲突')}</p><small>${escapeHtml(item.deviceName || item.deviceCode)} · ${escapeHtml(item.stationCode || '未绑定测试点')} · ${escapeHtml(context)}</small><em>批次 ${escapeHtml(String(item.clientBatchId || '').slice(0, 8))} · ${escapeHtml(progress)} · ${fieldNow(item.completedAt)}</em></div>${resolution}</article>`;
    }).join('') : `<div class="field-empty">${fieldSyncConflictFilter === 'open' ? '当前没有待核对的同步冲突' : '当前分组暂无同步冲突记录'}</div>`;
  };
  const renderFieldIssues = () => {
    const activeDevices = fieldDeviceItems.filter((item) => item.status !== 'disabled');
    const neverConnectedDevices = activeDevices.filter((item) => !item.lastHeartbeatAt).length;
    const offlineDevices = activeDevices.filter((item) => item.status !== 'online' && item.lastHeartbeatAt).length;
    const blockedDevices = activeDevices.filter((item) => item.status === 'online' && !item.readiness?.ready).length;
    const missingAdapters = activeDevices.filter((item) => item.status === 'online' && (item.readiness?.checks || []).some((check) => check.key === 'capture_adapter' && check.status === 'blocked')).length;
    const outdatedDevices = fieldOutdatedDeviceCount();
    const attentionSessions = Number(fieldSessionCounts.attention || 0);
    const openSyncConflicts = Number(fieldSyncConflictCounts.open || 0);
    const unassignedStudents = fieldQueueItems.filter((item) => ['waiting', 'called', 'checked_in', 'retest'].includes(item.status) && !item.stationId).length;
    const overdueCalls = fieldQueueItems.filter((item) => item.calledOverdue === true).length;
    const severeWaitingStudents = fieldQueueItems.filter((item) => ['waiting', 'retest'].includes(item.status) && fieldQueueTimingSeverity(item) === 'critical').length;
    const longWaitingStudents = fieldQueueItems.filter((item) => ['waiting', 'retest'].includes(item.status) && fieldQueueTimingSeverity(item) === 'warning').length;
    const issues = [];
    if (fieldSelectedTask && !fieldTaskPlanningStationCount) issues.push({ label: '当前任务无匹配测试点', target: 'stations', tone: 'danger' });
    if (neverConnectedDevices) issues.push({ label: `${neverConnectedDevices} 台等待首次连接`, target: 'devices', tone: 'danger' });
    if (offlineDevices) issues.push({ label: `${offlineDevices} 台设备连接中断`, target: 'devices', tone: 'danger' });
    if (missingAdapters) issues.push({ label: `${missingAdapters} 台未接入采集设备`, target: 'devices', tone: 'danger' });
    if (blockedDevices) issues.push({ label: `${blockedDevices} 台未通过开测检查`, target: 'devices', tone: 'warning' });
    if (outdatedDevices) issues.push({ label: `${outdatedDevices} 台客户端待升级`, target: 'devices', tone: 'warning' });
    if (attentionSessions) issues.push({ label: `${attentionSessions} 个会话待处理`, target: 'sessions', tone: 'warning' });
    if (openSyncConflicts) issues.push({ label: `${openSyncConflicts} 条同步冲突待核对`, target: 'conflicts', tone: 'danger' });
    if (overdueCalls) issues.push({ label: `${overdueCalls} 人叫号超过 2 分钟`, target: 'timing', tone: 'danger' });
    if (severeWaitingStudents) issues.push({ label: `${severeWaitingStudents} 人候测超过 30 分钟`, target: 'timing', tone: 'danger' });
    if (longWaitingStudents) issues.push({ label: `${longWaitingStudents} 人候测超过 15 分钟`, target: 'timing', tone: 'warning' });
    if (unassignedStudents) issues.push({ label: `${unassignedStudents} 名学生待分配`, target: 'queue', tone: 'info' });
    document.getElementById('fieldIssueChips').innerHTML = issues.length
      ? issues.map((item) => `<button class="is-${item.tone}" data-field-issue-target="${item.target}" type="button">${escapeHtml(item.label)}</button>`).join('')
      : '<span class="field-issue-clear">现场状态正常</span>';
    const setRunway = (key, stateName, detail) => {
      const step = document.querySelector(`[data-field-runway="${key}"]`);
      if (!step) return;
      step.classList.remove('is-ready', 'is-blocked', 'is-active');
      step.classList.add(`is-${stateName}`);
      const detailNode = step.querySelector('small');
      if (detailNode) detailNode.textContent = detail;
    };
    const onlineDevices = activeDevices.filter((item) => item.status === 'online').length;
    const taskChosen = Boolean(fieldSelectedTask);
    const queueReady = fieldQueueItems.length > 0;
    const deviceReady = fieldTaskReadyStationCount > 0;
    const canGenerateQueue = Boolean(fieldDispatchTaskId && !document.getElementById('fieldRebalanceQueue')?.disabled);
    setRunway('task', taskChosen ? 'ready' : 'active', taskChosen ? fieldSelectedTask.title : '请选择已发布任务');
    setRunway('queue', queueReady ? 'ready' : taskChosen ? 'active' : 'blocked', queueReady ? `${fieldQueueItems.length} 名学生已进入队列` : '生成候测名单');
    setRunway('device', deviceReady ? 'ready' : queueReady ? 'active' : 'blocked', deviceReady ? `${fieldTaskReadyStationCount} 个测试点可开测` : `${onlineDevices}/${activeDevices.length} 台设备在线`);
    setRunway('start', taskChosen && queueReady && deviceReady ? 'ready' : 'blocked', taskChosen && queueReady && deviceReady ? '条件完成，可以叫号' : '完成前三步后开放');
    const primaryDecision = selectFieldPrimaryAction({ taskChosen, queueReady, deviceReady, canGenerateQueue, issues, onlineDevices, activeDeviceCount: activeDevices.length });
    document.getElementById('fieldIssueSummary').textContent = !taskChosen
      ? '先选择本次测评任务，再准备学生、设备和叫号。'
      : !queueReady
        ? fieldTaskPlanningStationCount ? '当前阻塞：候测名单尚未生成。' : '当前阻塞：任务尚无匹配测试点。'
        : !deviceReady
          ? `当前阻塞：没有可开测设备（${onlineDevices}/${activeDevices.length} 台在线）；超时学生等后续待办仍会保留。`
          : issues.length
            ? `开测条件已具备；另有 ${issues.length} 类现场待办需要处理。`
            : '设备、队列和采集记录均无待处理异常。';
    const primaryAction = document.getElementById('fieldOpsPrimaryAction');
    if (primaryAction) {
      primaryAction.disabled = false;
      primaryAction.dataset.fieldPrimaryTarget = primaryDecision.target;
      primaryAction.textContent = primaryDecision.label;
    }
  };
  const focusPendingFieldRuntimeTarget = () => {
    if (!pendingFieldRuntimeTarget) return;
    const targetName = pendingFieldRuntimeTarget;
    const deviceId = pendingFieldRuntimeDeviceId;
    pendingFieldRuntimeTarget = null;
    pendingFieldRuntimeDeviceId = null;
    if (targetName === 'queue' || targetName === 'timing') {
      fieldQueueFilter = targetName === 'timing' ? 'timing' : 'active';
      renderFieldQueue();
    }
    let target = null;
    if (targetName === 'task' || targetName === 'generate') target = document.querySelector('.field-dispatch-bar');
    else if (targetName === 'devices' && deviceId) target = [...document.querySelectorAll('[data-field-device-card]')].find((item) => item.dataset.fieldDeviceCard === deviceId) || null;
    if (!target) target = document.getElementById({ devices: 'fieldDeviceBoard', sessions: 'fieldSessionBoard', queue: 'fieldQueueBoard', timing: 'fieldQueueBoard', conflicts: 'fieldSyncConflictBoard' }[targetName]);
    target?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    target?.classList.add('is-focused');
    window.setTimeout(() => target?.classList.remove('is-focused'), 1800);
    if (targetName === 'task') document.getElementById('fieldDispatchTask')?.focus({ preventScroll: true });
  };
  const loadFieldOperations = async () => {
    if (fieldOperationsLoading) { fieldOperationsReloadPending = true; return; }
    fieldOperationsLoading = true;
    const schoolId = state.schoolId;
    const summary = document.getElementById('fieldOpsSummary');
    try {
      const sessionSearch = String(document.getElementById('fieldSessionSearch')?.value || '').trim();
      const [stations, devices, sessions, tasksResult, syncConflicts] = await Promise.all([
        api(`/v1/admin/test-stations?schoolId=${encodeURIComponent(schoolId)}`),
        api(`/v1/admin/test-devices?schoolId=${encodeURIComponent(schoolId)}`),
        api(`/v1/admin/test-sessions?schoolId=${encodeURIComponent(schoolId)}&paged=1&page=${fieldSessionPage}&pageSize=${fieldSessionPageSize}&view=${encodeURIComponent(fieldSessionFilter)}${sessionSearch ? `&search=${encodeURIComponent(sessionSearch)}` : ''}`),
        api(`/v1/schools/${encodeURIComponent(schoolId)}/tasks?paged=1&pageSize=100`),
        api(`/v1/admin/field-sync-conflicts?schoolId=${encodeURIComponent(schoolId)}&view=${encodeURIComponent(fieldSyncConflictFilter)}&page=1&pageSize=20`)
      ]);
      fieldStations = stations || [];
      fieldDeviceItems = devices || [];
      const activeDevices = fieldDeviceItems.filter((item) => item.status !== 'disabled');
      const online = activeDevices.filter((item) => item.status === 'online').length;
      const formalReady = activeDevices.filter((item) => item.readiness?.ready).length;
      const sessionResult = Array.isArray(sessions) ? { items: sessions, page: 1, pageSize: fieldSessionPageSize, total: sessions.length, counts: { attention: 0, active: 0, completed: 0, all: sessions.length } } : (sessions || {});
      fieldSessionItems = sessionResult.items || [];
      fieldSessionTotal = Number(sessionResult.total || 0);
      fieldSessionPage = Number(sessionResult.page || fieldSessionPage);
      fieldSessionPageSize = Number(sessionResult.pageSize || fieldSessionPageSize);
      fieldSessionCounts = { attention: 0, active: 0, completed: 0, all: 0, ...(sessionResult.counts || {}) };
      fieldSyncConflictItems = syncConflicts?.items || [];
      fieldSyncConflictCounts = { open: 0, resolved: 0, all: 0, ...(syncConflicts?.counts || {}) };
      document.getElementById('fieldMetricStations').textContent = fieldStations.length;
      document.getElementById('fieldMetricDevices').textContent = `${online}/${activeDevices.length}`;
      document.getElementById('fieldMetricReady').textContent = formalReady;
      document.getElementById('fieldMetricUpdates').textContent = fieldClientReleaseInfo?.available ? fieldOutdatedDeviceCount() : '—';
      document.getElementById('fieldMetricReviews').textContent = fieldSessionCounts.attention;
      renderFieldDevices();
      if (fieldDeviceDetailId && !fieldDeviceDetailModal.classList.contains('hidden')) showFieldDeviceDetail(fieldDeviceDetailId);
      document.getElementById('fieldSessionHint').textContent = `共 ${fieldSessionTotal} 条`;
      renderFieldSessions();
      renderFieldSyncConflicts();
      const stationOptions = `<option value="">请选择测试点</option>${fieldStations.map((item) => `<option value="${escapeHtml(item.id)}">${escapeHtml(item.stationCode)} · ${escapeHtml(item.name)}</option>`).join('')}`;
      document.getElementById('fieldDeviceStation').innerHTML = stationOptions;
      document.getElementById('fieldCalibrationStation').innerHTML = stationOptions;
      if (fieldQueueStationId !== 'all' && fieldQueueStationId !== '__unassigned__' && !fieldStations.some((station) => station.id === fieldQueueStationId)) fieldQueueStationId = 'all';
      const queueStationFilter = document.getElementById('fieldQueueStationFilter');
      queueStationFilter.innerHTML = `<option value="all">全部测试点</option><option value="__unassigned__">待分配学生</option>${fieldStations.map((item) => `<option value="${escapeHtml(item.id)}">${escapeHtml(item.stationCode)} · ${escapeHtml(item.name)}</option>`).join('')}`;
      queueStationFilter.value = fieldQueueStationId;
      const fieldTasks = Array.isArray(tasksResult) ? tasksResult : (tasksResult?.items || []);
      const todayValue = new Date(); todayValue.setHours(0, 0, 0, 0);
      const todayKey = `${todayValue.getFullYear()}-${String(todayValue.getMonth() + 1).padStart(2, '0')}-${String(todayValue.getDate()).padStart(2, '0')}`;
      const fieldTaskPriority = (item) => { const value = new Date(`${String(item.date || '').slice(0, 10)}T00:00:00`); if (!Number.isFinite(value.valueOf())) return Number.MAX_SAFE_INTEGER; const days = Math.round((value - todayValue) / 86_400_000); return days === 0 ? 0 : days < 0 ? 10_000 + Math.abs(days) : 20_000 + days; };
      const dispatchableTasks = fieldTasks.filter((item) => item.lifecycleStatus === 'published' && item.progressStatus !== '已完成').sort((left, right) => fieldTaskPriority(left) - fieldTaskPriority(right));
      if (!dispatchableTasks.some((item) => item.id === fieldDispatchTaskId)) fieldDispatchTaskId = dispatchableTasks[0]?.id || '';
      const dispatchSelect = document.getElementById('fieldDispatchTask');
      dispatchSelect.innerHTML = dispatchableTasks.length ? dispatchableTasks.map((item) => { const date = String(item.date || '').slice(0, 10); const timing = date === todayKey ? '今天' : date < todayKey ? '已延期' : '待开始'; return `<option value="${escapeHtml(item.id)}" ${item.id === fieldDispatchTaskId ? 'selected' : ''}>[${timing}] ${escapeHtml(item.title)} · ${escapeHtml(date)} · ${item.completedCount || 0}/${item.totalCount || 0}</option>`; }).join('') : '<option value="">暂无已发布任务</option>';
      const selectedTask = dispatchableTasks.find((item) => item.id === fieldDispatchTaskId);
      fieldSelectedTask = selectedTask || null;
      const protocol = selectedTask?.protocolSnapshot || null;
      const protocolItems = Array.isArray(protocol?.items) && protocol.items.length
        ? [...protocol.items].sort((left, right) => Number(left.sequenceNo || 0) - Number(right.sequenceNo || 0))
        : (selectedTask?.items || []).map((name, index) => ({ name, code: name, sequenceNo: index + 1 }));
      document.getElementById('fieldProtocolName').textContent = selectedTask ? `${protocol?.name || '当前任务测试方案'} · v${protocol?.version || '任务快照'}` : '暂无可运行测试方案';
      document.getElementById('fieldProtocolMeta').textContent = selectedTask ? `一次签到 · 一名学生 · 固定顺序 ${protocolItems.length} 项 · 一次提交` : '请先发布测评任务';
      document.getElementById('fieldProtocolItems').innerHTML = protocolItems.length
        ? protocolItems.map((item, index) => `<li><b>${Number(item.sequenceNo || index + 1)}</b><span>${escapeHtml(item.name || item.code || '未命名项目')}</span></li>`).join('')
        : '<li class="is-empty">测试方案尚未配置项目</li>';
      const selectedTaskDate = String(selectedTask?.date || '').slice(0, 10);
      const selectedTaskIsFuture = Boolean(selectedTaskDate && selectedTaskDate > todayKey);
      const planningStations = selectedTask ? fieldStations.filter((station) => fieldStationProfile(station).compatible && !['maintenance', 'paused', 'disabled'].includes(station.status) && activeDevices.some((device) => device.stationId === station.id)) : [];
      const taskReadyStations = planningStations.filter((station) => activeDevices.some((device) => device.stationId === station.id && device.readiness?.ready));
      fieldTaskPlanningStationCount = planningStations.length;
      fieldTaskReadyStationCount = taskReadyStations.length;
      const rebalanceButton = document.getElementById('fieldRebalanceQueue');
      rebalanceButton.disabled = !dispatchableTasks.length || !planningStations.length;
      rebalanceButton.textContent = taskReadyStations.length && !selectedTaskIsFuture ? '生成 / 重新分流' : '预生成候测名单';
      document.getElementById('fieldDispatchHint').textContent = !dispatchableTasks.length
        ? '当前没有可分流的已发布任务。'
        : !planningStations.length
          ? '没有与当前任务项目匹配且已绑定设备的测试点；请将多项目任务配置为“整套任务通道”。'
          : selectedTaskIsFuture
            ? `当前任务：${(selectedTask?.items || []).join('、')}。可提前生成候测名单；正式采集仍须通过设备、项目与签到门禁。`
            : !taskReadyStations.length
              ? `当前任务：${(selectedTask?.items || []).join('、')}。可先预分流；设备通过心跳、自检和标定前仍不能正式采集。`
              : `当前任务：${(selectedTask?.items || []).join('、')}。${taskReadyStations.length} 个匹配测试点已通过开测检查。`;
      summary.textContent = !selectedTask
        ? '暂无可调度的已发布任务'
        : taskReadyStations.length
          ? `${selectedTask.title} · ${taskReadyStations.length} 个匹配测试点已就绪`
          : planningStations.length
            ? `${selectedTask.title} · 可预分流，正式开测条件未完成`
            : `${selectedTask.title} · 尚无匹配测试点`;
      const queue = fieldDispatchTaskId ? await api(`/v1/admin/test-queues?taskId=${encodeURIComponent(fieldDispatchTaskId)}`) : [];
      document.getElementById('fieldQueueHint').textContent = fieldDispatchTaskId ? `共 ${(queue || []).length} 人` : '请选择任务';
      document.getElementById('fieldMetricQueue').textContent = (queue || []).filter((item) => ['waiting', 'called', 'checked_in', 'testing', 'retest'].includes(item.status)).length;
      fieldQueueItems = queue || [];
      const criticalQueueCount = fieldQueueItems.filter((item) => fieldQueueTimingSeverity(item) === 'critical').length;
      const warningQueueCount = fieldQueueItems.filter((item) => fieldQueueTimingSeverity(item) === 'warning').length;
      document.getElementById('fieldMetricQueueDetail').textContent = criticalQueueCount ? `${criticalQueueCount} 人严重积压` : warningQueueCount ? `${warningQueueCount} 人等待过久` : '名学生 · 流转正常';
      renderFieldStations();
      renderFieldQueue();
      renderFieldIssues();
      focusPendingFieldRuntimeTarget();
    } catch (error) { summary.textContent = error.message || '场地状态加载失败'; }
    finally {
      fieldOperationsLoading = false;
      if (fieldOperationsReloadPending) {
        fieldOperationsReloadPending = false;
        void loadFieldOperations();
      }
    }
  };
  const updateFieldRefreshTimer = () => {
    if (fieldRefreshTimer) { clearInterval(fieldRefreshTimer); fieldRefreshTimer = null; }
    if (!fieldModal.classList.contains('hidden')) fieldRefreshTimer = setInterval(() => { void loadFieldOperations(); }, 15_000);
  };
  new MutationObserver(updateFieldRefreshTimer).observe(fieldModal, { attributes: true, attributeFilter: ['class'] });
  fieldButton.addEventListener('click', () => { fieldModal.classList.remove('hidden'); updateFieldRefreshTimer(); void loadFieldClientRelease(); loadFieldOperations(); });
  document.addEventListener('click', async (event) => {
    const taskFieldButton = event.target.closest('[data-task-open-field]');
    if (!taskFieldButton) return;
    fieldDispatchTaskId = taskFieldButton.dataset.taskOpenField;
    fieldQueueFilter = 'active';
    document.getElementById('detailModal')?.classList.add('hidden');
    fieldModal.classList.remove('hidden');
    updateFieldRefreshTimer();
    await loadFieldClientRelease();
    await loadFieldOperations();
    document.getElementById('fieldQueueBoard')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  });
  document.getElementById('fieldOpsRefresh')?.addEventListener('click', loadFieldOperations);
  document.getElementById('fieldDispatchTask')?.addEventListener('change', (event) => { fieldDispatchTaskId = event.target.value; void loadFieldOperations(); });
  document.getElementById('fieldEditStationStatus')?.addEventListener('change', (event) => {
    const station = fieldStations.find((item) => item.id === fieldStationEditId);
    const changed = Boolean(station && event.target.value !== station.status);
    document.getElementById('fieldEditStationReasonField')?.classList.toggle('hidden', !changed);
    document.getElementById('fieldEditStationStatusHint').textContent = fieldStationStatusHint(event.target.value);
    if (changed) document.getElementById('fieldEditStationReason')?.focus();
  });
  document.getElementById('fieldQueueSearch')?.addEventListener('input', renderFieldQueue);
  document.getElementById('fieldQueueStationFilter')?.addEventListener('change', (event) => {
    fieldQueueStationId = event.target.value || 'all';
    renderFieldQueue();
  });
  document.getElementById('fieldSessionSearch')?.addEventListener('input', () => {
    if (fieldSessionSearchTimer) clearTimeout(fieldSessionSearchTimer);
    fieldSessionPage = 1;
    fieldSessionSearchTimer = setTimeout(() => { void loadFieldOperations(); }, 250);
  });
  document.getElementById('fieldQueueFilters')?.addEventListener('click', (event) => {
    const button = event.target.closest('[data-field-queue-filter]');
    if (!button) return;
    fieldQueueFilter = button.dataset.fieldQueueFilter;
    renderFieldQueue();
  });
  document.getElementById('fieldShowDisabledDevices')?.addEventListener('change', renderFieldDevices);
  document.getElementById('fieldSessionFilters')?.addEventListener('click', (event) => {
    const button = event.target.closest('[data-field-session-filter]');
    if (!button) return;
    fieldSessionFilter = button.dataset.fieldSessionFilter;
    fieldSessionPage = 1;
    void loadFieldOperations();
  });
  document.getElementById('fieldSyncConflictFilters')?.addEventListener('click', (event) => {
    const button = event.target.closest('[data-field-conflict-filter]');
    if (!button) return;
    fieldSyncConflictFilter = button.dataset.fieldConflictFilter;
    void loadFieldOperations();
  });
  document.getElementById('fieldSessionPager')?.addEventListener('click', (event) => {
    const button = event.target.closest('[data-field-session-page]');
    if (!button || button.disabled) return;
    const nextPage = Number(button.dataset.fieldSessionPage);
    const pages = Math.max(1, Math.ceil(fieldSessionTotal / fieldSessionPageSize));
    if (!Number.isInteger(nextPage) || nextPage < 1 || nextPage > pages || nextPage === fieldSessionPage) return;
    fieldSessionPage = nextPage;
    void loadFieldOperations();
  });
  document.getElementById('fieldIssueChips')?.addEventListener('click', (event) => {
    const issue = event.target.closest('[data-field-issue-target]');
    if (!issue) return;
    if (issue.dataset.fieldIssueTarget === 'sessions') { fieldSessionFilter = 'attention'; fieldSessionPage = 1; void loadFieldOperations(); }
    if (issue.dataset.fieldIssueTarget === 'queue') { fieldQueueFilter = 'active'; renderFieldQueue(); }
    if (issue.dataset.fieldIssueTarget === 'timing') { fieldQueueFilter = 'timing'; renderFieldQueue(); }
    if (issue.dataset.fieldIssueTarget === 'conflicts') { fieldSyncConflictFilter = 'open'; void loadFieldOperations(); }
    const target = document.getElementById({ stations: 'fieldStationBoard', devices: 'fieldDeviceBoard', sessions: 'fieldSessionBoard', queue: 'fieldQueueBoard', timing: 'fieldQueueBoard', conflicts: 'fieldSyncConflictBoard' }[issue.dataset.fieldIssueTarget]);
    target?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  });
  document.getElementById('fieldOpsPrimaryAction')?.addEventListener('click', (event) => {
    const targetName = event.currentTarget.dataset.fieldPrimaryTarget;
    if (targetName === 'task') {
      const select = document.getElementById('fieldDispatchTask');
      select?.closest('.field-dispatch-bar')?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      select?.focus({ preventScroll: true });
      return;
    }
    if (targetName === 'generate') { document.getElementById('fieldRebalanceQueue')?.click(); return; }
    if (targetName === 'sessions') { fieldSessionFilter = 'attention'; fieldSessionPage = 1; void loadFieldOperations(); }
    if (targetName === 'queue') { fieldQueueFilter = 'active'; renderFieldQueue(); }
    if (targetName === 'timing') { fieldQueueFilter = 'timing'; renderFieldQueue(); }
    if (targetName === 'conflicts') { fieldSyncConflictFilter = 'open'; void loadFieldOperations(); }
    const target = document.getElementById({ stations: 'fieldStationBoard', devices: 'fieldDeviceBoard', sessions: 'fieldSessionBoard', queue: 'fieldQueueBoard', timing: 'fieldQueueBoard', conflicts: 'fieldSyncConflictBoard' }[targetName]);
    target?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  });
  document.getElementById('fieldRebalanceQueue')?.addEventListener('click', async () => {
    try {
      const taskId = document.getElementById('fieldDispatchTask').value;
      if (!taskId) throw new Error('请选择已发布的测评任务');
      if (!window.confirm('将重新均衡候测学生。已叫号、签到或测试中的学生不会被移动，确认继续？')) return;
      const result = await api('/v1/admin/test-queues/rebalance', { method: 'POST', headers: { 'Idempotency-Key': `field-rebalance-${taskId}-${Date.now()}` }, body: JSON.stringify({ taskId }) });
      const stations = (result.dispatchStations || result.eligibleStations || []).map((item) => item.stationCode).join('、') || '无';
      const modeLabel = result.mode === 'pre_dispatch' ? '预分流' : '正式分流';
      document.getElementById('fieldDispatchHint').textContent = `${modeLabel}完成：本次调整 ${result.assignments?.length || 0} 人，测试点 ${stations}，未分配 ${result.unassignedCount || 0} 人。`;
      toast(`${modeLabel}完成：${result.assignments?.length || 0} 人；${result.mode === 'pre_dispatch' ? '设备就绪后才能开测' : '可在已就绪测试点开测'}`);
      await loadFieldOperations();
    } catch (error) { toast(error.message, true); }
  });
  document.getElementById('cancelFieldAssignment')?.addEventListener('click', () => fieldAssignmentModal.classList.add('hidden'));
  document.getElementById('cancelFieldIdentity')?.addEventListener('click', () => { fieldIdentityModal.classList.add('hidden'); fieldIdentityQueueAction = null; });
  document.getElementById('cancelFieldQueueDecision')?.addEventListener('click', () => { fieldQueueDecisionModal.classList.add('hidden'); fieldQueueDecisionAction = null; });
  document.getElementById('cancelFieldStationEdit')?.addEventListener('click', () => { fieldStationEditModal.classList.add('hidden'); fieldStationEditId = null; });
  document.getElementById('saveFieldStationEdit')?.addEventListener('click', async (event) => {
    const button = event.currentTarget;
    try {
      const station = fieldStations.find((item) => item.id === fieldStationEditId);
      if (!station) throw new Error('测试点信息已更新，请重新打开');
      const stationCode = String(document.getElementById('fieldEditStationCode').value || '').trim();
      const name = String(document.getElementById('fieldEditStationName').value || '').trim();
      const queueCapacity = Number(document.getElementById('fieldEditStationCapacity').value);
      const status = document.getElementById('fieldEditStationStatus').value;
      const reason = String(document.getElementById('fieldEditStationReason').value || '').trim();
      if (!stationCode) throw new Error('请填写测试点编码');
      if (!name) throw new Error('请填写测试点名称');
      if (!Number.isInteger(queueCapacity) || queueCapacity < 1 || queueCapacity > 500) throw new Error('队列容量必须在 1 到 500 之间');
      if (status !== station.status && !reason) throw new Error('改变测试点运行状态时必须填写原因');
      const payload = { stationCode, name, queueCapacity, itemCode: document.getElementById('fieldEditStationItem').value || null };
      if (status !== station.status) Object.assign(payload, { status, reason });
      button.disabled = true;
      await api(`/v1/admin/test-stations/${encodeURIComponent(station.id)}`, {
        method: 'PATCH',
        body: JSON.stringify(payload)
      });
      fieldStationEditModal.classList.add('hidden');
      fieldStationEditId = null;
      toast(`${name} 的测试点信息已保存`);
      await loadFieldOperations();
    } catch (error) { toast(error.message, true); }
    finally { button.disabled = false; }
  });
  document.getElementById('confirmFieldIdentity')?.addEventListener('click', async () => {
    const queueAction = fieldIdentityQueueAction;
    if (!queueAction) return;
    fieldIdentityQueueAction = null;
    fieldIdentityModal.classList.add('hidden');
    await submitFieldQueueTransition(queueAction, true);
  });
  document.getElementById('confirmFieldQueueDecision')?.addEventListener('click', async () => {
    const queueAction = fieldQueueDecisionAction;
    const reason = String(document.getElementById('fieldQueueDecisionReason').value || '').trim();
    if (!queueAction) return;
    if (!reason) { toast('请填写现场处理原因', true); document.getElementById('fieldQueueDecisionReason').focus(); return; }
    fieldQueueDecisionAction = null;
    fieldQueueDecisionModal.classList.add('hidden');
    await submitFieldQueueTransition(queueAction, false, reason);
  });
  document.getElementById('fieldAssignmentStation')?.addEventListener('change', (event) => {
    const station = fieldAssignmentItem ? eligibleAssignmentStations(fieldAssignmentItem).find((item) => item.id === event.target.value) : null;
    document.getElementById('fieldAssignmentCapacity').textContent = station ? `当前占用 ${station.load}/${station.capacity}，换点后 ${station.load + 1}/${station.capacity}` : '请选择目标测试点';
  });
  document.getElementById('confirmFieldAssignment')?.addEventListener('click', async () => {
    const button = document.getElementById('confirmFieldAssignment');
    try {
      if (!fieldAssignmentItem) throw new Error('学生队列信息已失效，请重新打开');
      const stationId = document.getElementById('fieldAssignmentStation').value;
      const reason = String(document.getElementById('fieldAssignmentReason').value || '').trim();
      if (!stationId) throw new Error('请选择目标测试点');
      if (!reason) throw new Error('请填写换点原因，便于现场追溯');
      button.disabled = true;
      const result = await api(`/v1/admin/test-queues/${encodeURIComponent(fieldAssignmentItem.id)}/assign`, {
        method: 'POST',
        body: JSON.stringify({ stationId, expectedVersion: Number(fieldAssignmentItem.stateVersion), reason })
      });
      fieldAssignmentModal.classList.add('hidden');
      toast(`${result.studentName || fieldAssignmentItem.studentName} 已调整到 ${result.stationCode}`);
      fieldAssignmentItem = null;
      await loadFieldOperations();
    } catch (error) { toast(error.message, true); }
    finally { button.disabled = false; }
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
      showFieldDeviceCredentials(result);
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
    const recallStudent = event.target.closest('[data-field-recall-device]');
    if (recallStudent?.dataset.fieldRecallDevice) {
      recallStudent.disabled = true;
      try {
        await api('/v1/admin/device-commands', {
          method: 'POST',
          headers: { 'Idempotency-Key': `field-recall-${recallStudent.dataset.fieldRecallQueue}-${Date.now()}` },
          body: JSON.stringify({
            deviceId: recallStudent.dataset.fieldRecallDevice,
            commandType: 'recall',
            payload: { queueEntryId: recallStudent.dataset.fieldRecallQueue, studentId: recallStudent.dataset.fieldRecallStudentId, studentName: recallStudent.dataset.fieldRecallStudent, requestedFrom: 'admin' },
            expiresAt: new Date(Date.now() + 120_000).toISOString()
          })
        });
        toast(`已提醒场地端再次呼叫 ${recallStudent.dataset.fieldRecallStudent}`);
      } catch (error) { toast(error.message, true); recallStudent.disabled = false; }
      return;
    }
    const stationFocus = event.target.closest('[data-field-station-focus]');
    if (stationFocus) {
      fieldQueueFilter = 'active';
      const search = document.getElementById('fieldQueueSearch');
      fieldQueueStationId = stationFocus.dataset.fieldStationFocus || 'all';
      if (search) search.value = '';
      const stationFilter = document.getElementById('fieldQueueStationFilter');
      if (stationFilter) stationFilter.value = fieldQueueStationId;
      renderFieldQueue();
      let targetRow = null;
      if (fieldQueueStationId === '__unassigned__') {
        const firstUnassigned = fieldQueueItems.find((entry) => !entry.stationId && fieldActiveQueueStatuses.includes(entry.status));
        if (firstUnassigned) targetRow = document.querySelector(`[data-field-queue-entry="${CSS.escape(firstUnassigned.id)}"]`);
      }
      document.getElementById('fieldQueueBoard')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      targetRow?.classList.add('is-focused');
      window.setTimeout(() => targetRow?.classList.remove('is-focused'), 1800);
      return;
    }
    const stationEdit = event.target.closest('[data-field-station-edit]');
    if (stationEdit) {
      const station = fieldStations.find((item) => item.id === stationEdit.dataset.fieldStationEdit);
      if (!station) { toast('测试点信息已更新，请刷新后重试', true); return; }
      fieldStationEditId = station.id;
      document.getElementById('fieldEditStationCode').value = station.stationCode || '';
      document.getElementById('fieldEditStationName').value = station.name || '';
      document.getElementById('fieldEditStationCapacity').value = Number(station.queueCapacity || 20);
      document.getElementById('fieldEditStationItem').innerHTML = fieldStationProfileOptions(station.itemCode);
      document.getElementById('fieldEditStationStatus').innerHTML = fieldStationStatusOptions(station);
      document.getElementById('fieldEditStationStatusHint').textContent = `${fieldStationStatusHint(station.status)}${station.statusReason ? ` 当前说明：${station.statusReason}` : ''}`;
      document.getElementById('fieldEditStationReason').value = '';
      document.getElementById('fieldEditStationReasonField').classList.add('hidden');
      fieldStationEditModal.classList.remove('hidden');
      document.getElementById('fieldEditStationName').focus();
      return;
    }
    const handoffStudent = event.target.closest('[data-field-handoff-student]');
    if (handoffStudent?.dataset.fieldHandoffStudent) {
      fieldQueueFilter = 'active';
      const handoffEntry = fieldQueueItems.find((entry) => entry.id === handoffStudent.dataset.fieldHandoffStudent);
      fieldQueueStationId = handoffEntry?.stationId || '__unassigned__';
      const search = document.getElementById('fieldQueueSearch');
      if (search) search.value = '';
      const stationFilter = document.getElementById('fieldQueueStationFilter');
      if (stationFilter) stationFilter.value = fieldQueueStationId;
      renderFieldQueue();
      const row = document.querySelector(`[data-field-queue-entry="${CSS.escape(handoffStudent.dataset.fieldHandoffStudent)}"]`);
      row?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      row?.classList.add('is-focused');
      window.setTimeout(() => row?.classList.remove('is-focused'), 1800);
      return;
    }
    const deviceDetail = event.target.closest('[data-field-device-detail]');
    if (deviceDetail) {
      showFieldDeviceDetail(deviceDetail.dataset.fieldDeviceDetail);
      return;
    }
    const saveDevice = event.target.closest('[data-field-save-device]');
    if (saveDevice) {
      const item = fieldDeviceItems.find((device) => device.id === saveDevice.dataset.fieldSaveDevice);
      if (!item) { toast('设备信息已更新，请刷新后重试', true); return; }
      const name = String(document.getElementById('fieldEditDeviceName')?.value || '').trim();
      const deviceCode = String(document.getElementById('fieldEditDeviceCode')?.value || '').trim();
      if (!name) { toast('请填写设备名称', true); document.getElementById('fieldEditDeviceName')?.focus(); return; }
      if (!deviceCode) { toast('请填写设备编码', true); document.getElementById('fieldEditDeviceCode')?.focus(); return; }
      saveDevice.disabled = true;
      try {
        await api(`/v1/admin/test-devices/${encodeURIComponent(item.id)}`, {
          method: 'PATCH',
          body: JSON.stringify({
            name,
            deviceCode,
            stationId: document.getElementById('fieldEditDeviceStation')?.value || null,
            serialNumber: String(document.getElementById('fieldEditDeviceSerial')?.value || '').trim() || null
          })
        });
        toast(`${name} 的设备信息已保存`);
        await loadFieldOperations();
      } catch (error) { toast(error.message, true); saveDevice.disabled = false; }
      return;
    }
    const deviceGuide = event.target.closest('[data-field-device-guide]');
    if (deviceGuide) {
      fieldDeviceDetailModal.classList.add('hidden');
      showFieldDeviceGuide(deviceGuide.dataset.fieldDeviceGuide, deviceGuide.dataset.fieldDeviceCode || '场地设备');
      return;
    }
    const resolveConflict = event.target.closest('[data-field-resolve-conflict]');
    if (resolveConflict) {
      const note = window.prompt(`请填写核对结论。确认后，“${resolveConflict.dataset.fieldResolveDevice}”下次同步会自动解除本地冲突标记：`, '已核对中央队列、现场记录和设备状态，以中央当前状态为准');
      if (note === null || !note.trim()) return;
      resolveConflict.disabled = true;
      try {
        await api(`/v1/admin/field-sync-conflicts/${encodeURIComponent(resolveConflict.dataset.fieldResolveConflict)}/resolve`, { method: 'POST', body: JSON.stringify({ note: note.trim() }) });
        toast('同步冲突已确认，场地端下次联网将自动解除标记');
        await loadFieldOperations();
      } catch (error) { toast(error.message, true); resolveConflict.disabled = false; }
      return;
    }
    const queueHistory = event.target.closest('[data-field-queue-history]');
    if (queueHistory) {
      await showFieldQueueHistory(queueHistory.dataset.fieldQueueHistory);
      return;
    }
    const assignmentAction = event.target.closest('[data-field-assign-id]');
    if (assignmentAction) {
      const item = fieldQueueItems.find((entry) => entry.id === assignmentAction.dataset.fieldAssignId);
      if (!item) { toast('队列信息已更新，请刷新后重试', true); return; }
      const options = eligibleAssignmentStations(item);
      const available = options.filter((station) => station.available);
      if (!available.length) { toast(options.length ? '其他已就绪测试点队列均已满' : '当前没有其他已通过开测检查的测试点', true); return; }
      fieldAssignmentItem = item;
      document.getElementById('fieldAssignmentStudent').innerHTML = `<span class="field-student-avatar">${escapeHtml(String(item.studentName || '学').slice(0, 1))}</span><div><strong>${escapeHtml(item.studentName)}</strong><small>${escapeHtml(item.className)} · 当前 ${escapeHtml(item.stationCode || '待分配')} · ${escapeHtml(queueStatusLabels[item.status] || item.status)}</small></div>`;
      document.getElementById('fieldAssignmentStation').innerHTML = available.map((station) => `<option value="${escapeHtml(station.id)}">${escapeHtml(station.stationCode)} · ${escapeHtml(station.name)}（${station.load}/${station.capacity}）</option>`).join('');
      document.getElementById('fieldAssignmentReason').value = '';
      document.getElementById('fieldAssignmentCapacity').textContent = `当前占用 ${available[0].load}/${available[0].capacity}，换点后 ${available[0].load + 1}/${available[0].capacity}`;
      fieldAssignmentModal.classList.remove('hidden');
      document.getElementById('fieldAssignmentReason').focus();
      return;
    }
    const queueAction = event.target.closest('[data-field-queue-id]');
    if (queueAction) {
      const status = queueAction.dataset.fieldQueueStatus;
      if (status === 'checked_in') {
        fieldIdentityQueueAction = queueAction;
        document.getElementById('fieldIdentityName').textContent = queueAction.dataset.fieldQueueStudent || '姓名待补';
        document.getElementById('fieldIdentityClass').textContent = queueAction.dataset.fieldQueueClass || '班级待补';
        document.getElementById('fieldIdentityStudentNo').textContent = queueAction.dataset.fieldQueueStudentNo || '学籍号待补';
        document.getElementById('fieldIdentityGender').textContent = queueAction.dataset.fieldQueueGender || '性别待补';
        document.getElementById('fieldIdentityBirthDate').textContent = queueAction.dataset.fieldQueueBirthDate || '生日待补';
        fieldIdentityModal.classList.remove('hidden');
        document.getElementById('confirmFieldIdentity').focus();
        return;
      }
      if (['absent', 'skipped', 'cancelled', 'retest'].includes(status)) {
        const item = fieldQueueItems.find((entry) => entry.id === queueAction.dataset.fieldQueueId);
        const decisions = {
          absent: { action: '标记缺席', impact: '学生将从当前候测流程移出；后台仍可恢复候测。确认前应核对现场并完成必要的再次呼叫。', placeholder: '例如：现场再次呼叫两次仍未到场' },
          skipped: { action: '跳过本轮', impact: '学生将暂时离开当前叫号流程；后台可恢复候测。请说明跳过原因。', placeholder: '例如：学生临时离场，先测试下一位' },
          cancelled: { action: '取消补测', impact: '学生将退出本次补测队列；如需重新加入，须由后台再次安排。', placeholder: '例如：经教师确认本任务无需继续补测' },
          retest: { action: '安排补测', impact: '当前完成状态将转入待重测，后续需要重新叫号、核验身份并采集。', placeholder: '例如：成绩复核发现设备证据不完整' }
        };
        const decision = decisions[status];
        fieldQueueDecisionAction = queueAction;
        document.getElementById('fieldQueueDecisionStudent').innerHTML = `<span class="field-student-avatar">${escapeHtml(String(queueAction.dataset.fieldQueueStudent || '学').slice(0, 1))}</span><div><strong>${escapeHtml(queueAction.dataset.fieldQueueStudent || '该学生')}</strong><small>${escapeHtml(item?.className || '班级待补')} · ${escapeHtml(item ? fieldQueueTimingLabel(item) : queueStatusLabels[item?.status] || '状态待确认')}</small></div>`;
        document.getElementById('fieldQueueDecisionImpact').innerHTML = `<strong>${escapeHtml(decision.action)}</strong><span>${escapeHtml(decision.impact)}</span>`;
        document.getElementById('fieldQueueDecisionReason').value = '';
        document.getElementById('fieldQueueDecisionReason').placeholder = decision.placeholder;
        document.getElementById('confirmFieldQueueDecision').textContent = `确认${decision.action}`;
        fieldQueueDecisionModal.classList.remove('hidden');
        document.getElementById('fieldQueueDecisionReason').focus();
        return;
      }
      await submitFieldQueueTransition(queueAction);
      return;
    }
    const deviceStatus = event.target.closest('[data-field-device-status]');
    if (deviceStatus) {
      const nextStatus = deviceStatus.dataset.fieldDeviceStatus;
      const deviceName = deviceStatus.dataset.fieldDeviceName || '该设备';
      const confirmation = nextStatus === 'disabled'
        ? window.confirm(`确认停用“${deviceName}”？停用后设备密钥请求会立即失效，未处理指令也会取消。`)
        : window.confirm(`确认恢复“${deviceName}”？设备需要重新发送心跳后才会显示在线。`);
      if (!confirmation) return;
      try {
        await api(`/v1/admin/test-devices/${encodeURIComponent(deviceStatus.dataset.fieldDeviceId)}`, { method: 'PATCH', body: JSON.stringify({ status: nextStatus, reason: nextStatus === 'disabled' ? '后台现场中控停用历史设备' : '后台现场中控恢复设备' }) });
        toast(nextStatus === 'disabled' ? `${deviceName} 已停用` : `${deviceName} 已恢复为离线等待连接`);
        await loadFieldOperations();
      } catch (error) { toast(error.message, true); }
      return;
    }
    const rotate = event.target.closest('[data-field-rotate-device]');
    if (rotate) {
      if (!window.confirm('轮换后该电脑端必须立即更新密钥；确认继续？')) return;
      try {
        const result = await api(`/v1/admin/test-devices/${encodeURIComponent(rotate.dataset.fieldRotateDevice)}/rotate-key`, { method: 'POST', body: '{}' });
        const credentialTarget = fieldDeviceDetailModal.classList.contains('hidden') ? 'fieldDeviceKeyNotice' : 'fieldDeviceDetailCredential';
        showFieldDeviceCredentials(result, true, credentialTarget);
        toast('设备密钥已轮换，旧密钥已失效'); await loadFieldOperations();
      } catch (error) { toast(error.message, true); }
      return;
    }
    const copyConnection = event.target.closest('[data-field-copy-connection]');
    if (copyConnection) {
      const marker = copyConnection.dataset.fieldCopyConnection;
      const apiBaseUrl = document.getElementById(`${marker}-url`)?.textContent || '';
      const deviceId = document.getElementById(`${marker}-id`)?.textContent || '';
      const deviceKey = document.getElementById(`${marker}-key`)?.textContent || '';
      if (!apiBaseUrl || !deviceId || !deviceKey) { toast('接入信息已失效，请轮换设备密钥后重新复制', true); return; }
      try {
        await fieldCopyText(JSON.stringify({ schemaVersion: 'xiangshang-field-connection/v1', apiBaseUrl, deviceId, deviceKey }));
        toast('三项接入信息已复制；请立即粘贴到 Windows 客户端');
      } catch { toast('复制失败，请改为逐项复制', true); }
      return;
    }
    const copyCredential = event.target.closest('[data-field-copy-target]');
    if (copyCredential) {
      const value = document.getElementById(copyCredential.dataset.fieldCopyTarget)?.textContent || '';
      try { await fieldCopyText(value); toast('已复制到剪贴板'); }
      catch { toast('复制失败，请手动选择内容复制', true); }
      return;
    }
    const control = event.target.closest('[data-field-control-device]');
    if (control) {
      const commandType = control.dataset.fieldControlCommand;
      const deviceName = control.dataset.fieldControlName || '该设备';
      let reason = '';
      if (commandType === 'pause' || commandType === 'stop') {
        const suppliedReason = window.prompt(commandType === 'stop' ? `请填写停止“${deviceName}”的原因：` : `请填写暂停“${deviceName}”的原因：`, '');
        if (suppliedReason === null || !suppliedReason.trim()) return;
        reason = suppliedReason.trim();
      } else if (!window.confirm(`确认恢复“${deviceName}”的现场操作？`)) return;
      if (commandType === 'stop' && !window.confirm(`停止会锁定“${deviceName}”的所有新操作，确认继续？`)) return;
      control.disabled = true;
      try {
        await api('/v1/admin/device-commands', { method: 'POST', headers: { 'Idempotency-Key': `field-control-${control.dataset.fieldControlDevice}-${commandType}-${Date.now()}` }, body: JSON.stringify({ deviceId: control.dataset.fieldControlDevice, commandType, payload: { reason, requestedFrom: 'admin' } }) });
        toast(commandType === 'resume' ? `${deviceName} 已恢复运行` : commandType === 'stop' ? `${deviceName} 已停止` : `${deviceName} 已暂停`);
        await loadFieldOperations();
      } catch (error) { toast(error.message, true); control.disabled = false; }
      return;
    }
    const command = event.target.closest('[data-field-command-device]');
    if (command) {
      try { await api('/v1/admin/device-commands', { method: 'POST', body: JSON.stringify({ deviceId: command.dataset.fieldCommandDevice, commandType: 'refresh_config', payload: { requestedFrom: 'admin' } }) }); toast('配置同步指令已下发'); await loadFieldOperations(); } catch (error) { toast(error.message, true); }
      return;
    }
    const sessionReview = event.target.closest('[data-field-session-review]');
    if (sessionReview) {
      const action = sessionReview.dataset.fieldSessionReview;
      const reason = window.prompt(action === 'approve' ? '填写复核说明（修改成绩时必填，可留空）：' : '请填写安排补测的原因：', '');
      if (reason === null || (action === 'retest' && !reason.trim())) return;
      if (!window.confirm(action === 'approve' ? '确认这些成绩与证据一致，并完成本次复核？' : '确认否决本次结果并将学生加入补测队列？')) return;
      const scores = action === 'approve' ? [...document.querySelectorAll('[data-field-review-score-id]')].map((input) => ({ scoreId: input.dataset.fieldReviewScoreId, score: Number(input.value) })) : [];
      sessionReview.disabled = true;
      try {
        const result = await api(`/v1/admin/test-sessions/${encodeURIComponent(sessionReview.dataset.fieldReviewSessionId)}/review`, { method: 'POST', headers: { 'Idempotency-Key': `field-session-review-${sessionReview.dataset.fieldReviewSessionId}-${action}-${Date.now()}` }, body: JSON.stringify({ action, reason, scores }) });
        toast(action === 'approve' ? `已确认 ${result.reviewedScores} 项成绩` : '已安排补测并同步更新候测队列');
        detailModal.classList.add('hidden'); fieldModal.classList.remove('hidden'); document.body.classList.add('modal-open');
        await loadFieldOperations();
      } catch (error) { toast(error.message, true); sessionReview.disabled = false; }
      return;
    }
    const sessionRecovery = event.target.closest('[data-field-session-recover]');
    if (sessionRecovery) {
      const studentName = sessionRecovery.dataset.fieldSessionStudent || '该学生';
      const reason = window.prompt(`请填写收口 ${studentName} 异常会话的原因：`, '场地设备离线，原采集上下文无法安全恢复');
      if (reason === null || !reason.trim()) return;
      if (!window.confirm(`确认结束 ${studentName} 的异常会话并安排补测？\n\n之后到达的旧成绩不会覆盖这次处置。`)) return;
      sessionRecovery.disabled = true;
      try {
        await api(`/v1/admin/test-sessions/${encodeURIComponent(sessionRecovery.dataset.fieldSessionRecover)}/recover`, {
          method: 'POST', headers: { 'Idempotency-Key': `field-session-recover-${sessionRecovery.dataset.fieldSessionRecover}-${Date.now()}` }, body: JSON.stringify({ reason: reason.trim() })
        });
        toast(`${studentName} 的异常会话已收口，已转入补测队列`);
        detailModal.classList.add('hidden'); fieldModal.classList.remove('hidden'); document.body.classList.add('modal-open');
        await loadFieldOperations();
      } catch (error) { toast(error.message, true); sessionRecovery.disabled = false; }
      return;
    }
    const session = event.target.closest('[data-field-session-id]');
    if (!session) return;
    try {
      const detail = await api(`/v1/admin/test-sessions/${encodeURIComponent(session.dataset.fieldSessionId)}`);
      const title = document.getElementById('detailTitle'); const subtitle = document.getElementById('detailSubtitle'); const body = document.getElementById('detailBody');
      title.textContent = `${detail.studentName} · 场地会话`; subtitle.textContent = `${detail.className || '班级待补'} · 第 ${detail.attempt_no || detail.attemptNo || 1} 次 · ${fieldSessionStatus(detail.status)}`;
      const activeEvidenceCount = Number(detail.evidenceCount || 0);
      const totalEvidenceCount = Number(detail.totalEvidenceCount || detail.evidence.length || 0);
      const evidenceMissing = totalEvidenceCount === 0 && ['completed', 'needs_review'].includes(detail.status);
      const evidenceExpired = totalEvidenceCount > 0 && activeEvidenceCount === 0;
      const activeSession = ['created', 'checked_in', 'testing'].includes(detail.status);
      const canRecover = activeSession && detail.recoveryEligible === true;
      const evidenceSummary = detail.evidence.length ? detail.evidence.map((evidence) => evidence.purgedAt ? `${escapeHtml(fieldEvidenceType(evidence.evidenceType))}：已按保留期限清理` : `${escapeHtml(fieldEvidenceType(evidence.evidenceType))}：保留至 ${fieldNow(evidence.retentionUntil)}`).join(' · ') : evidenceMissing ? '本次成绩从未关联可复核证据，请勿直接发布，需安排补测。' : '证据仍在采集或同步中';
      const canApprove = detail.status === 'needs_review' && activeEvidenceCount > 0;
      const canRetest = ['needs_review', 'completed'].includes(detail.status);
      const scoreRows = detail.scores.length ? detail.scores.map((score) => `<label class="field-review-score"><span><strong>${escapeHtml(score.item)}</strong><small>置信度 ${Math.round(Number(score.confidence) * 100)}% · ${score.reviewStatus === 'passed' ? '已通过' : '待复核'}</small></span><input data-field-review-score-id="${escapeHtml(score.id)}" type="number" min="0" max="5" step="0.1" value="${Number(score.score).toFixed(1)}" ${detail.status === 'needs_review' ? '' : 'disabled'}></label>`).join('') : '<div class="field-empty">尚未提交成绩</div>';
      const reviewActions = canApprove || canRetest ? `<div class="field-review-actions">${detail.status === 'needs_review' ? `<button class="primary-btn" data-field-session-review="approve" data-field-review-session-id="${escapeHtml(detail.id)}" type="button" ${canApprove ? '' : `disabled title="${evidenceExpired ? '证据已过保留期，不能确认成绩' : '缺少证据，不能确认成绩'}"`}>确认成绩有效</button>` : ''}${canRetest ? `<button class="secondary-btn" data-field-session-review="retest" data-field-review-session-id="${escapeHtml(detail.id)}" type="button">安排补测</button>` : ''}</div>` : '';
      const recoveryPanel = activeSession ? `<section class="field-session-recovery ${canRecover ? 'is-ready' : 'is-blocked'}"><div><strong>${canRecover ? '检测到设备中断' : '当前会话仍由在线设备接管'}</strong><span>${canRecover ? `设备 ${escapeHtml(detail.deviceName || detail.deviceCode || '未记录')} 已离线或已停止，可将本会话收口为已中止并安排补测。` : `最近心跳 ${fieldNow(detail.deviceLastHeartbeatAt)}。如确认设备无法继续，请先在设备详情中“停止现场操作”。`}</span></div>${canRecover ? `<button class="secondary-btn danger-text" data-field-session-recover="${escapeHtml(detail.id)}" data-field-session-student="${escapeHtml(detail.studentName)}" type="button">结束异常会话并安排补测</button>` : ''}</section>` : '';
      const timeline = detail.events.length ? detail.events.slice(-10).map((item) => `<li><span>${escapeHtml(fieldEventType(item.eventType))}</span><time>${fieldNow(item.happenedAt)}</time></li>`).join('') : '<li><span>没有采集事件</span></li>';
      const reviewHistory = detail.reviews?.length ? detail.reviews.slice(-14).map((item) => `<li><span><strong>${item.action === 'approve' ? '确认成绩' : '安排补测'}</strong> · ${escapeHtml(item.item)}${Number(item.oldScore) !== Number(item.newScore) ? ` · ${Number(item.oldScore).toFixed(1)} → ${Number(item.newScore).toFixed(1)}` : ''}<small>${escapeHtml(item.reviewerName || '复核人员')} · ${escapeHtml(item.reason || '未填写说明')}</small></span><time>${fieldNow(item.createdAt)}</time></li>`).join('') : '<li><span>尚无人工复核记录</span></li>';
      body.innerHTML = `<div class="detail-grid"><div><span>学生身份</span><strong>${escapeHtml(detail.studentNo || '学籍号待补')} · ${escapeHtml(detail.gender || '性别待补')} · ${escapeHtml(detail.birthDate ? dateText(detail.birthDate) : '生日待补')}</strong></div><div><span>测试点 / 设备</span><strong>${escapeHtml(detail.stationCode || '未分配')} / ${escapeHtml(detail.deviceName || detail.deviceCode || '未记录')}</strong></div><div><span>开始 / 结束</span><strong>${fieldNow(detail.started_at || detail.startedAt)} / ${fieldNow(detail.ended_at || detail.endedAt)}</strong></div><div><span>规则 / 标定</span><strong>${escapeHtml(detail.rule_version || detail.ruleVersion || '—')} / ${escapeHtml(detail.calibration_version || detail.calibrationVersion || '—')}</strong></div></div>${recoveryPanel}<div class="field-review-score-list"><div class="field-review-heading"><strong>成绩复核</strong><span>低置信度项目需核对证据后确认</span></div>${scoreRows}</div><div class="detail-note${evidenceMissing || evidenceExpired && detail.status === 'needs_review' ? ' warning' : ''}">证据状态：${evidenceSummary}</div>${reviewActions}<div class="field-audit-columns"><section><h4>采集时间线</h4><ul class="field-audit-list">${timeline}</ul></section><section><h4>人工复核记录</h4><ul class="field-audit-list">${reviewHistory}</ul></section></div>`;
      fieldModal.classList.add('hidden');
      detailModal.classList.remove('hidden'); document.body.classList.add('modal-open');
    } catch (error) { toast(error.message, true); }
  });
})();
