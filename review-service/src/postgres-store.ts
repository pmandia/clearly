import { Pool, type PoolClient } from "pg";
import { decodeCursor, encodeCursor, makeId, makeToken, sha256, tokenMatches } from "./crypto.js";
import { diffSummary, lineDiff } from "./diff.js";
import type { ReviewStore } from "./store.js";
import type {
  CommentRemapInput,
  CreateCommentInput,
  CreateForkInput,
  CreateReviewInput,
  CreateReviewResult,
  CreateVersionInput,
  Page,
  ReviewComment,
  ReviewForkDetail,
  ReviewForkSummary,
  ReviewRecord,
  ReviewVersion,
  UpdateCommentInput,
} from "./types.js";

export class PostgresReviewStore implements ReviewStore {
  constructor(private readonly pool: Pool) {}

  static fromDatabaseUrl(databaseUrl: string): PostgresReviewStore {
    return new PostgresReviewStore(new Pool({ connectionString: databaseUrl }));
  }

  async createReview(input: CreateReviewInput, publicBaseUrl: string): Promise<CreateReviewResult> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const reviewId = makeId("rvw");
      const publicReviewToken = makeToken();
      const publisherAccessToken = makeToken();
      const publisherId = makeId("pub");
      const keychainAccount = `clearly-review-${reviewId}`;
      const reviewUrl = `${publicBaseUrl.replace(/\/$/, "")}/r/${publicReviewToken}`;
      const reviewResult = await client.query(
        `INSERT INTO reviews (
          id, title, public_token_hash, publisher_token_hash, publisher_id,
          keychain_account, review_url, target_file, target_relative_path, vault_id, latest_version
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,1)
        RETURNING *`,
        [
          reviewId,
          input.title,
          sha256(publicReviewToken),
          sha256(publisherAccessToken),
          publisherId,
          keychainAccount,
          reviewUrl,
          input.targetFile,
          input.targetRelativePath,
          input.vaultId,
        ]
      );
      const versionResult = await client.query(
        `INSERT INTO review_versions (
          review_id, version, snapshot_html, markdown_source, source_map_json,
          content_hash, anchor_normalizer_version
        ) VALUES ($1,1,$2,$3,$4,$5,$6)
        RETURNING *`,
        [
          reviewId,
          input.snapshotHtml,
          input.markdownSource,
          JSON.stringify(input.sourceMapJson),
          input.contentHash,
          input.anchorNormalizerVersion,
        ]
      );
      await this.insertEvent(client, reviewId, "publisher", publisherId, "review.created", { version: 1 });
      await client.query("COMMIT");
      return {
        review: mapReview(reviewResult.rows[0]),
        version: mapVersion(versionResult.rows[0]),
        publicReviewToken,
        publisherAccessToken,
      };
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async getReview(reviewId: string): Promise<ReviewRecord | undefined> {
    const result = await this.pool.query("SELECT * FROM reviews WHERE id = $1", [reviewId]);
    return result.rows[0] ? mapReview(result.rows[0]) : undefined;
  }

  async getReviewByPublicToken(publicToken: string): Promise<ReviewRecord | undefined> {
    const hash = sha256(publicToken);
    const result = await this.pool.query("SELECT * FROM reviews WHERE public_token_hash = $1 AND status = 'open' AND revoked_at IS NULL", [hash]);
    return result.rows[0] ? mapReview(result.rows[0]) : undefined;
  }

  async verifyPublisher(reviewId: string, token: string, adminTokenHash?: string): Promise<boolean> {
    const review = await this.getReview(reviewId);
    if (!review) return false;
    return tokenMatches(token, review.publisherTokenHash) || (adminTokenHash ? tokenMatches(token, adminTokenHash) : false);
  }

  async revokeReview(reviewId: string, reason: string | undefined, actorId: string | undefined): Promise<ReviewRecord | undefined> {
    const result = await this.pool.query(
      `UPDATE reviews
       SET status = 'revoked', revoked_at = now(), updated_at = now()
       WHERE id = $1 AND status = 'open'
       RETURNING *`,
      [reviewId]
    );
    const row = result.rows[0] ?? (await this.pool.query("SELECT * FROM reviews WHERE id = $1", [reviewId])).rows[0];
    if (row) {
      await this.logEvent(reviewId, "publisher", actorId, "review.revoked", { reason: reason ?? "" });
    }
    return row ? mapReview(row) : undefined;
  }

