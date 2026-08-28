import { MOVEMENT_ITEM_CODES } from './scoring.js';

const itemSet = new Set(MOVEMENT_ITEM_CODES);

const scopeError = (message, code = 'FIELD_TASK_ITEMS_INVALID') => Object.assign(new Error(message), { status: 400, code });

export function normalizeFieldTaskItems(value, options = {}) {
  const { allowEmpty = false } = options;
  if (!Array.isArray(value)) throw scopeError('测评项目必须是列表');
  const normalized = value.map((item) => String(item || '').trim()).filter(Boolean);
  if (!allowEmpty && normalized.length === 0) throw scopeError('测评任务至少需要选择一个项目');
  if (normalized.length > MOVEMENT_ITEM_CODES.length) throw scopeError('测评项目最多为 7 项');
  const unique = [...new Set(normalized)];
  if (unique.length !== normalized.length) throw scopeError('测评项目不能重复');
  const unsupported = unique.filter((item) => !itemSet.has(item));
  if (unsupported.length) throw scopeError(`存在不支持的测评项目：${unsupported.join('、')}`);
  return MOVEMENT_ITEM_CODES.filter((item) => unique.includes(item));
}

export function normalizeStationItemCode(value) {
  const itemCode = String(value || '').trim();
  if (!itemCode || itemCode === 'all') return null;
  if (!itemSet.has(itemCode)) throw scopeError('测试点能力必须选择“整套任务”或一个标准测评项目', 'FIELD_STATION_ITEM_INVALID');
  return itemCode;
}

export function stationTaskCompatibility(stationItemCode, taskItems) {
  let normalizedItems;
  try {
    normalizedItems = normalizeFieldTaskItems(taskItems);
  } catch (error) {
    return { compatible: false, mode: 'invalid_task', label: '任务项目配置错误', reason: error.message };
  }
  const itemCode = String(stationItemCode || '').trim();
  if (!itemCode || itemCode === 'all') {
    return { compatible: true, mode: 'full_task', label: '整套任务通道', reason: `可完成任务全部 ${normalizedItems.length} 项` };
  }
  if (!itemSet.has(itemCode)) {
    return { compatible: false, mode: 'invalid_station', label: '旧版能力配置', reason: '测试点能力不是标准项目，请在后台重新选择' };
  }
  const compatible = normalizedItems.length === 1 && normalizedItems[0] === itemCode;
  return {
    compatible,
    mode: 'single_item',
    label: `单项通道 · ${itemCode}`,
    reason: compatible ? `与任务项目“${itemCode}”一致` : `该测试点只支持“${itemCode}”，当前任务包含 ${normalizedItems.join('、')}`
  };
}

export function scoreScopeDifference(taskItems, scoreItems) {
  const expected = normalizeFieldTaskItems(taskItems);
  const submitted = [...new Set(scoreItems.map((item) => String(item || '').trim()).filter(Boolean))];
  return {
    expected,
    missing: expected.filter((item) => !submitted.includes(item)),
    unexpected: submitted.filter((item) => !expected.includes(item))
  };
}
