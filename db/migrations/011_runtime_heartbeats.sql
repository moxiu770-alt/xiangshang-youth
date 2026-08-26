CREATE TABLE IF NOT EXISTS runtime_heartbeats (
  component TEXT NOT NULL,
  instance_id TEXT NOT NULL,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (component, instance_id)
);
CREATE INDEX IF NOT EXISTS idx_runtime_heartbeats_component_seen ON runtime_heartbeats(component, last_seen_at DESC);
