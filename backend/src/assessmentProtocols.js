import { MOVEMENT_ITEM_CODES } from './scoring.js';

export const BASELINE_ASSESSMENT_PROTOCOL_ID = 'protocol-global-seven-actions-v1';
export const BASELINE_ASSESSMENT_PROTOCOL_CODE = 'seven-action-complete-lane';
export const BASELINE_ASSESSMENT_PROTOCOL_VERSION = '1.0.0';

const recognitionFocus = Object.freeze({
  '连续双脚障碍跳': ['起跳', '落地', '越障', '缓冲', '触碰', '停顿'],
  '侧向滑步': ['身体朝向', '脚步交叉', '膝角', '重心高度', '移动距离'],
  '倒退平衡': ['有效倒退步', '横杆边界', '触地', '扶物', '停顿'],
  '接球-上手掷准': ['接球', '屈肘缓冲', '衔接', '上手投掷', '越线', '命中'],
  '手运球绕杆': ['手触球', '球触地', '反弹', '绕杆', '抱球', '漏杆', '失控'],
  '脚运球变向': ['脚触球', '球速和方向变化', '球距', '绕杆', '手触球', '停顿'],
  '定点踢准': ['支撑脚', '踢球腿摆动', '触球', '身体控制', '目标命中']
});

export const BASELINE_ASSESSMENT_PROTOCOL_ITEMS = Object.freeze(MOVEMENT_ITEM_CODES.map((name, index) => Object.freeze({
  code: name,
  name,
  sequenceNo: index + 1,
  required: true,
  sensorProfile: {
    preferredSensors: ['hikvision-high-speed', 'orbbec-femto-mega'],
    recognitionFocus: recognitionFocus[name]
  },
  ruleConfig: {}
})));

const normalizeSnapshotItem = (item, index) => ({
  code: String(item?.code || item?.itemCode || item?.name || '').trim(),
  name: String(item?.name || item?.itemName || item?.code || '').trim(),
  sequenceNo: Number(item?.sequenceNo || index + 1),
  required: item?.required !== false,
  sensorProfile: item?.sensorProfile && typeof item.sensorProfile === 'object' ? item.sensorProfile : {},
  ruleConfig: item?.ruleConfig && typeof item.ruleConfig === 'object' ? item.ruleConfig : {}
});

export function baselineAssessmentProtocolSnapshot(taskItems = MOVEMENT_ITEM_CODES) {
  const selected = new Set(taskItems.map((item) => String(item || '').trim()).filter(Boolean));
  const items = BASELINE_ASSESSMENT_PROTOCOL_ITEMS.filter((item) => selected.has(item.code));
  return {
    id: BASELINE_ASSESSMENT_PROTOCOL_ID,
    code: BASELINE_ASSESSMENT_PROTOCOL_CODE,
    name: '向上少年七项完整通道',
    version: BASELINE_ASSESSMENT_PROTOCOL_VERSION,
    description: '一名学生一次签到、按固定顺序完成全部项目、一次提交。',
    items
  };
}

export function protocolSnapshotFromTask(task) {
  const snapshot = task?.protocol_snapshot_json || task?.protocolSnapshot;
  if (snapshot && typeof snapshot === 'object' && Array.isArray(snapshot.items) && snapshot.items.length) {
    return {
      id: String(snapshot.id || task.protocol_id || BASELINE_ASSESSMENT_PROTOCOL_ID),
      code: String(snapshot.code || BASELINE_ASSESSMENT_PROTOCOL_CODE),
      name: String(snapshot.name || '测评方案'),
      version: String(snapshot.version || task.protocol_version || BASELINE_ASSESSMENT_PROTOCOL_VERSION),
      description: String(snapshot.description || ''),
      items: snapshot.items.map(normalizeSnapshotItem).sort((left, right) => left.sequenceNo - right.sequenceNo)
    };
  }
  return baselineAssessmentProtocolSnapshot(Array.isArray(task?.items) ? task.items : MOVEMENT_ITEM_CODES);
}

export async function resolveAssessmentProtocol(executor, { schoolId, protocolId = null, taskItems = null, testDate = null }) {
  if (!protocolId) return baselineAssessmentProtocolSnapshot(taskItems || MOVEMENT_ITEM_CODES);
  const result = await executor.query(`SELECT p.id,p.protocol_code AS code,p.name,p.version,p.description,
      COALESCE(jsonb_agg(jsonb_build_object('code',i.item_code,'name',i.item_name,'sequenceNo',i.sequence_no,'required',i.required,'sensorProfile',i.sensor_profile_json,'ruleConfig',i.rule_config_json) ORDER BY i.sequence_no) FILTER(WHERE i.id IS NOT NULL),'[]'::jsonb) AS items
    FROM assessment_protocols p LEFT JOIN assessment_protocol_items i ON i.protocol_id=p.id
    WHERE p.id=$1 AND (p.school_id IS NULL OR p.school_id=$2) AND p.status='active' AND ($3::date IS NULL OR p.effective_date<=$3::date)
    GROUP BY p.id`, [protocolId, schoolId, testDate]);
  const row = result.rows[0];
  if (!row) throw Object.assign(new Error('测试方案不存在、未启用或不属于当前学校'), { status: 400, code: 'ASSESSMENT_PROTOCOL_NOT_FOUND' });
  const snapshot = { ...row, items: (row.items || []).map(normalizeSnapshotItem).sort((left, right) => left.sequenceNo - right.sequenceNo) };
  if (!snapshot.items.length) throw Object.assign(new Error('测试方案没有配置任何项目'), { status: 409, code: 'ASSESSMENT_PROTOCOL_EMPTY' });
  return snapshot;
}

export function protocolTaskItems(snapshot) {
  return snapshot.items.map((item) => item.code);
}
