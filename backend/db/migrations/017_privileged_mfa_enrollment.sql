ALTER TABLE auth_mfa_challenges ADD COLUMN IF NOT EXISTS purpose TEXT NOT NULL DEFAULT 'verify';
ALTER TABLE auth_mfa_challenges ADD COLUMN IF NOT EXISTS pending_secret_encrypted TEXT;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='auth_mfa_challenges_purpose_check' AND conrelid='auth_mfa_challenges'::regclass) THEN
    ALTER TABLE auth_mfa_challenges ADD CONSTRAINT auth_mfa_challenges_purpose_check CHECK (purpose IN ('verify', 'enroll')) NOT VALID;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname='auth_mfa_challenges_purpose_check' AND conrelid='auth_mfa_challenges'::regclass AND NOT convalidated) THEN
    ALTER TABLE auth_mfa_challenges VALIDATE CONSTRAINT auth_mfa_challenges_purpose_check;
  END IF;
END $$;
