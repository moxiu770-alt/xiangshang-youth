ALTER TABLE data_consents
  ADD COLUMN IF NOT EXISTS consent_id TEXT,
  ADD COLUMN IF NOT EXISTS privacy_policy_version TEXT,
  ADD COLUMN IF NOT EXISTS camera_consent_version TEXT,
  ADD COLUMN IF NOT EXISTS algorithm_notice_version TEXT,
  ADD COLUMN IF NOT EXISTS device_info_hash TEXT,
  ADD COLUMN IF NOT EXISTS app_version TEXT,
  ADD COLUMN IF NOT EXISTS data_retention_notice_accepted BOOLEAN NOT NULL DEFAULT false;

UPDATE data_consents SET consent_id=id WHERE consent_id IS NULL;
ALTER TABLE data_consents ALTER COLUMN consent_id SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_data_consents_consent_id ON data_consents(consent_id);
