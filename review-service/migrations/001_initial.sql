CREATE TABLE IF NOT EXISTS reviews (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'revoked', 'deleted')),
  title TEXT NOT NULL,
  public_token_hash TEXT NOT NULL UNIQUE,
  publisher_token_hash TEXT NOT NULL,
  publisher_id TEXT NOT NULL,
  keychain_account TEXT NOT NULL,
  review_url TEXT NOT NULL,
  target_file TEXT,
  target_relative_path TEXT,
  vault_id TEXT,
  latest_version INTEGER NOT NULL DEFAULT 0,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS review_versions (
  review_id TEXT NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  version INTEGER NOT NULL,
  snapshot_html TEXT NOT NULL,
  markdown_source TEXT NOT NULL,
  source_map_json JSONB NOT NULL,
  content_hash TEXT NOT NULL,
  anchor_normalizer_version INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (review_id, version)
);

CREATE TABLE IF NOT EXISTS review_comments (
  id TEXT PRIMARY KEY,
  review_id TEXT NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  version INTEGER NOT NULL,
  parent_comment_id TEXT REFERENCES review_comments(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'open',
  author_id TEXT NOT NULL,
  author_display_name TEXT NOT NULL,
  body TEXT NOT NULL,
  selected_text TEXT,
  suggested_replacement TEXT,
  suggestion_mode TEXT NOT NULL DEFAULT 'advisory',
  anchor JSONB NOT NULL,
  current_anchor JSONB NOT NULL,
  anchor_confidence TEXT NOT NULL DEFAULT 'exact' CHECK (anchor_confidence IN ('exact', 'fuzzy', 'section', 'orphan')),
  anchor_remap_reason TEXT,
  anchor_remapped_version INTEGER,
  anchor_remapped_at TIMESTAMPTZ,
  remote_revision INTEGER NOT NULL DEFAULT 1,
  resolved_by TEXT,
  resolved_at TIMESTAMPTZ,
  resolution_note TEXT,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS review_comments_review_order_idx
  ON review_comments (review_id, created_at, id);

CREATE TABLE IF NOT EXISTS review_forks (
  id TEXT PRIMARY KEY,
  review_id TEXT NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  version INTEGER NOT NULL,
  author_id TEXT NOT NULL,
  author_display_name TEXT NOT NULL,
  markdown_source TEXT NOT NULL,
  diff_json JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS review_forks_review_order_idx
  ON review_forks (review_id, created_at, id);

CREATE TABLE IF NOT EXISTS review_events (
  id BIGSERIAL PRIMARY KEY,
  review_id TEXT NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  actor_type TEXT NOT NULL,
  actor_id TEXT,
  event_type TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS review_events_review_order_idx
  ON review_events (review_id, created_at, id);
