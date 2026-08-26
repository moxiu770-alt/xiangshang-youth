(() => {
  const nav = document.querySelector('.nav-item[data-section="content"]');
  const anchor = document.getElementById('settingsSection');
  if (!nav || !anchor) return;

  const labels = { course: '课程', activity: '活动', expert: '专家', notification_template: '通知模板' };
  const content = {
    channel: 'mobile', type: 'course', catalog: [], releases: [], selectedRelease: null,
    selectedItems: [], search: '', loading: false, error: ''
  };
  const section = document.createElement('section');
  section.id = 'contentSection';
  section.className = 'panel content-ops-section';
  section.innerHTML = `
    <div class="panel-head"><div><h3>内容运营</h3><p>将课程、活动、专家与通知模板编排为可审计的发布版本</p></div><button id="contentRefresh" class="secondary-btn"><span data-icon="refresh"></span>刷新</button></div>
    <div class="content-release-summary" id="contentSummary"></div>
    <div id="contentError" class="content-ops-error hidden"></div>
    <form id="contentReleaseForm" class="content-ops-toolbar">
      <div class="field"><label for="contentChannel">发布渠道</label><select id="contentChannel"><option value="mobile">全部移动端</option><option value="family">家庭端</option><option value="teacher">教师端</option></select></div>
      <div class="field"><label for="contentNotes">版本说明</label><input id="contentNotes" maxlength="2000" required placeholder="例如：秋季课程与活动第一批发布"></div>
      <div class="field"><label for="contentEffectiveAt">生效时间（可选）</label><input id="contentEffectiveAt" type="datetime-local"></div>
      <button class="primary-btn" type="submit"><span data-icon="plus"></span>创建发布草稿</button>
    </form>
    <div class="content-ops-grid">
      <div class="content-ops-panel">
        <div class="content-ops-panel-head"><div><h4>内容目录</h4><small>选择项目加入当前草稿</small></div><div class="content-type-tabs" id="contentTypeTabs"></div></div>
        <input id="contentCatalogSearch" class="content-catalog-search" placeholder="搜索标题或编号">
        <div id="contentCatalogList" class="content-catalog-list"></div>
      </div>
      <div class="content-ops-panel">
        <div class="content-ops-panel-head"><div><h4>版本与编排</h4><small>发布后版本不可修改，只能撤回</small></div></div>
        <div id="contentReleaseList" class="content-release-list"></div>
        <div id="contentEditor" class="content-editor"></div>
      </div>
    </div>`;
  anchor.before(section);
  section.querySelectorAll('[data-icon]').forEach((node) => { node.innerHTML = icon(node.dataset.icon); });

  const node = (id) => document.getElementById(id);
  const cleanDate = (value) => value ? new Date(value).toLocaleString('zh-CN', { hour12: false }) : '立即生效';
  const itemId = (item) => String(item.id || item.contentId || '');
  const itemTitle = (item) => String(item.title || item.name || item.content || item.id || '未命名内容');
  const itemStatus = (item) => String(item.status || '未设置状态');
  const selectedKey = (item) => `${item.contentType}:${item.contentId}`;
  const catalogueKey = (item) => `${content.type}:${itemId(item)}`;

  function setError(message = '') {
    content.error = message;
    node('contentError').textContent = message;
    node('contentError').classList.toggle('hidden', !message);
  }
  function setLoading(value) {
    content.loading = value;
    section.classList.toggle('content-ops-loading', value);
  }
  function renderSummary() {
    const published = content.releases.filter((item) => item.status === 'published').length;
    const draft = content.releases.filter((item) => item.status === 'draft').length;
    node('contentSummary').innerHTML = `<span class="content-summary-chip">版本 ${content.releases.length}</span><span class="content-summary-chip">已发布 ${published}</span><span class="content-summary-chip">草稿 ${draft}</span><span class="content-summary-chip">当前学校 ${escapeHtml(state.schoolId || '全平台')}</span>`;
  }
  function renderTabs() {
    node('contentTypeTabs').innerHTML = Object.entries(labels).map(([key, label]) => `<button type="button" class="content-type-tab ${content.type === key ? 'active' : ''}" data-content-type="${key}">${label}</button>`).join('');
  }
  function renderCatalog() {
    const q = content.search.trim().toLowerCase();
    const editable = content.selectedRelease?.status === 'draft';
    const selected = new Set(content.selectedItems.map(selectedKey));
    const items = content.catalog.filter((item) => !q || `${itemTitle(item)} ${itemId(item)}`.toLowerCase().includes(q));
    node('contentCatalogList').innerHTML = items.length ? items.map((item) => {
      const key = catalogueKey(item);
      return `<label class="content-catalog-item"><input type="checkbox" data-catalog-id="${escapeHtml(itemId(item))}" ${selected.has(key) ? 'checked' : ''} ${editable ? '' : 'disabled'}><span><strong>${escapeHtml(itemTitle(item))}</strong><small>${escapeHtml(itemId(item))} · ${escapeHtml(itemStatus(item))}</small></span></label>`;
    }).join('') : '<div class="content-empty">当前分类没有可用内容。请先创建并审核业务内容，再加入发布版本。</div>';
  }
  function renderReleases() {
    node('contentReleaseList').innerHTML = content.releases.length ? content.releases.map((release) => `<article class="content-release-card ${content.selectedRelease?.releaseId === release.releaseId ? 'selected' : ''}"><div><strong>${escapeHtml(release.channel)} · v${Number(release.version || 0)}</strong><small>${escapeHtml(release.notes || '无版本说明')} · ${cleanDate(release.effectiveAt)} · ${Number(release.itemCount || 0)} 项</small></div><span class="content-status ${escapeHtml(release.status)}">${release.status === 'published' ? '已发布' : release.status === 'withdrawn' ? '已撤回' : '草稿'}</span><span class="content-release-actions"><button class="content-mini-btn" data-release-open="${escapeHtml(release.releaseId)}">查看</button>${release.status === 'published' ? `<button class="content-mini-btn danger" data-release-withdraw="${escapeHtml(release.releaseId)}">撤回</button>` : ''}</span></article>`).join('') : '<div class="content-empty">还没有内容版本。创建草稿后选择目录内容并保存编排。</div>';
  }
  function renderEditor() {
    const release = content.selectedRelease;
    if (!release) { node('contentEditor').innerHTML = '<div class="content-empty">选择一个版本查看详情，或创建新的发布草稿。</div>'; renderCatalog(); return; }
    const editable = release.status === 'draft';
    const items = content.selectedItems;
    node('contentEditor').innerHTML = `<div class="content-draft-note"><strong>${escapeHtml(release.channel)} · v${Number(release.version || 0)}</strong><br>${escapeHtml(release.notes || '无版本说明')}<br>生效：${cleanDate(release.effectiveAt)}</div><div class="content-selected-list">${items.length ? items.map((item, index) => `<div class="content-selected-item"><span><strong>${index + 1}. ${escapeHtml(labels[item.contentType] || item.contentType)} · ${escapeHtml(item.contentId)}</strong><small>内容版本 ${Number(item.contentVersion || 1)}</small></span>${editable ? `<span class="content-order-actions"><button class="content-mini-btn" data-item-move="up" data-item-index="${index}" ${index === 0 ? 'disabled' : ''}>上移</button><button class="content-mini-btn" data-item-move="down" data-item-index="${index}" ${index === items.length - 1 ? 'disabled' : ''}>下移</button><button class="content-mini-btn danger" data-item-remove="${index}">移除</button></span>` : ''}</div>`).join('') : '<div class="content-empty">草稿尚未加入内容。请从左侧目录选择。</div>'}</div>${editable ? `<div class="content-editor-footer"><button class="secondary-btn" id="contentSaveItems" ${items.length ? '' : 'disabled'}>保存编排</button><button class="primary-btn" id="contentPublish" ${items.length ? '' : 'disabled'}>发布版本</button></div>` : ''}`;
    renderCatalog();
  }
  function render() { renderSummary(); renderTabs(); renderCatalog(); renderReleases(); renderEditor(); }

  async function loadCatalog() {
    content.catalog = await api(`/v1/admin/content/catalog?type=${encodeURIComponent(content.type)}&schoolId=${encodeURIComponent(state.schoolId)}`);
  }
  async function loadReleases() {
    content.releases = await api(`/v1/admin/content/releases?schoolId=${encodeURIComponent(state.schoolId)}`);
  }
  async function loadAllContent() {
    setLoading(true); setError();
    try { await Promise.all([loadCatalog(), loadReleases()]); render(); }
    catch (error) { setError(error.message || '内容运营数据加载失败'); }
    finally { setLoading(false); }
  }
  async function openRelease(id) {
    setLoading(true); setError();
    try {
      const detail = await api(`/v1/admin/content/releases/${encodeURIComponent(id)}`);
      content.selectedRelease = detail;
      content.selectedItems = Array.isArray(detail.items) ? detail.items.map((item, index) => ({ ...item, sortOrder: index })) : [];
      render();
    } catch (error) { setError(error.message); }
    finally { setLoading(false); }
  }
  async function saveItems(showToast = true) {
    const release = content.selectedRelease;
    if (!release || release.status !== 'draft') throw new Error('请选择可编辑的草稿版本');
    if (!content.selectedItems.length) throw new Error('发布版本至少需要一个内容项目');
    await api(`/v1/admin/content/releases/${encodeURIComponent(release.releaseId)}/items`, { method: 'PUT', body: JSON.stringify({ items: content.selectedItems.map((item, index) => ({ contentType: item.contentType, contentId: item.contentId, contentVersion: Number(item.contentVersion || 1), sortOrder: index, metadata: item.metadata || {} })) }) });
    if (showToast) toast('内容编排已保存');
    await openRelease(release.releaseId);
    await loadReleases(); renderReleases(); renderSummary();
  }
  async function publishRelease() {
    if (!window.confirm('发布后该版本将锁定且移动端可见，确认继续？')) return;
    setLoading(true); setError();
    try {
      await saveItems(false);
      await api(`/v1/admin/content/releases/${encodeURIComponent(content.selectedRelease.releaseId)}/publish`, { method: 'POST', headers: { 'Idempotency-Key': `content-publish-${content.selectedRelease.releaseId}` }, body: '{}' });
      toast('内容版本已发布'); content.selectedRelease = null; content.selectedItems = []; await loadAllContent();
    } catch (error) { setError(error.message); }
    finally { setLoading(false); }
  }

  node('contentReleaseForm').addEventListener('submit', async (event) => {
    event.preventDefault(); setLoading(true); setError();
    try {
      const effective = node('contentEffectiveAt').value;
      const release = await api('/v1/admin/content/releases', { method: 'POST', headers: { 'Idempotency-Key': `content-release-${Date.now()}` }, body: JSON.stringify({ schoolId: state.schoolId, channel: node('contentChannel').value, notes: node('contentNotes').value.trim(), effectiveAt: effective ? new Date(effective).toISOString() : null }) });
      node('contentNotes').value = ''; node('contentEffectiveAt').value = ''; toast('发布草稿已创建'); await loadReleases(); await openRelease(release.releaseId);
    } catch (error) { setError(error.message); }
    finally { setLoading(false); }
  });
  node('contentRefresh').addEventListener('click', loadAllContent);
  node('contentCatalogSearch').addEventListener('input', (event) => { content.search = event.target.value; renderCatalog(); });
  nav.addEventListener('click', () => { document.querySelector('.crumb strong').textContent = '内容运营'; loadAllContent(); });
  document.addEventListener('click', async (event) => {
    const typeButton = event.target.closest('[data-content-type]');
    if (typeButton) { content.type = typeButton.dataset.contentType; setLoading(true); try { await loadCatalog(); render(); } catch (error) { setError(error.message); } finally { setLoading(false); } return; }
    const open = event.target.closest('[data-release-open]'); if (open) { await openRelease(open.dataset.releaseOpen); return; }
    const withdraw = event.target.closest('[data-release-withdraw]');
    if (withdraw) { if (!window.confirm('撤回后移动端将不再获得该版本，确认继续？')) return; try { await api(`/v1/admin/content/releases/${encodeURIComponent(withdraw.dataset.releaseWithdraw)}/withdraw`, { method: 'POST', headers: { 'Idempotency-Key': `content-withdraw-${withdraw.dataset.releaseWithdraw}` }, body: '{}' }); toast('内容版本已撤回'); await loadAllContent(); } catch (error) { setError(error.message); } return; }
    const remove = event.target.closest('[data-item-remove]'); if (remove) { content.selectedItems.splice(Number(remove.dataset.itemRemove), 1); render(); return; }
    const move = event.target.closest('[data-item-move]'); if (move) { const index = Number(move.dataset.itemIndex); const next = move.dataset.itemMove === 'up' ? index - 1 : index + 1; if (next >= 0 && next < content.selectedItems.length) { const [item] = content.selectedItems.splice(index, 1); content.selectedItems.splice(next, 0, item); render(); } return; }
    if (event.target.closest('#contentSaveItems')) { setLoading(true); setError(); try { await saveItems(); } catch (error) { setError(error.message); } finally { setLoading(false); } return; }
    if (event.target.closest('#contentPublish')) { await publishRelease(); }
  });
  node('contentCatalogList').addEventListener('change', (event) => {
    const checkbox = event.target.closest('[data-catalog-id]'); if (!checkbox || content.selectedRelease?.status !== 'draft') return;
    const id = checkbox.dataset.catalogId; const key = `${content.type}:${id}`;
    if (checkbox.checked && !content.selectedItems.some((item) => selectedKey(item) === key)) content.selectedItems.push({ contentType: content.type, contentId: id, contentVersion: 1, sortOrder: content.selectedItems.length, metadata: {} });
    if (!checkbox.checked) content.selectedItems = content.selectedItems.filter((item) => selectedKey(item) !== key);
    renderEditor();
  });

  const previousSchoolListener = node('schoolId');
  previousSchoolListener?.addEventListener('change', () => { content.selectedRelease = null; content.selectedItems = []; loadAllContent(); });
  render();
})();