  async rotatePublicToken(reviewId: string, publicBaseUrl: string, reason: string | undefined, actorId: string | undefined): Promise<{ review: ReviewRecord; publicReviewToken: string } | undefined> {
    const publicReviewToken = makeToken();
    const reviewUrl = `${publicBaseUrl.replace(/\/$/, "")}/r/${publicReviewToken}`;
    const result = await this.pool.query(
      `UPDATE reviews
       SET public_token_hash = $2, review_url = $3, updated_at = now()
       WHERE id = $1 AND status = 'open'
       RETURNING *`,
      [reviewId, sha256(publicReviewToken), reviewUrl]
    );
    if (!result.rows[0]) return undefined;
    await this.logEvent(reviewId, "publisher", actorId, "link.rotated", { reason: reason ?? "" });
    return { review: mapReview(result.rows[0]), publicReviewToken };
  }

  async addVersion(reviewId: string, input: CreateVersionInput): Promise<ReviewVersion> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const nextVersion = await client.query("SELECT COALESCE(MAX(version), 0) + 1 AS version FROM review_versions WHERE review_id = $1", [reviewId]);
      const version = Number(nextVersion.rows[0].version);
      const result = await client.query(
        `INSERT INTO review_versions (
          review_id, version, snapshot_html, markdown_source, source_map_json,
          content_hash, anchor_normalizer_version
        ) VALUES ($1,$2,$3,$4,$5,$6,$7)
        RETURNING *`,
        [
          reviewId,
          version,
          input.snapshotHtml,
          input.markdownSource,
          JSON.stringify(input.sourceMapJson),
          input.contentHash,
          input.anchorNormalizerVersion,
        ]
      );
      await client.query("UPDATE reviews SET latest_version = $2, updated_at = now() WHERE id = $1", [reviewId, version]);
      await this.insertEvent(client, reviewId, "publisher", undefined, "version.published", { version });
      await client.query("COMMIT");
      return mapVersion(result.rows[0]);
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async getVersion(reviewId: string, version: number): Promise<ReviewVersion | undefined> {
    const result = await this.pool.query("SELECT * FROM review_versions WHERE review_id = $1 AND version = $2", [reviewId, version]);
    return result.rows[0] ? mapVersion(result.rows[0]) : undefined;
  }

  async getLatestVersion(reviewId: string): Promise<ReviewVersion | undefined> {
    const result = await this.pool.query("SELECT * FROM review_versions WHERE review_id = $1 ORDER BY version DESC LIMIT 1", [reviewId]);
    return result.rows[0] ? mapVersion(result.rows[0]) : undefined;
  }

  async listVersions(reviewId: string, cursor: string | undefined, limit: number): Promise<Page<ReviewVersion>> {
    const cursorValue = decodeCursor(cursor);
    const params: unknown[] = [reviewId, limit];
    let where = "review_id = $1";
    if (cursorValue) {
      params.splice(1, 0, cursorValue.createdAt, Number(cursorValue.id));
      where += " AND (created_at, version) > ($2::timestamptz, $3::int)";
    }
    const limitParam = `$${params.length}`;
    const result = await this.pool.query(
      `SELECT * FROM review_versions WHERE ${where} ORDER BY created_at ASC, version ASC LIMIT ${limitParam}`,
      params
    );
    const items = result.rows.map(mapVersion);
    const last = items.at(-1);
    return {
      items,
      nextCursor: items.length === limit && last ? encodeCursor({ createdAt: last.createdAt, id: String(last.version) }) : undefined,
    };
  }

  async listComments(reviewId: string, cursor: string | undefined, limit: number, status?: string): Promise<Page<ReviewComment>> {
    const cursorValue = decodeCursor(cursor);
    const params: unknown[] = [reviewId];
    let where = "review_id = $1 AND deleted_at IS NULL";
    if (status) {
      params.push(status);
      where += ` AND status = $${params.length}`;
    }
    if (cursorValue) {
      params.push(cursorValue.createdAt, cursorValue.id);
      where += ` AND (created_at, id) > ($${params.length - 1}::timestamptz, $${params.length})`;
    }
    params.push(limit);
    const result = await this.pool.query(
      `SELECT * FROM review_comments WHERE ${where} ORDER BY created_at ASC, id ASC LIMIT $${params.length}`,
      params
    );
    const items = result.rows.map(mapComment);
    const last = items.at(-1);
    return {
      items,
      nextCursor: items.length === limit && last ? encodeCursor({ createdAt: last.createdAt, id: last.id }) : undefined,
    };
  }

