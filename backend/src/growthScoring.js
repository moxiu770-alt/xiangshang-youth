/**
 * Canonical growth-plan policy.
 *
 * This is a habit/plan recommendation model, not a medical outcome model.
 * Date-only activity records are validated in the Asia/Shanghai business
 * calendar so the server and native clients cannot disagree at midnight.
 */
import { MODEL_CALIBRATION_VERSION } from './modelCalibration.js';
import { MODEL_REGISTRY_VERSION } from './modelRegistry.js';

export const GROWTH_ALGORITHM_VERSION = 'UY-GROWTH-RULE-1.1';
export const GROWTH_PERIODS = Object.freeze({
  week: Object.freeze({ dayCount: 7, targetActiveDays: 4 }),
  month: Object.freeze({ dayCount: 30, targetActiveDays: 16 })
});

const totalMaximum = 35;
const attentionTotalThreshold = 25;
const finiteNumeric = (value) => {
  // Keep malformed JSON values from becoming zero through Number([])/Number(false).
  if (value == null || typeof value === 'boolean' || typeof value === 'object' || typeof value === 'function' || (typeof value === 'string' && value.trim() === '')) return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
};
const businessDateFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit'
});

function businessDateKey(value) {
  if (!(value instanceof Date) || !Number.isFinite(value.getTime())) return null;
  const parts = Object.fromEntries(businessDateFormatter.formatToParts(value).filter((part) => part.type !== 'literal').map((part) => [part.type, part.value]));
  return `${parts.year}-${parts.month}-${parts.day}`;
}

function parseDateKey(value) {
  const raw = String(value ?? '').trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return null;
  const [year, month, day] = raw.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
  return raw;
}

function dateKeyAddDays(key, days) {
  const [year, month, day] = key.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function recentDateKeys(values, now, dayCount) {
  const end = businessDateKey(now);
  if (!end) return new Set();
  const start = dateKeyAddDays(end, -(dayCount - 1));
  return new Set((Array.isArray(values) || values instanceof Set ? [...values] : [])
    .map(parseDateKey)
    .filter((date) => date != null && date >= start && date <= end));
}

function planFor({ bodyAttention, consistencyPercent, totalScore }) {
  if (bodyAttention === 'red') return ['低冲击观察计划', '身体测评出现需进一步关注的信号，本周优先轻量活动与复测，不增加动作强度。', 3, 10, ['完成一次家长陪同复测', '选择低冲击姿态课程', '出现疼痛或活动受限时停止并咨询专业人员']];
  if (bodyAttention === 'yellow') return ['姿态巩固计划', '根据近期记录，已缩短单次时长并增加姿态练习。', 4, 12, ['完成 2 次肩背与站姿练习', '完成 1 次自然步态观察', '按提醒日期复测并记录变化']];
  if (bodyAttention === 'pending') return ['完成家庭观察计划', '拍摄任务尚未完成；先完成剩余引导，不将未完成记录当作健康风险。', 2, 8, ['完成剩余拍摄记录', '由家长确认观察结果', '完成后再查看训练建议']];
  if (bodyAttention === 'unavailable') return ['完善成长资料计划', '尚缺少年龄别 BMI 筛查所需的生日信息；先补全资料，再生成对应参考。', 2, 8, ['核对孩子生日', '保留本次真实身高体重', '资料完整后查看年龄别 BMI 参考']];
  if (consistencyPercent < 50) return ['轻量习惯计划', '近期完成率低于目标，先降低开始门槛，建立稳定运动习惯。', 3, 10, ['任选 3 天完成 10 分钟运动', '每次训练后完成打卡', '周末回顾一次身体感受']];
  if (totalScore != null && totalScore < attentionTotalThreshold) return ['基础能力提升计划', '综合运动能力仍有提升空间，计划保持中等频率并优先练习薄弱项。', 4, 15, ['完成 2 次薄弱能力课程', '完成 1 次平衡或协调练习', '训练后记录难度与完成感受']];
  return ['均衡成长计划', '近期完成率和测评状态稳定，维持当前节奏并逐步增加动作质量。', 4, 15, ['完成 2 次综合能力课程', '完成 1 次户外运动', '保留 1 天亲子轻松活动']];
}

export function scoreGrowth({ period = 'week', checkInDates = [], planDates = [], assessmentCount = 0, bodyAttention = null, totalScore = null, now = new Date() } = {}) {
  const resolvedPeriod = Object.prototype.hasOwnProperty.call(GROWTH_PERIODS, period) ? period : 'week';
  const config = GROWTH_PERIODS[resolvedPeriod];
  const checkIns = recentDateKeys(checkInDates, now, config.dayCount);
  const plans = recentDateKeys(planDates, now, config.dayCount);
  const activeDates = new Set([...checkIns, ...plans]);
  const consistencyPercent = Math.min(100, Math.max(0, Math.round(activeDates.size / Math.max(config.targetActiveDays, 1) * 100)));
  const numericScore = finiteNumeric(totalScore);
  const safeScore = numericScore != null
    ? Math.min(totalMaximum, Math.max(0, numericScore))
    : null;
  const numericAssessmentCount = finiteNumeric(assessmentCount);
  const plan = planFor({ bodyAttention, consistencyPercent, totalScore: safeScore });
  return {
    algorithm: GROWTH_ALGORITHM_VERSION,
    calibrationVersion: MODEL_CALIBRATION_VERSION,
    modelRegistryVersion: MODEL_REGISTRY_VERSION,
    period: resolvedPeriod,
    activeDays: activeDates.size,
    targetActiveDays: config.targetActiveDays,
    planDays: plans.size,
    assessmentCount: Math.max(0, numericAssessmentCount == null ? 0 : Math.floor(numericAssessmentCount)),
    consistencyPercent,
    planTitle: plan[0], planReason: plan[1], sessionsPerWeek: plan[2], minutesPerSession: plan[3], actions: plan[4]
  };
}
