-- The migrator stores a SHA-256 checksum for every SQL migration. Future
-- deploys fail closed if a previously applied migration is edited in place.
ALTER TABLE schema_migrations
  ADD COLUMN IF NOT EXISTS checksum_sha256 TEXT;
