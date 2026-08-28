ALTER TABLE body_screening_decisions
  ADD COLUMN IF NOT EXISTS outcome_level TEXT;

UPDATE body_screening_decisions
SET outcome_level = CASE
  WHEN route = 'recapture_required' THEN 'capture_invalid'
  WHEN route = 'professional_review' THEN 'school_retest'
  ELSE 'no_obvious_abnormality'
END
WHERE outcome_level IS NULL;

ALTER TABLE body_screening_decisions
  ALTER COLUMN outcome_level SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'body_screening_decisions_outcome_level_check'
  ) THEN
    ALTER TABLE body_screening_decisions
      ADD CONSTRAINT body_screening_decisions_outcome_level_check
      CHECK (outcome_level IN (
        'capture_invalid',
        'no_obvious_abnormality',
        'training_observation',
        'school_retest',
        'professional_evaluation'
      ));
  END IF;
END $$;
