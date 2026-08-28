ALTER TABLE test_devices
  ADD COLUMN IF NOT EXISTS control_state TEXT NOT NULL DEFAULT 'running',
  ADD COLUMN IF NOT EXISTS control_state_updated_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'test_devices_control_state_check'
      AND conrelid = 'test_devices'::regclass
  ) THEN
    ALTER TABLE test_devices
      ADD CONSTRAINT test_devices_control_state_check
      CHECK (control_state IN ('running', 'paused', 'stopped'));
  END IF;
END $$;

-- Preserve the latest safety command when an existing installation upgrades.
-- A new default must never silently override a pause that was already issued.
WITH latest AS (
  SELECT DISTINCT ON (device_id) device_id, command_type, acknowledged_at, created_at
  FROM device_commands
  WHERE command_type IN ('pause', 'stop', 'resume')
    AND status <> 'cancelled'
  ORDER BY device_id, created_at DESC
)
UPDATE test_devices device
SET control_state = CASE latest.command_type
      WHEN 'pause' THEN 'paused'
      WHEN 'stop' THEN 'stopped'
      WHEN 'resume' THEN 'running'
      ELSE device.control_state
    END,
    control_state_updated_at = COALESCE(latest.acknowledged_at, latest.created_at)
FROM latest
WHERE latest.device_id = device.id;
