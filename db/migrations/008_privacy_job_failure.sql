ALTER TABLE privacy_requests DROP CONSTRAINT IF EXISTS privacy_requests_status_check;
ALTER TABLE privacy_requests ADD CONSTRAINT privacy_requests_status_check
  CHECK (status IN ('pending', 'approved', 'processing', 'completed', 'rejected', 'failed'));
