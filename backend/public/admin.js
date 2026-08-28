const icons = {
  spark:
    '<path d="m12 2 1.6 6.4L20 10l-6.4 1.6L12 18l-1.6-6.4L4 10l6.4-1.6L12 2Z"/><path d="m19 16 .7 2.3L22 19l-2.3.7L19 22l-.7-2.3L16 19l2.3-.7L19 16Z"/>',
  shield:
    '<path d="M12 3 20 6v5c0 5-3.4 8.2-8 10-4.6-1.8-8-5-8-10V6l8-3Z"/><path d="m8.5 12 2.2 2.2 4.8-5"/>',
  chart:
    '<path d="M4 19V5M4 19h17"/><path d="M8 16v-4M12 16V8M16 16V5M20 16v-7"/>',
  layers:
    '<path d="m12 3 9 5-9 5-9-5 9-5Z"/><path d="m3 12 9 5 9-5M3 16l9 5 9-5"/>',
  dashboard:
    '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
  clipboard:
    '<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4.5V3h6v1.5M8 10h8M8 14h6"/>',
  users:
    '<path d="M16 20v-1.5a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4V20M9 10a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7ZM17 11a3 3 0 1 0-1-5.8M22 20v-1.5a4 4 0 0 0-3-3.8"/>',
  report: '<path d="M6 3h9l3 3v15H6z"/><path d="M15 3v4h4M9 12h6M9 16h6"/>',
  settings:
    '<path d="M12 15.2a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4Z"/><path d="M19 12a7 7 0 0 0-.4-2.2l1.5-1.5-2.1-2.1-1.5 1.5A7 7 0 0 0 14 7.3V5h-3v2.3a7 7 0 0 0-2.2.9L7.3 6.2 5.2 8.3l1.5 1.5A7 7 0 0 0 6.3 12H4v3h2.3a7 7 0 0 0 .9 2.2l-1.5 1.5 2.1 2.1 1.5-1.5a7 7 0 0 0 2.2.9V22h3v-2.3a7 7 0 0 0 2.2-.9l1.5 1.5 2.1-2.1-1.5-1.5a7 7 0 0 0 .9-2.2H22v-3h-3Z"/>',
  logout: '<path d="M10 17 15 12 10 7M15 12H3M21 3v18"/>',
  menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
  search: '<circle cx="11" cy="11" r="6"/><path d="m16 16 4 4"/>',
  refresh:
    '<path d="M20 11a8 8 0 0 0-14-4L4 9M4 5v4h4M4 13a8 8 0 0 0 14 4l2-2M20 19v-4h-4"/>',
  bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9ZM10 21h4"/>',
  school:
    '<path d="m3 10 9-5 9 5-9 5-9-5Z"/><path d="M7 12v5c3 2 7 2 10 0v-5M21 10v6"/>',
  location:
    '<path d="M20 10c0 5-8 11-8 11S4 15 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="2.5"/>',
  calendar:
    '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 10h18"/>',
  flag: '<path d="M5 21V4M5 5c6-4 8 4 14 0v9c-6 4-8-4-14 0"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  chevron: '<path d="m9 18 6-6-6-6"/>',
  close: '<path d="m6 6 12 12M18 6 6 18"/>',
  send: '<path d="m22 2-7 20-4-9-9-4 20-7Z"/><path d="M22 2 11 13"/>',
};
const icon = (name) =>
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name] || ""}</svg>`;
document
  .querySelectorAll("[data-icon]")
  .forEach((node) => (node.innerHTML = icon(node.dataset.icon)));
const $ = (id) => document.getElementById(id);
const escapeHtml = (value) =>
  String(value ?? "").replace(
    /[&<>'"]/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[
        c
      ],
  );
const state = {
  token: "",
  schoolId: "school-1",
  dashboard: null,
  gradeStats: [],
  classStats: [],
  reports: [],
  search: "",
  syncIssues: [],
};
const refreshAccessToken = async () => {
  try {
    const response = await fetch("/v1/auth/refresh", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    });
    if (!response.ok) return false;
    const payload = await response.json();
    state.token = payload.data.accessToken;
    applyProfile(payload.data.user);
    return true;
  } catch {
    return false;
  }
};
const authEntry = (path) =>
  ["/v1/auth/login", "/v1/auth/mfa/totp", "/v1/auth/mfa/enroll/setup", "/v1/auth/mfa/enroll/confirm", "/v1/auth/refresh", "/v1/auth/register"].includes(path);
const api = async (path, options = {}, canRefresh = true) => {
  const res = await fetch(path, {
    credentials: "same-origin",
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(state.token ? { Authorization: "Bearer " + state.token } : {}),
      ...(options.headers || {}),
    },
  });
  let payload = {};
  try {
    payload = await res.json();
  } catch {}
  if (res.status === 401 && canRefresh && !authEntry(path)) {
    if (await refreshAccessToken()) return api(path, options, false);
  }
  if (res.status === 401 && authEntry(path))
    throw new Error(payload.message || "账号或密码错误");
  if (res.status === 401) {
    state.token = "";
    showLogin();
    throw new Error("登录已过期，请重新登录");
  }
  if (!res.ok) throw new Error(payload.message || "请求失败");
  return payload.data;
};
const dateText = (value) =>
  String(value || "")
    .slice(0, 10)
    .replace(/-/g, ".");
const percent = (n) => `${Math.round(Number(n) || 0)}%`;
const statusClass = (value) => {
  const s = String(value || "");
  if (s === "未完成" || s === "已关闭") return "review";
  if (s.includes("完成") || s === "published") return "done";
  if (s.includes("复核") || s.includes("关注") || s === "attention")
    return "review";
  if (s.includes("高") || s === "high") return "high";
  if (s.includes("发布") || s.includes("签到") || s === "pending")
    return "pending";
  return "gray";
};
function toast(message, error = false) {
  const node = $("toast");
  node.textContent = message;
  node.className = `toast${error ? " error" : ""}`;
  setTimeout(() => node.classList.add("hidden"), 2800);
}
function showLogin() {
  $("loginView").classList.remove("hidden");
  $("appView").classList.add("hidden");
}
function showApp() {
  $("loginView").classList.add("hidden");
  $("appView").classList.remove("hidden");
}
function applyProfile(profile) {
  if (!profile) return;
  const initial = (profile.avatarInitials || profile.name || "演").slice(0, 1);
  $("sideAvatar").textContent = initial;
  $("topAvatar").textContent = initial;
  $("sideName").textContent = profile.name || "工作台用户";
  $("sideRole").textContent = profile.role || "学校管理员";
}
function calculatePendingBreakdown() {
  const pendingStudents = (state.dashboard?.students || []).filter((s) =>
    String(s.taskStatus).includes("复核"),
  ).length;
  const pendingReports = (state.reports || []).filter(
    (r) =>
      ["high", "attention", "unavailable"].includes(r.riskLevel) &&
      r.status !== "published",
  ).length;
  return { pendingStudents, pendingReports, total: pendingStudents + pendingReports };
}
function calculatePending() {
  return calculatePendingBreakdown().total;
}
function renderOverview() {
  const d = state.dashboard || {};
  const school = d.school || {};
  const tasks = (d.tasks || []).filter((t) => t.status !== "draft");
  const students = d.students || [];
  const studentTotal = Number.isFinite(Number(d.studentTotal))
    ? Number(d.studentTotal)
    : students.length;
  const total = tasks.reduce((sum, t) => sum + Number(t.totalCount || 0), 0);
  const completed = tasks.reduce(
    (sum, t) => sum + Number(t.completedCount || 0),
    0,
  );
  const completion = total ? Math.round((completed / total) * 100) : 0;
  const pendingBreakdown = calculatePendingBreakdown();
  const pending = pendingBreakdown.total;
  $("schoolTitle").textContent = school.name || "学校数据总览";
  $("schoolDescription").textContent =
    `${school.campus || "本校区"} · 已接入 ${studentTotal} 名学生、${(d.classes || []).length} 个班级，测评数据持续同步中。`;
  $("schoolRegion").textContent = school.region || "未设置地区";
  $("heroCompletion").textContent = percent(completion);
  $("heroPending").textContent = pending;
  $("metricStudents").textContent = studentTotal;
  $("metricTasks").textContent = tasks.length;
  $("metricClasses").textContent = (d.classes || []).length;
  $("metricReports").textContent = pendingBreakdown.pendingReports;
  $("taskCount").textContent = tasks.length;
  const updateText = `最后同步：${new Date().toLocaleString("zh-CN", { hour12: false })}`;
  $("updatedAt").dataset.latestUpdate = updateText;
  if (!$("overviewSection").dataset.workspace || $("overviewSection").dataset.workspace === "overview") {
    $("updatedAt").textContent = updateText;
  }
  renderGradeChart();
  renderRisk();
  renderTasks();
  renderStudents();
  renderClasses();
  renderNotices();
}
function renderGradeChart() {
  const list = state.gradeStats || [];
  $("gradeChart").innerHTML = list.length
    ? list
        .map(
          (x) =>
            `<div class="bar-row"><span>${escapeHtml(x.name)}</span><div class="bar-track"><i style="width:${Math.min(100, Number(x.completionRate) || 0)}%"></i></div><b>${percent(x.completionRate)}</b></div>`,
        )
        .join("")
    : '<div class="empty-chart">暂无年级统计数据</div>';
}
function renderRisk() {
  const reports = state.reports || [];
  const counts = { low: 0, attention: 0, high: 0, unavailable: 0 };
  reports.forEach(
    (r) => (counts[r.riskLevel] = (counts[r.riskLevel] || 0) + 1),
  );
  const total = reports.length;
  const values = total
    ? [counts.low, counts.attention, counts.high, counts.unavailable].map(
        (n) => (n / total) * 100,
      )
    : [0, 0, 0, 100];
  const end = values.reduce((a, n) => a + n, 0);
  $("riskDistribution").innerHTML =
    `<div class="donut" style="background:conic-gradient(var(--green) 0 ${values[0]}%,#fbbf24 ${values[0]}% ${values[0] + values[1]}%,var(--red) ${values[0] + values[1]}% ${values[0] + values[1] + values[2]}%,#d8e2ef ${values[0] + values[1] + values[2]}% ${end}%)"><div class="donut-label"><strong>${total}</strong><span>份报告</span></div></div><div class="legend"><div class="legend-item"><span><i class="legend-dot" style="background:var(--green)"></i>低风险</span><b>${counts.low}</b></div><div class="legend-item"><span><i class="legend-dot" style="background:#fbbf24"></i>需要关注</span><b>${counts.attention}</b></div><div class="legend-item"><span><i class="legend-dot" style="background:var(--red)"></i>高风险</span><b>${counts.high}</b></div><div class="legend-item"><span><i class="legend-dot" style="background:#d8e2ef"></i>数据不足</span><b>${counts.unavailable}</b></div></div>`;
}
function renderTasks() {
  const tasks = state.dashboard?.tasks || [];
  $("taskTable").innerHTML = tasks.length
    ? tasks
        .slice(0, 8)
        .map((t) => {
          const rate = t.totalCount
            ? Math.round((t.completedCount / t.totalCount) * 100)
            : 0;
          return `<tr><td><strong>${escapeHtml(t.title)}</strong></td><td>${escapeHtml(t.gradeName || "全校")} / ${escapeHtml(t.className || "全校")}</td><td><div class="progress-cell"><div class="mini-progress"><i style="width:${rate}%"></i></div><span>${t.completedCount || 0}/${t.totalCount || 0}</span></div></td><td><span class="status ${statusClass(t.status)}">${escapeHtml(t.status || "待发布")}</span></td><td>${dateText(t.date)}</td></tr>`;
        })
        .join("")
    : '<tr><td colspan="5"><div class="empty-chart">暂无测评任务</div></td></tr>';
}
function renderStudents() {
  const query = (state.search || "").trim().toLowerCase();
  const list = (state.dashboard?.students || []).filter(
    (s) =>
      !query ||
      `${s.name}${s.grade}${s.className}`.toLowerCase().includes(query),
  );
  $("studentTable").innerHTML = list.length
    ? list
        .slice(0, 10)
        .map(
          (s) =>
            `<tr><td><div class="student-cell"><span class="student-mini">${escapeHtml(String(s.name || "").slice(0, 1))}</span><span><strong>${escapeHtml(s.name)}</strong><small>${escapeHtml(s.gender || "")} · ${escapeHtml(s.birthDate ? dateText(s.birthDate) : "未填写生日")}</small></span></div></td><td>${escapeHtml(s.grade)} / ${escapeHtml(s.className)}</td><td><span class="status ${statusClass(s.taskStatus)}">${escapeHtml(s.taskStatus || "未签到")}</span></td><td><strong>${s.totalScore == null ? "-" : Number(s.totalScore).toFixed(1)}</strong><span class="hint"> / 35</span></td><td>${s.isPovertyArea ? '<span class="status attention">重点帮扶</span>' : escapeHtml(s.region || "—")}</td></tr>`,
        )
        .join("")
    : '<tr><td colspan="5"><div class="empty-chart">没有匹配的学生</div></td></tr>';
}
function renderClasses() {
  const list = state.classStats || [];
  const max = Math.max(100, ...list.map((x) => Number(x.completionRate) || 0));
  $("classRanking").innerHTML = list.length
    ? list
        .slice(0, 6)
        .map(
          (x) =>
            `<div class="bar-row"><span>${escapeHtml(x.name)}</span><div class="bar-track"><i style="width:${Math.min(100, ((Number(x.completionRate) || 0) / max) * 100)}%"></i></div><b>${percent(x.completionRate)}</b></div>`,
        )
        .join("")
    : '<div class="empty-chart">暂无班级数据</div>';
}
function renderNotices() {
  const d = state.dashboard || {};
  const tasks = (d.tasks || []).filter(
    (t) =>
      t.status !== "draft" &&
      Number(t.completedCount || 0) < Number(t.totalCount || 0),
  );
  const notices = [];
  if (tasks.length)
    notices.push({
      icon: "clipboard",
      title: `${tasks.length} 项测评任务仍在进行中`,
      desc: `最近任务完成度 ${tasks[0].totalCount ? Math.round((tasks[0].completedCount / tasks[0].totalCount) * 100) : 0}%，建议提醒班主任完成签到与录入。`,
    });
  if (calculatePending())
    notices.push({
      icon: "flag",
      warn: true,
      title: `有 ${calculatePending()} 项数据需要处理`,
      desc: "请前往报告中心或学生档案查看具体记录。",
    });
  if (!notices.length)
    notices.push({
      icon: "spark",
      title: "当前没有紧急事项",
      desc: "学校数据运行平稳，可以继续关注学生成长趋势。",
    });
  $("noticeList").innerHTML = notices
    .map(
      (n) =>
        `<div class="notice"><div class="notice-icon ${n.warn ? "warn" : ""}"><span data-icon="${n.icon}"></span></div><div><strong>${escapeHtml(n.title)}</strong><span>${escapeHtml(n.desc)}</span></div></div>`,
    )
    .join("");
  $("noticeList")
    .querySelectorAll("[data-icon]")
    .forEach((n) => (n.innerHTML = icon(n.dataset.icon)));
}
async function loadAll() {
  const refreshButtons = [$('refreshBtn'), $('refreshTextBtn')].filter(Boolean);
  refreshButtons.forEach((button) => { button.disabled = true; button.classList.add('is-loading'); });
  setWorkspaceStatus('loading', '正在同步学校数据', '正在读取学生、任务、报告和统计记录。');
  void loadServiceHealth();
  try {
    const id = encodeURIComponent(state.schoolId);
    const dashboard = await api(
      `/v1/schools/${id}/dashboard?studentPage=1&studentPageSize=20`,
    );
    state.dashboard = dashboard;
    const results = await Promise.allSettled([
      api(`/v1/schools/${id}/grade-stats`),
      api(`/v1/schools/${id}/class-stats`),
      api(`/v1/reports?schoolId=${id}&paged=1&page=1&pageSize=100`),
    ]);
    state.gradeStats =
      results[0].status === "fulfilled" ? results[0].value : [];
    state.classStats =
      results[1].status === "fulfilled" ? results[1].value : [];
    state.reports =
      results[2].status === "fulfilled"
        ? results[2].value?.items || results[2].value || []
        : [];
    const labels = ["年级统计", "班级统计", "报告中心"];
    state.syncIssues = results.flatMap((result, index) =>
      result.status === "rejected" ? [labels[index]] : [],
    );
    renderOverview();
    if (state.syncIssues.length) {
      setWorkspaceStatus(
        'warning',
        '部分数据暂未同步',
        `${state.syncIssues.join('、')}读取失败，已保留其余可用内容。`,
        true,
      );
    } else {
      setWorkspaceStatus('success', '数据已更新', '学校业务数据已完成同步。');
      window.setTimeout(() => setWorkspaceStatus('hidden'), 1600);
    }
  } catch (error) {
    setWorkspaceStatus('error', '学校数据同步失败', error.message || '网络或服务暂时不可用，请重新同步。', true);
    toast(error.message, true);
  } finally {
    refreshButtons.forEach((button) => { button.disabled = false; button.classList.remove('is-loading'); });
  }
}

function setWorkspaceStatus(kind, title = '', detail = '', retry = false) {
  const container = $('workspaceStatus');
  if (!container) return;
  if (kind === 'hidden') { container.className = 'workspace-status hidden'; return; }
  container.className = `workspace-status ${kind}`;
  $('workspaceStatusTitle').textContent = title;
  $('workspaceStatusDetail').textContent = detail;
  $('workspaceRetryBtn').classList.toggle('hidden', !retry);
}

async function loadServiceHealth() {
  const node = $('serviceHealth');
  if (!node) return;
  node.className = 'service-health checking';
  node.querySelector('span').textContent = '服务检查中';
  try {
    const response = await fetch('/readyz', { credentials: 'same-origin', cache: 'no-store' });
    const payload = await response.json();
    const ready = response.ok && payload?.data?.database === 'up' && payload?.data?.migration?.healthy !== false;
    node.className = `service-health ${ready ? 'healthy' : 'degraded'}`;
    node.querySelector('span').textContent = ready ? '服务运行正常' : '服务需要检查';
  } catch {
    node.className = 'service-health degraded';
    node.querySelector('span').textContent = '服务连接异常';
  }
}
function openTaskModal() {
  const d = state.dashboard || {};
  $("taskModal").classList.remove("hidden");
  $("taskDateInput").value = new Date().toISOString().slice(0, 10);
  $("taskGradeInput").innerHTML =
    '<option value="">全校</option>' +
    (d.grades || [])
      .map(
        (g) =>
          `<option value="${escapeHtml(g.id)}">${escapeHtml(g.name)}</option>`,
      )
      .join("");
  $("taskClassInput").innerHTML =
    '<option value="">全校</option>' +
    (d.classes || [])
      .map(
        (c) =>
          `<option value="${escapeHtml(c.id)}">${escapeHtml(c.name)}</option>`,
      )
      .join("");
  $("taskTitleInput").focus();
}
function closeTaskModal() {
  $("taskModal").classList.add("hidden");
  $("taskFormError").textContent = "";
}
async function submitTask(event) {
  event.preventDefault();
  const f = new FormData(event.target);
  const items = String(f.get("items") || "")
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);
  $("taskFormError").textContent = "";
  try {
    const data = await api("/v1/admin/tasks", {
      method: "POST",
      headers: {
        "Idempotency-Key": `admin-task-${Date.now()}-${Math.random().toString(16).slice(2)}`,
      },
      body: JSON.stringify({
        schoolId: state.schoolId,
        title: f.get("title"),
        testDate: f.get("testDate"),
        location: f.get("location"),
        gradeId: f.get("gradeId") || null,
        classId: f.get("classId") || null,
        items,
      }),
    });
    closeTaskModal();
    toast(`任务已创建，已关联 ${data.studentCount || 0} 名学生`);
    await loadAll();
  } catch (error) {
    $("taskFormError").textContent = error.message;
  }
}
function jumpTo(section) {
  const el = $(
    section === "overview" ? "overviewSection" : `${section}Section`,
  );
  if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
  document
    .querySelectorAll(".nav-item")
    .forEach((n) =>
      n.classList.toggle("active", n.dataset.section === section),
    );
  $("sidebar").classList.remove("open");
}
let mfaChallengeToken = "";
let mfaEnrollment = false;
let pendingMfaLogin = null;
const completeLogin = async (data) => {
  mfaChallengeToken = "";
  mfaEnrollment = false;
  pendingMfaLogin = null;
  $("mfaCodeField").classList.add("hidden");
  $("mfaEnrollmentNotice").classList.add("hidden");
  $("loginSubmit").innerHTML = '<span data-icon="arrow"></span>进入数据工作台';
  state.token = data.accessToken;
  applyProfile(data.user);
  showApp();
  await loadAll();
};
$("loginForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  $("loginError").textContent = "";
  const f = new FormData(e.currentTarget);
  try {
    if (pendingMfaLogin) return completeLogin(pendingMfaLogin);
    const data = mfaChallengeToken
      ? await api(mfaEnrollment ? "/v1/auth/mfa/enroll/confirm" : "/v1/auth/mfa/totp", { method: "POST", body: JSON.stringify({ challengeToken: mfaChallengeToken, code: f.get("mfaCode") }) })
      : await api("/v1/auth/login", { method: "POST", body: JSON.stringify({ account: f.get("account"), password: f.get("password") }) });
    if (data.mfaRequired || data.mfaEnrollmentRequired) {
      mfaChallengeToken = data.challengeToken;
      mfaEnrollment = Boolean(data.mfaEnrollmentRequired);
      if (mfaEnrollment) {
        const setup = await api("/v1/auth/mfa/enroll/setup", { method: "POST", body: JSON.stringify({ challengeToken: mfaChallengeToken }) });
        const notice = $("mfaEnrollmentNotice");
        notice.classList.remove("hidden");
        notice.innerHTML = `<strong>请先注册身份验证器</strong><code>${escapeHtml(setup.secret)}</code><span>在 Microsoft/Google Authenticator、1Password 等应用中手动输入该密钥；${new Date(setup.expiresAt).toLocaleString("zh-CN", { hour12: false })} 前完成确认。</span>`;
      }
      $("mfaCodeField").classList.remove("hidden");
      $("mfaCode").focus();
      $("loginSubmit").textContent = mfaEnrollment ? "确认并启用双重验证" : "验证并进入工作台";
      return;
    }
    if (data.recoveryCodes?.length) {
      pendingMfaLogin = data;
      $("mfaCodeField").classList.add("hidden");
      const notice = $("mfaEnrollmentNotice");
      notice.classList.remove("hidden");
      notice.innerHTML = `<strong>请立即保存恢复码（仅显示一次）</strong><code>${data.recoveryCodes.map(escapeHtml).join("<br>")}</code><span>每个恢复码只能使用一次。请保存到企业密码库后再继续。</span>`;
      $("loginSubmit").textContent = "我已安全保存恢复码";
      return;
    }
    await completeLogin(data);
  } catch (error) {
    $("loginError").textContent = error.message;
  }
});
$("logoutBtn").addEventListener("click", async () => {
  try {
    await api("/v1/auth/logout", { method: "POST" });
  } catch {}
  state.token = "";
  showLogin();
});
$("refreshBtn").addEventListener("click", loadAll);
$("refreshTextBtn").addEventListener("click", loadAll);
$("workspaceRetryBtn").addEventListener("click", loadAll);
$("schoolId").addEventListener("change", () => {
  state.schoolId = $("schoolId").value.trim() || "school-1";
  loadAll();
});
$("globalSearch").addEventListener("input", (e) => {
  $("studentSearch").value = e.target.value;
  state.search = e.target.value;
  renderStudents();
});
$("studentSearch").addEventListener("input", (e) => {
  state.search = e.target.value;
  renderStudents();
});
$("createTaskBtn").addEventListener("click", openTaskModal);
document
  .querySelectorAll('[data-action="create"]')
  .forEach((n) => n.addEventListener("click", openTaskModal));
$("closeTaskBtn").addEventListener("click", closeTaskModal);
$("cancelTaskBtn").addEventListener("click", closeTaskModal);
$("taskModal").addEventListener("click", (e) => {
  if (e.target === $("taskModal")) closeTaskModal();
});
$("taskForm").addEventListener("submit", submitTask);
document
  .querySelectorAll("[data-section]")
  .forEach((n) => n.addEventListener("click", () => jumpTo(n.dataset.section)));
$("menuBtn").addEventListener("click", () =>
  $("sidebar").classList.toggle("open"),
);
showLogin();

(function enhanceDashboard() {
  const oldReportAnchor = document.getElementById("reportsSection");
  if (oldReportAnchor) oldReportAnchor.removeAttribute("id");
  const tasksAnchor = document.getElementById("tasksSection");
  const settingsAnchor = document.getElementById("settingsSection");
  const trendPanel = document.createElement("section");
  trendPanel.className = "panel trend-panel";
  trendPanel.id = "trendSection";
  trendPanel.innerHTML =
    '<div class="panel-head"><div><h3>任务完成趋势</h3><p>按任务日期查看当前学校的完成进度</p></div><span class="date-label">最近任务</span></div><div id="trendChart" class="trend-chart"><div class="empty-chart">暂无趋势数据</div></div>';
  if (tasksAnchor) tasksAnchor.before(trendPanel);
  const reportPanel = document.createElement("section");
  reportPanel.className = "panel report-panel";
  reportPanel.id = "reportsSection";
  reportPanel.innerHTML =
    '<div class="panel-head"><div><h3>报告中心</h3><p>集中处理诊断报告的风险等级与发布状态</p></div><select id="reportFilter" class="report-filter" aria-label="报告风险筛选"><option value="all">全部风险</option><option value="low">低风险</option><option value="attention">需要关注</option><option value="high">高风险</option><option value="unavailable">数据不足</option></select></div><div class="table-panel"><div class="table-scroll"><table class="data-table"><thead><tr><th>学生</th><th>班级</th><th>综合得分</th><th>风险等级</th><th>发布状态</th><th>生成时间</th><th>操作</th></tr></thead><tbody id="reportTable"></tbody></table></div></div>';
  if (settingsAnchor) settingsAnchor.before(reportPanel);
  const reportRiskLabel = {
    low: "低风险",
    attention: "需要关注",
    high: "高风险",
    unavailable: "数据不足",
  };
  function renderTrendPanel() {
    const chart = document.getElementById("trendChart");
    if (!chart) return;
    const tasks = state.dashboard?.tasks || [];
    if (!tasks.length) {
      chart.innerHTML = '<div class="empty-chart">暂无趋势数据</div>';
      return;
    }
    chart.innerHTML = tasks
      .slice(0, 7)
      .reverse()
      .map((t) => {
        const rate = t.totalCount
          ? Math.round(
              (Number(t.completedCount || 0) / Number(t.totalCount)) * 100,
            )
          : 0;
        return `<div class="trend-column" title="${escapeHtml(t.title)}：${rate}%"><strong>${rate}%</strong><i style="height:${Math.max(4, rate)}%"></i><span>${dateText(t.date)}</span></div>`;
      })
      .join("");
  }
  function renderReportPanel() {
    const table = document.getElementById("reportTable");
    if (!table) return;
    const filter = document.getElementById("reportFilter")?.value || "all";
    const list = (state.reports || []).filter(
      (r) => filter === "all" || r.riskLevel === filter,
    );
    if (!list.length) {
      table.innerHTML =
        '<tr><td colspan="7"><div class="empty-chart">当前筛选暂无报告</div></td></tr>';
      return;
    }
    table.innerHTML = list
      .map((r) => {
        const published = r.status === "published";
        const risk = r.riskLevel || "unavailable";
        return `<tr><td><div class="student-cell"><span class="student-mini">${escapeHtml(String(r.studentName || "").slice(0, 1))}</span><span><strong>${escapeHtml(r.studentName || "—")}</strong><small>${escapeHtml(r.gradeName || "")} · ${escapeHtml(r.className || "")}</small></span></div></td><td>${escapeHtml(r.className || "—")}</td><td><strong>${r.totalScore == null ? "—" : Number(r.totalScore).toFixed(1)}</strong><span class="hint"> / 35</span></td><td><span class="status ${statusClass(risk)}">${reportRiskLabel[risk] || escapeHtml(risk)}</span></td><td><span class="status ${published ? "done" : "pending"}">${published ? "已发布" : "待发布"}</span></td><td>${dateText(r.generatedAt)}</td><td><button class="report-action ${published ? "withdraw" : ""}" data-report-action="${published ? "withdraw" : "publish"}" data-report-id="${escapeHtml(r.id)}">${published ? "撤回" : "发布"}</button></td></tr>`;
      })
      .join("");
  }
  async function updateReport(reportId, action) {
    if (
      !window.confirm(
        action === "publish"
          ? "确认发布这份诊断报告？"
          : "确认撤回这份诊断报告？",
      )
    )
      return;
    try {
      await api(`/v1/reports/${encodeURIComponent(reportId)}/${action}`, {
        method: "POST",
      });
      toast(action === "publish" ? "报告已发布" : "报告已撤回");
      await loadAll();
    } catch (error) {
      toast(error.message, true);
    }
  }
  document
    .getElementById("reportFilter")
    ?.addEventListener("change", renderReportPanel);
  document.addEventListener("click", (event) => {
    const button = event.target.closest("[data-report-action]");
    if (button)
      updateReport(button.dataset.reportId, button.dataset.reportAction);
  });
  let previousDashboard = null;
  setInterval(() => {
    if (state.dashboard !== previousDashboard) {
      previousDashboard = state.dashboard;
      renderTrendPanel();
      renderReportPanel();
    }
  }, 250);
})();

(function enhanceAccounts() {
  const settingsNav = document.querySelector(
    '.nav-item[data-section="settings"]',
  );
  if (settingsNav) settingsNav.lastChild.textContent = "运营提醒";
  const accountNav = document.createElement("button");
  accountNav.className = "nav-item";
  accountNav.dataset.section = "accounts";
  accountNav.innerHTML = '<span data-icon="users"></span>账户分桶';
  accountNav.querySelector("[data-icon]").innerHTML = icon("users");
  if (settingsNav) settingsNav.before(accountNav);
  const settingsAnchor = document.getElementById("settingsSection");
  const panel = document.createElement("section");
  panel.className = "panel account-panel";
  panel.id = "accountsSection";
  panel.innerHTML =
    '<div class="panel-head"><div><h3>账户分桶</h3><p>按角色和账户状态管理学校运营账号，手机号默认脱敏显示</p></div><button id="addAccountBtn" class="primary-btn"><span data-icon="plus"></span>新增账户</button></div><div id="accountBuckets" class="account-buckets"></div><div class="account-toolbar"><input id="accountSearch" class="table-search" placeholder="搜索姓名或手机号"><select id="accountRoleFilter" class="account-select" aria-label="账户角色筛选"><option value="all">全部角色</option><option value="admin">平台管理员</option><option value="principal">校长</option><option value="teacher">教师</option><option value="parent">家长</option></select><select id="accountStatusFilter" class="account-select" aria-label="账户状态筛选"><option value="all">全部状态</option><option value="active">正常</option><option value="disabled">已停用</option></select></div><div class="table-panel"><div class="table-scroll"><table class="data-table"><thead><tr><th>账户</th><th>角色</th><th>所属学校</th><th>状态</th><th>创建时间</th><th>操作</th></tr></thead><tbody id="accountTable"></tbody></table></div></div>';
  if (settingsAnchor) settingsAnchor.before(panel);
  const accountModal = document.createElement("div");
  accountModal.id = "accountModal";
  accountModal.className = "modal-backdrop hidden";
  accountModal.innerHTML =
    '<div class="modal"><div class="modal-head"><div><h2>新增账户</h2><p>为学校团队创建一个可登录的工作账户。</p></div><button id="closeAccountBtn" class="modal-close" aria-label="关闭"><span data-icon="close"></span></button></div><div class="account-modal-note">账户权限将由角色决定。家长账户适用于家庭绑定，教师和校长账户只应绑定到实际学校。</div><form id="accountForm"><div class="form-grid"><div class="field"><label for="accountNameInput">姓名</label><input id="accountNameInput" name="name" required placeholder="例如：李老师"></div><div class="field"><label for="accountPhoneInput">手机号</label><input id="accountPhoneInput" name="phone" required inputmode="numeric" placeholder="11 位手机号"></div><div class="field"><label for="accountPasswordInput">初始密码</label><input id="accountPasswordInput" name="password" type="password" required minlength="8" placeholder="至少 8 位字符"></div><div class="field"><label for="accountRoleInput">角色</label><select id="accountRoleInput" name="role"><option value="teacher">教师</option><option value="principal">校长</option><option value="parent">家长</option><option value="admin">平台管理员</option></select></div><div class="field"><label for="accountSchoolInput">学校 ID</label><input id="accountSchoolInput" name="schoolId" value="school-1"></div><div class="field"><label for="accountClassInput">班级 ID（可选）</label><input id="accountClassInput" name="classId" placeholder="例如：class-3"></div><div class="field full"><label for="accountScopesInput">多学校/班级范围（可选 JSON）</label><textarea id="accountScopesInput" rows="3" placeholder=&quot;[{&quot;roleCode&quot;:&quot;teacher&quot;,&quot;schoolId&quot;:&quot;school-1&quot;,&quot;classId&quot;:&quot;class-3&quot;}]&quot;></textarea><span class="hint">填写后按 roles 发送，可配置同一账户的多个学校、角色和班级范围。</span></div></div><div id="accountFormError" class="error"></div><div class="modal-footer"><button type="button" id="cancelAccountBtn" class="secondary-btn">取消</button><button type="submit" class="primary-btn"><span data-icon="send"></span>创建账户</button></div></form></div>';
  document.body.append(accountModal);
  accountModal
    .querySelectorAll("[data-icon]")
    .forEach((n) => (n.innerHTML = icon(n.dataset.icon)));
  state.accounts = { buckets: [], items: [], scopeTotal: 0 };
  state.accountRole = "all";
  state.accountStatus = "all";
  state.accountSearch = "";
  let accountReady = false;
  let accountRequestSeq = 0;
  let accountSearchTimer = 0;
  const roles = {
    admin: "平台管理员",
    principal: "校长",
    teacher: "教师",
    parent: "家长",
  };
  function accountQuery() {
    const params = new URLSearchParams({
      schoolId: state.schoolId,
      paged: "1",
      page: "1",
      pageSize: "100",
    });
    if (state.accountRole !== "all") params.set("role", state.accountRole);
    if (state.accountStatus !== "all")
      params.set("status", state.accountStatus);
    if (state.accountSearch.trim())
      params.set("search", state.accountSearch.trim());
    return params;
  }
  function renderAccounts() {
    const buckets = document.getElementById("accountBuckets");
    const table = document.getElementById("accountTable");
    if (!buckets || !table) return;
    const bucketMap = Object.fromEntries(
      (state.accounts.buckets || []).map((b) => [b.key, b]),
    );
    buckets.innerHTML = ["admin", "principal", "teacher", "parent"]
      .map((key) => {
        const bucket = bucketMap[key] || {
          count: 0,
          percent: 0,
          label: roles[key],
        };
        return `<button class="account-bucket ${state.accountRole === key ? "active" : ""}" data-account-role="${key}"><span class="bucket-icon"><span data-icon="${key === "parent" ? "users" : key === "teacher" ? "clipboard" : key === "principal" ? "school" : "shield"}"></span></span><span><strong>${bucket.count}</strong><span>${roles[key]} · ${bucket.percent}%</span></span></button>`;
      })
      .join("");
    buckets
      .querySelectorAll("[data-icon]")
      .forEach((n) => (n.innerHTML = icon(n.dataset.icon)));
    buckets.querySelectorAll("[data-account-role]").forEach((n) =>
      n.addEventListener("click", () => {
        state.accountRole =
          state.accountRole === n.dataset.accountRole
            ? "all"
            : n.dataset.accountRole;
        document.getElementById("accountRoleFilter").value = state.accountRole;
        loadAccounts();
      }),
    );
    table.innerHTML = state.accounts.items?.length
      ? state.accounts.items
          .map((item) => {
            const role = item.roles?.[0]?.code || "parent";
            const active = item.status === "active";
            return `<tr><td><div class="student-cell"><span class="student-mini">${escapeHtml(String(item.name || "").slice(0, 1))}</span><span><strong>${escapeHtml(item.name)}</strong><small>${escapeHtml(item.phoneMasked || "已隐藏")}</small></span></div></td><td><span class="account-role ${role}">${escapeHtml(item.roles?.map((r) => r.name).join("、") || roles[role])}</span></td><td>${escapeHtml(item.schoolNames || "未分配")}</td><td><span class="status ${active ? "done" : "gray"}">${active ? "正常" : "已停用"}</span></td><td>${dateText(item.createdAt)}</td><td><button class="report-action ${active ? "withdraw" : ""}" data-account-action="${active ? "disable" : "active"}" data-account-id="${escapeHtml(item.id)}">${active ? "停用" : "启用"}</button></td></tr>`;
          })
          .join("")
      : '<tr><td colspan="6"><div class="empty-chart">当前筛选暂无账户</div></td></tr>';
  }
  async function loadAccounts() {
    const requestSeq = ++accountRequestSeq;
    try {
      const data = await api(`/v1/admin/accounts?${accountQuery()}`);
      if (requestSeq !== accountRequestSeq) return;
      state.accounts = data;
      accountReady = true;
      panel.classList.remove("hidden");
      accountNav.classList.remove("hidden");
      renderAccounts();
    } catch (error) {
      if (requestSeq !== accountRequestSeq) return;
      if (error.message.includes("平台管理员")) {
        accountReady = false;
        panel.classList.add("hidden");
        accountNav.classList.add("hidden");
      } else if (accountReady) toast(error.message, true);
    }
  }
  async function updateAccount(id, status) {
    if (
      !window.confirm(
        status === "disabled"
          ? "确认停用该账户？停用后其登录会话会立即失效。"
          : "确认启用该账户？",
      )
    )
      return;
    try {
      await api(`/v1/admin/accounts/${encodeURIComponent(id)}/status`, {
        method: "PATCH",
        body: JSON.stringify({ status }),
      });
      toast(status === "disabled" ? "账户已停用" : "账户已启用");
      await loadAccounts();
    } catch (error) {
      toast(error.message, true);
    }
  }
  async function submitAccount(event) {
    event.preventDefault();
    const f = new FormData(event.currentTarget);
    const errorNode = document.getElementById("accountFormError");
    errorNode.textContent = "";
    try {
      const rawScopes = String(
        document.getElementById("accountScopesInput")?.value || "",
      ).trim();
      let roles = null;
      if (rawScopes) {
        roles = JSON.parse(rawScopes);
        if (!Array.isArray(roles) || !roles.length)
          throw new Error("权限范围必须是非空 JSON 数组");
      }
      const payload = {
        name: f.get("name"),
        phone: f.get("phone"),
        password: f.get("password"),
        role: f.get("role"),
        schoolId: f.get("schoolId") || null,
        classId: f.get("classId") || null,
      };
      if (roles) payload.roles = roles;
      await api("/v1/admin/accounts", {
        method: "POST",
        headers: {
          "Idempotency-Key": `admin-account-${Date.now()}-${Math.random().toString(16).slice(2)}`,
        },
        body: JSON.stringify(payload),
      });
      closeAccountModal();
      toast("账户已创建");
      await loadAccounts();
    } catch (error) {
      errorNode.textContent = error.message.includes("JSON")
        ? "权限范围 JSON 格式不正确"
        : error.message;
    }
  }
  function openAccountModal() {
    accountModal.classList.remove("hidden");
    document.getElementById("accountNameInput").focus();
  }
  function closeAccountModal() {
    accountModal.classList.add("hidden");
    document.getElementById("accountFormError").textContent = "";
  }
  accountNav.addEventListener("click", () => jumpTo("accounts"));
  document
    .getElementById("accountSearch")
    .addEventListener("input", (event) => {
      state.accountSearch = event.target.value;
      clearTimeout(accountSearchTimer);
      accountSearchTimer = setTimeout(loadAccounts, 260);
    });
  document
    .getElementById("accountRoleFilter")
    .addEventListener("change", (event) => {
      state.accountRole = event.target.value;
      loadAccounts();
    });
  document
    .getElementById("accountStatusFilter")
    .addEventListener("change", (event) => {
      state.accountStatus = event.target.value;
      loadAccounts();
    });
  document
    .getElementById("addAccountBtn")
    .addEventListener("click", openAccountModal);
  document
    .getElementById("closeAccountBtn")
    .addEventListener("click", closeAccountModal);
  document
    .getElementById("cancelAccountBtn")
    .addEventListener("click", closeAccountModal);
  accountModal.addEventListener("click", (event) => {
    if (event.target === accountModal) closeAccountModal();
  });
  document
    .getElementById("accountForm")
    .addEventListener("submit", submitAccount);
  document.addEventListener("click", (event) => {
    const button = event.target.closest("[data-account-action]");
    if (button)
      updateAccount(button.dataset.accountId, button.dataset.accountAction);
  });
  let previousAccountDashboard = null;
  setInterval(() => {
    if (state.dashboard !== previousAccountDashboard) {
      previousAccountDashboard = state.dashboard;
      loadAccounts();
    }
  }, 300);
})();
