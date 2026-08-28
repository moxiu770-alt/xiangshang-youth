import { pool, query } from './db.js';
import { auditEvent } from './audit.js';
import { resolveAssessmentStandard } from './assessmentStandards.js';
import { MODEL_CALIBRATION_VERSION } from './modelCalibration.js';
import { MODEL_REGISTRY_VERSION } from './modelRegistry.js';
import { MOVEMENT_ALGORITHM_VERSION, evaluateMovementScores, normalizeTotalScore } from './scoring.js';
import { dateOnlyText } from './dateOnly.js';

const reportStudentRow = (row) => ({
  id: row.id,
  name: row.name,
  gender: row.gender,
  grade: row.grade_name,
  className: row.class_name,
  region: row.region,
  isPovertyArea: row.is_poverty_area,
  taskStatus: row.task_status || '未签到',
  totalScore: row.total_score == null ? null : normalizeTotalScore(row.total_score),
  birthDate: dateOnlyText(row.birth_date)
});

const assessmentStandardContext = (student, task) => ({
  schoolId: student.school_id,
  gradeId: student.grade_id || task.grade_id || null,
  region: student.region || '',
  povertyArea: Boolean(student.is_poverty_area),
  testDate: task.test_date,
  fallbackVersion: task.rule_version
});

/**
 * Resolve configured mappings to stable playable IDs.  This intentionally
 * returns an empty list when operations has not configured a rule; generating
 * a plausible title here would let the app navigate to the wrong content.
 */
async function courseSuggestionsForReport(student, riskLevel) {
  const result = await query(`SELECT r.id,
      c.id AS "courseId", l.id AS "lessonId", l.title,
      l.duration_ms AS "durationMs", r.focus,
      r.is_public_benefit AS "isPublicBenefit"
    FROM course_recommendations r
    JOIN courses c ON c.id=r.course_id AND c.status='active'
    JOIN course_lessons l ON l.id=r.lesson_id AND l.course_id=c.id AND l.status='active'
    WHERE r.active=true
      AND (r.school_id IS NULL OR r.school_id=$1)
      AND (r.grade_id IS NULL OR r.grade_id=$2)
      AND (r.risk_level IS NULL OR r.risk_level=$3)
      AND (c.school_id IS NULL OR c.school_id=$1)
    ORDER BY (r.school_id IS NOT NULL) DESC,
      (r.grade_id IS NOT NULL) DESC,
      (r.risk_level IS NOT NULL) DESC,
      r.priority DESC, r.created_at DESC
    LIMIT 3`, [student.school_id, student.grade_id, riskLevel]);
  return result.rows.map((row) => ({
    id: row.id,
    courseId: row.courseId,
    lessonId: row.lessonId,
    title: row.title,
    duration: `${Math.max(1, Math.round(Number(row.durationMs || 0) / 60000))}分钟`,
    focus: row.focus || '运动能力训练',
    isPublicBenefit: Boolean(row.isPublicBenefit)
  }));
}

async function activeStudent(studentId) {
  const result = await query(`SELECT st.*, g.name AS grade_name, c.name AS class_name,
      ts.status AS task_status, dr.total_score
    FROM students st
    JOIN grades g ON g.id=st.grade_id
    JOIN classes c ON c.id=st.class_id
    LEFT JOIN LATERAL (SELECT status FROM task_students WHERE student_id=st.id ORDER BY created_at DESC LIMIT 1) ts ON true
    LEFT JOIN LATERAL (SELECT total_score FROM diagnosis_reports WHERE student_id=st.id AND status='published' ORDER BY generated_at DESC LIMIT 1) dr ON true
    WHERE st.id=$1 AND st.status='active'`, [studentId]);
  return result.rows[0] || null;
}

