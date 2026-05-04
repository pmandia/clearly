ALTER TABLE reviews
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'open';

ALTER TABLE review_comments
  ADD COLUMN IF NOT EXISTS current_anchor JSONB,
  ADD COLUMN IF NOT EXISTS anchor_confidence TEXT NOT NULL DEFAULT 'exact',
  ADD COLUMN IF NOT EXISTS anchor_remap_reason TEXT,
  ADD COLUMN IF NOT EXISTS anchor_remapped_version INTEGER,
  ADD COLUMN IF NOT EXISTS anchor_remapped_at TIMESTAMPTZ;

UPDATE review_comments
SET current_anchor = anchor
WHERE current_anchor IS NULL;

ALTER TABLE review_comments
  ALTER COLUMN current_anchor SET NOT NULL;
