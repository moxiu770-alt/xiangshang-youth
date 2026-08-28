ALTER TABLE test_stations
  ADD COLUMN IF NOT EXISTS status_reason TEXT,
  ADD COLUMN IF NOT EXISTS status_changed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS status_changed_by TEXT REFERENCES users(id) ON DELETE SET NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname='test_stations_status_reason_length_check'
      AND conrelid='test_stations'::regclass
  ) THEN
    ALTER TABLE test_stations
      ADD CONSTRAINT test_stations_status_reason_length_check
      CHECK (status_reason IS NULL OR char_length(status_reason) BETWEEN 1 AND 500);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_test_stations_status_changed
  ON test_stations(school_id, status_changed_at DESC)
  WHERE status <> 'online';
