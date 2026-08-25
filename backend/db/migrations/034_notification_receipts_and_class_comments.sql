-- Class notices need an auditable parent acknowledgement lifecycle. Messages
-- are delivery records; receipts are business records tied to a campaign.
CREATE TABLE IF NOT EXISTS notification_receipts (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  campaign_id TEXT NOT NULL REFERENCES notification_campaigns(id) ON DELETE CASCADE,
  receiver_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending',
  acknowledged_at TIMESTAMPTZ,
  version INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (status IN ('pending', 'acknowledged')),
  UNIQUE(campaign_id, receiver_user_id)
);
CREATE INDEX IF NOT EXISTS idx_notification_receipts_campaign ON notification_receipts(campaign_id, status);

ALTER TABLE class_post_comments ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
CREATE INDEX IF NOT EXISTS idx_class_post_comments_post_created ON class_post_comments(post_id, created_at DESC)
  WHERE deleted_at IS NULL;