export async function refreshReportForStudent({ student, taskId = null, operatorId = null, requestId = null, ip = null }) {
  const taskParameters = [student.school_id, student.id];
  const taskFilter = taskId ? ' AND t.id=$3' : '';
  if (taskId) taskParameters.push(taskId);
  const taskResult = await query(`SELECT t.* FROM assessment_tasks t
    JOIN task_students ts ON ts.task_id=t.id
    WHERE t.school_id=$1 AND ts.student_id=$2${taskFilter}
    ORDER BY t.test_date DESC,t.created_at DESC LIMIT 1`, taskParameters);
  const task = taskResult.rows[0];
  if (!task) throw Object.assign(new Error('暂无测评任务'), { code: 'TASK_NOT_FOUND' });

  const sessionStandard = await query(`SELECT standard_snapshot_json AS "standardSnapshot" FROM test_sessions
    WHERE task_id=$1 AND student_id=$2 AND standard_version<>''
    ORDER BY started_at DESC,created_at DESC LIMIT 1`, [task.id, student.id]);
  const storedStandard = sessionStandard.rows[0]?.standardSnapshot;
  const standard = storedStandard && Object.keys(storedStandard).length
    ? storedStandard
    : await resolveAssessmentStandard({ query }, assessmentStandardContext(student, task));
  const scoreResult = await query(`SELECT id,item_code AS item,score,note,confidence,review_status AS "reviewStatus",manual_reviewed AS "humanReviewed",algorithm_version AS "algorithmVersion"
    FROM assessment_scores WHERE task_id=$1 AND student_id=$2 ORDER BY item_code`, [task.id, student.id]);
  const evaluated = evaluateMovementScores(scoreResult.rows);
  const courseSuggestions = await courseSuggestionsForReport(student, evaluated.riskLevel);
  const reportJson = {
    id: `${student.id}-${task.id}`,
    student: reportStudentRow(student),
    assessmentDate: dateOnlyText(task.test_date),
    date: dateOnlyText(task.test_date),
    scores: evaluated.scores,
    scoreCompletionRatio: evaluated.scoreCompletionRatio,
    meanConfidence: evaluated.meanConfidence,
    reviewItems: evaluated.reviewItems,
    requiresReview: evaluated.requiresReview,
    totalScore: evaluated.totalScore,
    riskLevel: evaluated.riskLevel,
    algorithmVersion: MOVEMENT_ALGORITHM_VERSION,
    calibrationVersion: MODEL_CALIBRATION_VERSION,
    modelRegistryVersion: MODEL_REGISTRY_VERSION,
    abilityTags: [],
    riskAlerts: evaluated.riskLevel === 'low' ? [] : ['建议进一步关注测评结果'],
    trainingAdvice: ['每周进行 3 次基础体能与协调性训练'],
    courseSuggestions,
    ruleVersion: standard.standardVersion,
    taskRuleVersion: task.rule_version,
    standard,
    regionPolicy: { id: standard.id || 'baseline', region: standard.region, povertyAreaLabel: standard.povertyArea ? '专项帮扶' : null, standardVersion: standard.standardVersion, effectiveDate: standard.effectiveDate }
  };
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const report = await client.query(`INSERT INTO diagnosis_reports(student_id,task_id,risk_level,total_score,rule_version,status,published_at,published_version)
      VALUES($1,$2,$3,$4,$5,'draft',NULL,NULL)
      ON CONFLICT(student_id,task_id) DO UPDATE SET risk_level=EXCLUDED.risk_level,total_score=EXCLUDED.total_score,rule_version=EXCLUDED.rule_version,current_version=diagnosis_reports.current_version+1,generated_at=now(),status=CASE WHEN diagnosis_reports.published_version IS NULL THEN 'draft' ELSE 'published' END
      RETURNING *`, [student.id, task.id, evaluated.riskLevel, evaluated.totalScore, standard.standardVersion]);
    const stored = report.rows[0];
    await client.query(`INSERT INTO report_versions(report_id,version,report_json,generated_by) VALUES($1,$2,$3,$4)
      ON CONFLICT(report_id,version) DO UPDATE SET report_json=EXCLUDED.report_json`, [stored.id, stored.current_version, reportJson, operatorId]);
    await client.query('COMMIT');
    await auditEvent({ operatorId, schoolId: student.school_id, action: 'report.refresh', resourceType: 'diagnosis_report', resourceId: stored.id, before: null, after: reportJson, ip, requestId: requestId || `report-refresh:${stored.id}:${stored.current_version}` });
    return reportJson;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

export async function refreshReportForStudentId({ studentId, taskId = null, operatorId = null, requestId = null, ip = null }) {
  const student = await activeStudent(studentId);
  if (!student) throw Object.assign(new Error('学生不存在或已停用'), { code: 'STUDENT_NOT_FOUND' });
  return refreshReportForStudent({ student, taskId, operatorId, requestId, ip });
}
