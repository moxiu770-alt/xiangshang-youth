-- Optional, privacy-minimised product improvement events. These rows contain
-- no account, child, school or health-data foreign key by design.
CREATE TABLE IF NOT EXISTS product_events (
  event_id UUID PRIMARY KEY,
  event_name TEXT NOT NULL CHECK (event_name IN ('growth_report_opened','growth_report_period_changed','adaptive_plan_opened_courses')),
  coarse_value TEXT CHECK (coarse_value IS NULL OR coarse_value IN ('本周','本月')),
  platform TEXT NOT NULL CHECK (platform IN ('ios','android')),
  app_version TEXT NOT NULL CHECK (char_length(app_version) BETWEEN 1 AND 40),
  client_session_hash TEXT NOT NULL CHECK (char_length(client_session_hash) = 64),
  occurred_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_product_events_name_received ON product_events(event_name, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_product_events_retention ON product_events(received_at);
