(() => {
  const root = document.getElementById('overviewSection');
  if (!root) return;

  const workspaceMeta = {
    overview: { title: '学校数据总览', subtitle: '聚焦今日进度、风险和需要立即处理的事项。' },
    tasks: { title: '测评任务', subtitle: '创建、发布并跟踪每个测评批次的现场进度。' },
    students: { title: '学生档案', subtitle: '按学生查看身份、班级、测评状态和诊断结果。' },
    reports: { title: '报告中心', subtitle: '集中复核风险、数据完整性和报告发布状态。' },
    analysis: { title: '数据分析', subtitle: '比较年级完成度、风险分布和任务趋势。' },
    content: { title: '内容运营', subtitle: '编排课程、活动、专家和通知的发布版本。' },
    settings: { title: '系统与运营', subtitle: '管理账户、通知、审计和后台运行状态。' }
  };
  const selectors = {
    overview: ['.dashboard-hero', '.metric-grid', '#operationsSection'],
    tasks: ['#tasksSection', '#trendSection'],
    students: ['#studentsSection'],
    reports: ['#reportsSection'],
    analysis: ['.layout-main', '#trendSection'],
    content: ['#contentSection'],
    settings: ['#accountsSection', '#settingsSection']
  };
  const managedSelectors = [...new Set(Object.values(selectors).flat())];
  const actionWorkspaces = {
    createTaskBtn: ['overview', 'tasks'],
    assessmentStandardsBtn: ['tasks', 'settings'],
    organizationBtn: ['students', 'settings'],
    fieldOperationsBtn: ['overview', 'tasks']
  };
  let activeWorkspace = 'overview';

  const resolveManagedNodes = () => managedSelectors
    .flatMap((selector) => [...root.querySelectorAll(`:scope > ${selector}`)]);

  function applyWorkspace(section, options = {}) {
    if (section === 'field') {
      document.getElementById('fieldOperationsBtn')?.click();
      return;
    }
    if (!workspaceMeta[section]) section = 'overview';
    activeWorkspace = section;
    root.dataset.workspace = section;

    const visible = new Set((selectors[section] || [])
      .flatMap((selector) => [...root.querySelectorAll(`:scope > ${selector}`)]));
    resolveManagedNodes().forEach((node) => node.classList.toggle('workspace-surface-hidden', !visible.has(node)));

    const meta = workspaceMeta[section];
    const heading = root.querySelector('.page-heading h1');
    const subtitle = root.querySelector('.page-heading p');
    const crumb = document.querySelector('.crumb strong');
    if (heading) heading.textContent = meta.title;
    if (subtitle) {
      subtitle.dataset.workspaceText = meta.subtitle;
      subtitle.textContent = section === 'overview' && subtitle.dataset.latestUpdate
        ? subtitle.dataset.latestUpdate
        : meta.subtitle;
    }
    if (crumb) crumb.textContent = meta.title;
    document.querySelectorAll('.nav-item[data-section]').forEach((node) => {
      node.classList.toggle('active', node.dataset.section === section);
      node.setAttribute('aria-current', node.dataset.section === section ? 'page' : 'false');
    });
    Object.entries(actionWorkspaces).forEach(([id, workspaces]) => {
      document.getElementById(id)?.classList.toggle('workspace-action-hidden', !workspaces.includes(section));
    });
    const search = document.getElementById('globalSearch');
    if (search) search.placeholder = section === 'tasks' ? '搜索任务...' : section === 'students' ? '搜索学生...' : '搜索学生、任务...';
    document.getElementById('sidebar')?.classList.remove('open');
    if (options.scroll !== false) window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  document.addEventListener('click', (event) => {
    const trigger = event.target.closest('[data-section]');
    if (!trigger) return;
    applyWorkspace(trigger.dataset.section);
  }, true);

  const observer = new MutationObserver(() => applyWorkspace(activeWorkspace, { scroll: false }));
  observer.observe(root, { childList: true });
  window.adminOpenWorkspace = applyWorkspace;
  applyWorkspace('overview', { scroll: false });
})();
