-- Business routes make notifications actionable without using display text as an identifier.
ALTER TABLE messages ADD COLUMN IF NOT EXISTS message_type TEXT;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS business_id TEXT;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS business_route TEXT;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS child_id TEXT REFERENCES students(id) ON DELETE SET NULL;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS task_id TEXT REFERENCES assessment_tasks(id) ON DELETE SET NULL;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS course_id TEXT REFERENCES courses(id) ON DELETE SET NULL;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS lesson_id TEXT REFERENCES course_lessons(id) ON DELETE SET NULL;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS action_label TEXT;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_messages_route ON messages(receiver_user_id, business_route, created_at DESC);

ALTER TABLE notification_campaigns ADD COLUMN IF NOT EXISTS sender_teacher_id TEXT REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE notification_campaigns ADD COLUMN IF NOT EXISTS draft_version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE notification_campaigns ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMPTZ;
ALTER TABLE notification_campaigns ADD COLUMN IF NOT EXISTS failure_reason TEXT;
ALTER TABLE notification_campaigns ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
ALTER TABLE notification_campaigns ADD COLUMN IF NOT EXISTS parent_receipt_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE notification_campaigns ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE notification_campaigns DROP CONSTRAINT IF EXISTS notification_campaigns_status_check;
ALTER TABLE notification_campaigns ADD CONSTRAINT notification_campaigns_status_check CHECK (status IN ('draft', 'queued', 'sent', 'partial', 'failed'));
CREATE UNIQUE INDEX IF NOT EXISTS uq_notification_campaign_idempotency ON notification_campaigns(created_by, idempotency_key) WHERE idempotency_key IS NOT NULL;