  async createComment(reviewId: string, input: CreateCommentInput): Promise<ReviewComment> {
    const id = makeId("cmt");
    const result = await this.pool.query(
      `INSERT INTO review_comments (
        id, review_id, version, parent_comment_id, author_id, author_display_name,
        body, selected_text, suggested_replacement, suggestion_mode, anchor,
        current_anchor, anchor_confidence, anchor_remap_reason, anchor_remapped_version
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$11,$12,'authored_anchor',$3)
      RETURNING *`,
      [
        id,
        reviewId,
        input.version,
        input.parentCommentId,
        input.authorId,
        input.authorDisplayName,
        input.body,
        input.selectedText,
        input.suggestedReplacement,
        input.suggestionMode,
        JSON.stringify(input.anchor),
        anchorConfidence(input.anchor),
      ]
    );
    await this.logEvent(reviewId, "reviewer", input.authorId, "comment.created", { commentId: id });
    return mapComment(result.rows[0]);
  }

  async updateComment(reviewId: string, commentId: string, input: UpdateCommentInput): Promise<ReviewComment | "conflict" | undefined> {
    const existing = await this.pool.query("SELECT * FROM review_comments WHERE review_id = $1 AND id = $2 AND deleted_at IS NULL", [reviewId, commentId]);
    if (!existing.rows[0] || existing.rows[0].author_id !== input.authorId) return undefined;
    if (Number(existing.rows[0].remote_revision) !== input.expectedRevision) return "conflict";
    const result = await this.pool.query(
      `UPDATE review_comments
       SET body = COALESCE($3, body),
           suggested_replacement = COALESCE($4, suggested_replacement),
           suggestion_mode = COALESCE($5, suggestion_mode),
           remote_revision = remote_revision + 1,
           updated_at = now()
       WHERE review_id = $1 AND id = $2
       RETURNING *`,
      [reviewId, commentId, input.body, input.suggestedReplacement, input.suggestionMode]
    );
    await this.logEvent(reviewId, "reviewer", input.authorId, "comment.edited", { commentId });
    return mapComment(result.rows[0]);
  }

  async updateCommentRemap(reviewId: string, commentId: string, input: CommentRemapInput): Promise<ReviewComment | undefined> {
    const result = await this.pool.query(
      `UPDATE review_comments
       SET current_anchor = $3,
           anchor_confidence = $4,
           anchor_remap_reason = $5,
           anchor_remapped_version = $6,
           anchor_remapped_at = now(),
           updated_at = now()
       WHERE review_id = $1 AND id = $2 AND deleted_at IS NULL
       RETURNING *`,
      [reviewId, commentId, JSON.stringify(input.anchor), input.confidence, input.reason, input.remappedVersion]
    );
    return result.rows[0] ? mapComment(result.rows[0]) : undefined;
  }

  async deleteComment(reviewId: string, commentId: string, authorId: string): Promise<boolean> {
    const result = await this.pool.query(
      `UPDATE review_comments
       SET deleted_at = now(), status = 'deleted', remote_revision = remote_revision + 1, updated_at = now()
       WHERE review_id = $1 AND id = $2 AND author_id = $3 AND deleted_at IS NULL`,
      [reviewId, commentId, authorId]
    );
    if ((result.rowCount ?? 0) > 0) {
      await this.logEvent(reviewId, "reviewer", authorId, "comment.deleted", { commentId });
      return true;
    }
    return false;
  }

  async resolveComment(reviewId: string, commentId: string, expectedRevision: number, resolvedBy: string, note = ""): Promise<ReviewComment | "conflict" | undefined> {
    const existing = await this.pool.query("SELECT remote_revision FROM review_comments WHERE review_id = $1 AND id = $2 AND deleted_at IS NULL", [reviewId, commentId]);
    if (!existing.rows[0]) return undefined;
    if (Number(existing.rows[0].remote_revision) !== expectedRevision) return "conflict";
    const result = await this.pool.query(
      `UPDATE review_comments
       SET status = 'resolved',
           resolved_by = $3,
           resolved_at = now(),
           resolution_note = $4,
           remote_revision = remote_revision + 1,
           updated_at = now()
       WHERE review_id = $1 AND id = $2
       RETURNING *`,
      [reviewId, commentId, resolvedBy, note]
    );
    await this.logEvent(reviewId, "publisher", resolvedBy, "agent.resolution_confirmed", { commentId });
    return mapComment(result.rows[0]);
  }

