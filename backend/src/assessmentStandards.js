import { dateOnlyText } from './dateOnly.js';

const defaultRuleConfig = Object.freeze({
  itemCount: 7,
  scoreRange: { min: 0, max: 5 },
  lowConfidenceRequiresReview: true
});

const asDate = (value) => {
  return dateOnlyText(value) || dateOnlyText(new Date());
};

export const assessmentStandardSnapshot = (row, context) => ({
  id: row?.id || null,
  standardVersion: row?.standardVersion || context.fallbackVersion || '运动能力标准 v1.0',
  schoolId: row?.schoolId || context.schoolId,
  gradeId: row?.gradeId || context.gradeId || null,
  region: row?.region || context.region || '',
  povertyArea: row?.povertyArea ?? Boolean(context.povertyArea),
  effectiveDate: dateOnlyText(row?.effectiveDate) || asDate(context.testDate),
  ruleConfig: row?.ruleConfig || defaultRuleConfig,
  reportConfig: row?.reportConfig || {},
  courseConfig: row?.courseConfig || {},
  source: row?.id ? 'configured' : 'baseline'
});

export async function resolveAssessmentStandard(executor, context) {
  const result = await executor.query(`SELECT id,school_id AS "schoolId",grade_id AS "gradeId",region,poverty_area AS "povertyArea",standard_version AS "standardVersion",rule_config AS "ruleConfig",report_config AS "reportConfig",course_config AS "courseConfig",effective_date::text AS "effectiveDate"
    FROM assessment_standards
    WHERE status='active' AND effective_date<=$1
      AND (school_id IS NULL OR school_id=$2)
      AND (grade_id IS NULL OR grade_id=$3)
      AND (region='' OR region=$4)
      AND (poverty_area IS NULL OR poverty_area=$5)
    ORDER BY (school_id IS NOT NULL) DESC,(grade_id IS NOT NULL) DESC,(region <> '') DESC,(poverty_area IS NOT NULL) DESC,effective_date DESC,created_at DESC
    LIMIT 1`, [asDate(context.testDate), context.schoolId, context.gradeId || null, context.region || '', Boolean(context.povertyArea)]);
  return assessmentStandardSnapshot(result.rows[0] || null, context);
}
