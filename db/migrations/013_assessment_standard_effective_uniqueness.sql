-- One exact policy scope may have only one effective standard on a given
-- date. This avoids a non-deterministic tie when a field device resolves its
-- immutable session snapshot.
-- Legacy installs could have multiple active rows before this guarantee was
-- introduced. Keep the newest one deterministically and retain every older
-- version as archived audit history rather than making the upgrade fail.
WITH ranked AS (
  SELECT id, ROW_NUMBER() OVER (
    PARTITION BY COALESCE(school_id, ''), COALESCE(grade_id, ''), region,
      COALESCE(poverty_area::text, 'any'), effective_date
    ORDER BY created_at DESC, id DESC
  ) AS position
  FROM assessment_standards
  WHERE status='active'
)
UPDATE assessment_standards standard
SET status='archived', updated_at=now()
FROM ranked
WHERE standard.id=ranked.id AND ranked.position>1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_assessment_standards_active_scope_date
  ON assessment_standards(
    COALESCE(school_id, ''),
    COALESCE(grade_id, ''),
    region,
    COALESCE(poverty_area::text, 'any'),
    effective_date
  )
  WHERE status='active';