  async reopenComment(reviewId: string, commentId: string, expectedRevision: number, authorId: string): Promise<ReviewComment | "conflict" | undefined> {
    const existing = await this.pool.query(
      "SELECT remote_revision, author_id FROM review_comments WHERE review_id = $1 AND id = $2 AND deleted_at IS NULL",
      [reviewId, commentId]
    );
    if (!existing.rows[0] || existing.rows[0].author_id !== authorId) return undefined;
    if (Number(existing.rows[0].remote_revision) !== expectedRevision) return "conflict";
    const result = await this.pool.query(
      `UPDATE review_comments
       SET status = 'open',
           resolved_by = NULL,
           resolved_at = NULL,
           resolution_note = NULL,
           remote_revision = remote_revision + 1,
           updated_at = now()
       WHERE review_id = $1 AND id = $2
       RETURNING *`,
      [reviewId, commentId]
    );
    await this.logEvent(reviewId, "reviewer", authorId, "comment.reopened", { commentId });
    return mapComment(result.rows[0]);
  }

  async createFork(reviewId: string, input: CreateForkInput): Promise<ReviewForkDetail | undefined> {
    const base = await this.getVersion(reviewId, input.version);
    if (!base) return undefined;
    const diff = lineDiff(input.version, base.markdownSource, input.markdownSource);
    const summary = diffSummary(diff);
    const forkId = makeId("frk");
    const result = await this.pool.query(
      `INSERT INTO review_forks (
        id, review_id, version, author_id, author_display_name, markdown_source, diff_json
      ) VALUES ($1,$2,$3,$4,$5,$6,$7)
      RETURNING *`,
      [forkId, reviewId, input.version, input.authorId, input.authorDisplayName, input.markdownSource, JSON.stringify(diff)]
    );
    await this.logEvent(reviewId, "reviewer", input.authorId, "fork.submitted", { forkId });
    return { ...mapFork(result.rows[0]), diffSummary: summary };
  }

  async listForks(reviewId: string, cursor: string | undefined, limit: number): Promise<Page<ReviewForkSummary>> {
    const cursorValue = decodeCursor(cursor);
    const params: unknown[] = [reviewId];
    let where = "review_id = $1";
    if (cursorValue) {
      params.push(cursorValue.createdAt, cursorValue.id);
      where += ` AND (created_at, id) > ($${params.length - 1}::timestamptz, $${params.length})`;
    }
    params.push(limit);
    const result = await this.pool.query(
      `SELECT * FROM review_forks WHERE ${where} ORDER BY created_at ASC, id ASC LIMIT $${params.length}`,
      params
    );
    const items = result.rows.map(mapFork).map(({ forkId, version, authorDisplayName, createdAt, diffSummary }) => ({
      forkId,
      version,
      authorDisplayName,
      createdAt,
      diffSummary,
    }));
    const last = items.at(-1);
    return {
      items,
      nextCursor: items.length === limit && last ? encodeCursor({ createdAt: last.createdAt, id: last.forkId }) : undefined,
    };
  }

  async getFork(reviewId: string, forkId: string): Promise<ReviewForkDetail | undefined> {
    const result = await this.pool.query("SELECT * FROM review_forks WHERE review_id = $1 AND id = $2", [reviewId, forkId]);
    return result.rows[0] ? mapFork(result.rows[0]) : undefined;
  }

  async logEvent(reviewId: string, actorType: string, actorId: string | undefined, eventType: string, payload: unknown = {}): Promise<void> {
    await this.pool.query(
      "INSERT INTO review_events (review_id, actor_type, actor_id, event_type, payload) VALUES ($1,$2,$3,$4,$5)",
      [reviewId, actorType, actorId, eventType, JSON.stringify(payload)]
    );
  }

