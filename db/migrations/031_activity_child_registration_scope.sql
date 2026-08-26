-- A family may register more than one bound child for the same activity.
-- Preserve the legacy family-level NULL child bucket while making child scope
-- part of the stable registration identity.
ALTER TABLE activity_registrations DROP CONSTRAINT IF EXISTS activity_registrations_activity_id_user_id_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_activity_registrations_activity_user_child
  ON activity_registrations(activity_id, user_id, COALESCE(child_id, '__family__'));
CREATE INDEX IF NOT EXISTS idx_activity_registrations_child_history
  ON activity_registrations(user_id, child_id, updated_at DESC);
