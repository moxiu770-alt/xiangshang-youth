ALTER TABLE field_sync_batches
  ADD COLUMN IF NOT EXISTS resolution_status TEXT NOT NULL DEFAULT 'not_applicable',
  ADD COLUMN IF NOT EXISTS resolution_note TEXT,
  ADD COLUMN IF NOT EXISTS resolved_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;

UPDATE field_sync_batches
SET resolution_status = CASE WHEN status='failed' THEN 'open' ELSE 'not_applicable' END
WHERE resolution_status='not_applicable';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname='field_sync_batches_resolution_status_check'
      AND conrelid='field_sync_batches'::regclass
  ) THEN
    ALTER TABLE field_sync_batches
      ADD CONSTRAINT field_sync_batches_resolution_status_check
      CHECK (resolution_status IN ('not_applicable','open','resolved'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_field_sync_batches_open_conflicts
  ON field_sync_batches(device_id, completed_at DESC)
  WHERE status='failed' AND resolution_status='open';