  private async insertEvent(client: PoolClient, reviewId: string, actorType: string, actorId: string | undefined, eventType: string, payload: unknown = {}): Promise<void> {
    await client.query(
      "INSERT INTO review_events (review_id, actor_type, actor_id, event_type, payload) VALUES ($1,$2,$3,$4,$5)",
      [reviewId, actorType, actorId, eventType, JSON.stringify(payload)]
    );
  }
}

function mapReview(row: Record<string, unknown>): ReviewRecord {
  return {
    id: String(row.id),
    status: (String(row.status ?? "open") as ReviewRecord["status"]),
    title: String(row.title),
    publicTokenHash: String(row.public_token_hash),
    publisherTokenHash: String(row.publisher_token_hash),
    publisherId: String(row.publisher_id),
    keychainAccount: String(row.keychain_account),
    reviewUrl: String(row.review_url),
    targetFile: optionalString(row.target_file),
    targetRelativePath: optionalString(row.target_relative_path),
    vaultId: optionalString(row.vault_id),
    latestVersion: Number(row.latest_version),
    revokedAt: optionalDate(row.revoked_at),
    createdAt: requiredDate(row.created_at),
    updatedAt: requiredDate(row.updated_at),
  };
}

function mapVersion(row: Record<string, unknown>): ReviewVersion {
  return {
    reviewId: String(row.review_id),
    version: Number(row.version),
    snapshotHtml: String(row.snapshot_html),
    markdownSource: String(row.markdown_source),
    sourceMapJson: row.source_map_json,
    contentHash: String(row.content_hash),
    anchorNormalizerVersion: Number(row.anchor_normalizer_version),
    createdAt: requiredDate(row.created_at),
  };
}

function mapComment(row: Record<string, unknown>): ReviewComment {
  const id = String(row.id);
  return {
    id,
    commentId: id,
    reviewId: String(row.review_id),
    version: Number(row.version),
    parentCommentId: optionalString(row.parent_comment_id),
    status: String(row.status),
    author: String(row.author_display_name),
    authorDisplayName: String(row.author_display_name),
    authorId: String(row.author_id),
    body: String(row.body),
    selectedText: optionalString(row.selected_text),
    suggestedReplacement: optionalString(row.suggested_replacement),
    suggestionMode: String(row.suggestion_mode),
    anchor: row.anchor,
    currentAnchor: row.current_anchor ?? row.anchor,
    anchorConfidence: (String(row.anchor_confidence ?? (row.anchor as { confidence?: unknown } | undefined)?.confidence ?? "exact") as ReviewComment["anchorConfidence"]),
    anchorRemapReason: optionalString(row.anchor_remap_reason),
    anchorRemappedVersion: optionalNumber(row.anchor_remapped_version),
    orphaned: String(row.anchor_confidence ?? "") === "orphan",
    remoteRevision: Number(row.remote_revision),
    createdAt: requiredDate(row.created_at),
    updatedAt: requiredDate(row.updated_at),
    resolvedBy: optionalString(row.resolved_by),
    resolvedAt: optionalDate(row.resolved_at),
    resolutionNote: optionalString(row.resolution_note),
  };
}

function mapFork(row: Record<string, unknown>): ReviewForkDetail {
  const diff = row.diff_json as ReviewForkDetail["diff"];
  return {
    forkId: String(row.id),
    reviewId: String(row.review_id),
    version: Number(row.version),
    authorId: String(row.author_id),
    authorDisplayName: String(row.author_display_name),
    markdownSource: String(row.markdown_source),
    diff,
    diffSummary: diffSummary(diff),
    createdAt: requiredDate(row.created_at),
  };
}

function optionalString(value: unknown): string | undefined {
  return value === null || value === undefined ? undefined : String(value);
}

function optionalNumber(value: unknown): number | undefined {
  return value === null || value === undefined ? undefined : Number(value);
}

function anchorConfidence(anchor: unknown): ReviewComment["anchorConfidence"] {
  if (typeof anchor === "object" && anchor !== null) {
    const value = (anchor as { confidence?: unknown }).confidence;
    if (value === "fuzzy" || value === "section" || value === "orphan") return value;
  }
  return "exact";
}

function requiredDate(value: unknown): string {
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

function optionalDate(value: unknown): string | undefined {
  if (value === null || value === undefined) return undefined;
  return requiredDate(value);
}
