import { decodeCursor, encodeCursor, makeId, makeToken, sha256, tokenMatches } from "./crypto.js";
import { diffSummary, lineDiff } from "./diff.js";
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

export interface ReviewStore {
  createReview(input: CreateReviewInput, publicBaseUrl: string): Promise<CreateReviewResult>;
  getReview(reviewId: string): Promise<ReviewRecord | undefined>;
  getReviewByPublicToken(publicToken: string): Promise<ReviewRecord | undefined>;
  verifyPublisher(reviewId: string, token: string, adminTokenHash?: string): Promise<boolean>;
  revokeReview(reviewId: string, reason: string | undefined, actorId: string | undefined): Promise<ReviewRecord | undefined>;
  rotatePublicToken(reviewId: string, publicBaseUrl: string, reason: string | undefined, actorId: string | undefined): Promise<{ review: ReviewRecord; publicReviewToken: string } | undefined>;
  addVersion(reviewId: string, input: CreateVersionInput): Promise<ReviewVersion>;
  getVersion(reviewId: string, version: number): Promise<ReviewVersion | undefined>;
  getLatestVersion(reviewId: string): Promise<ReviewVersion | undefined>;
  listVersions(reviewId: string, cursor: string | undefined, limit: number): Promise<Page<ReviewVersion>>;
  listComments(reviewId: string, cursor: string | undefined, limit: number, status?: string): Promise<Page<ReviewComment>>;
  createComment(reviewId: string, input: CreateCommentInput): Promise<ReviewComment>;
  updateComment(reviewId: string, commentId: string, input: UpdateCommentInput): Promise<ReviewComment | "conflict" | undefined>;
  updateCommentRemap(reviewId: string, commentId: string, input: CommentRemapInput): Promise<ReviewComment | undefined>;
  closeComment(reviewId: string, commentId: string, expectedRevision: number, closedBy: string, note?: string): Promise<ReviewComment | "conflict" | undefined>;
  deleteComment(reviewId: string, commentId: string, authorId: string, expectedRevision?: number): Promise<ReviewComment | "conflict" | undefined>;
  deleteCommentAsPublisher(reviewId: string, commentId: string, expectedRevision: number, deletedBy: string): Promise<ReviewComment | "conflict" | undefined>;
  resolveComment(reviewId: string, commentId: string, expectedRevision: number, resolvedBy: string, note?: string): Promise<ReviewComment | "conflict" | undefined>;
  reopenComment(reviewId: string, commentId: string, expectedRevision: number, authorId: string): Promise<ReviewComment | "conflict" | undefined>;
  createFork(reviewId: string, input: CreateForkInput): Promise<ReviewForkDetail | undefined>;
  listForks(reviewId: string, cursor: string | undefined, limit: number): Promise<Page<ReviewForkSummary>>;
  getFork(reviewId: string, forkId: string): Promise<ReviewForkDetail | undefined>;
  logEvent(reviewId: string, actorType: string, actorId: string | undefined, eventType: string, payload?: unknown): Promise<void>;
}

interface StoredFork extends ReviewForkDetail {
  createdAt: string;
}

export class MemoryReviewStore implements ReviewStore {
  private reviews = new Map<string, ReviewRecord>();
  private publicTokenLookup = new Map<string, string>();
  private reviewPublicTokens = new Map<string, string>();
  private versions = new Map<string, ReviewVersion[]>();
  private comments = new Map<string, ReviewComment[]>();
  private forks = new Map<string, StoredFork[]>();

  async createReview(input: CreateReviewInput, publicBaseUrl: string): Promise<CreateReviewResult> {
    const reviewId = makeId("rvw");
    const publicReviewToken = makeToken();
    const publisherAccessToken = makeToken();
    const now = new Date().toISOString();
    const reviewUrl = `${publicBaseUrl.replace(/\/$/, "")}/r/${publicReviewToken}`;
    const review: ReviewRecord = {
      id: reviewId,
      status: "open",
      title: input.title,
      publicTokenHash: sha256(publicReviewToken),
      publisherTokenHash: sha256(publisherAccessToken),
      publisherId: makeId("pub"),
      keychainAccount: `clearly-review-${reviewId}`,
      reviewUrl,
      targetFile: input.targetFile,
      targetRelativePath: input.targetRelativePath,
      vaultId: input.vaultId,
      latestVersion: 1,
      createdAt: now,
      updatedAt: now,
    };
    const version: ReviewVersion = {
      reviewId,
      version: 1,
      snapshotHtml: input.snapshotHtml,
      markdownSource: input.markdownSource,
      sourceMapJson: input.sourceMapJson,
      contentHash: input.contentHash,
      anchorNormalizerVersion: input.anchorNormalizerVersion,
      createdAt: now,
    };

    this.reviews.set(reviewId, review);
    this.publicTokenLookup.set(publicReviewToken, reviewId);
    this.reviewPublicTokens.set(reviewId, publicReviewToken);
    this.versions.set(reviewId, [version]);
    this.comments.set(reviewId, []);
    this.forks.set(reviewId, []);
    await this.logEvent(reviewId, "publisher", review.publisherId, "review.created", { version: 1 });
    return { review, version, publicReviewToken, publisherAccessToken };
  }

  async getReview(reviewId: string): Promise<ReviewRecord | undefined> {
    return this.reviews.get(reviewId);
  }

  async getReviewByPublicToken(publicToken: string): Promise<ReviewRecord | undefined> {
    const reviewId = this.publicTokenLookup.get(publicToken);
    if (reviewId) {
      const review = this.reviews.get(reviewId);
      return review?.status === "open" ? review : undefined;
    }
    for (const review of this.reviews.values()) {
      if (review.status === "open" && tokenMatches(publicToken, review.publicTokenHash)) return review;
    }
    return undefined;
  }

  async verifyPublisher(reviewId: string, token: string, adminTokenHash?: string): Promise<boolean> {
    const review = this.reviews.get(reviewId);
    if (!review) return false;
    return tokenMatches(token, review.publisherTokenHash) || (adminTokenHash ? tokenMatches(token, adminTokenHash) : false);
  }

  async revokeReview(reviewId: string, reason: string | undefined, actorId: string | undefined): Promise<ReviewRecord | undefined> {
    const review = this.reviews.get(reviewId);
    if (!review || review.status !== "open") return review;
    review.status = "revoked";
    review.revokedAt = new Date().toISOString();
    review.updatedAt = review.revokedAt;
    await this.logEvent(reviewId, "publisher", actorId, "review.revoked", { reason: reason ?? "" });
    return review;
  }

  async rotatePublicToken(reviewId: string, publicBaseUrl: string, reason: string | undefined, actorId: string | undefined): Promise<{ review: ReviewRecord; publicReviewToken: string } | undefined> {
    const review = this.reviews.get(reviewId);
    if (!review || review.status !== "open") return undefined;
    const oldToken = this.reviewPublicTokens.get(reviewId);
    if (oldToken) this.publicTokenLookup.delete(oldToken);
    const publicReviewToken = makeToken();
    review.publicTokenHash = sha256(publicReviewToken);
    review.reviewUrl = `${publicBaseUrl.replace(/\/$/, "")}/r/${publicReviewToken}`;
    review.updatedAt = new Date().toISOString();
    this.publicTokenLookup.set(publicReviewToken, reviewId);
    this.reviewPublicTokens.set(reviewId, publicReviewToken);
    await this.logEvent(reviewId, "publisher", actorId, "link.rotated", { reason: reason ?? "" });
    return { review, publicReviewToken };
  }

  async addVersion(reviewId: string, input: CreateVersionInput): Promise<ReviewVersion> {
    const review = required(this.reviews.get(reviewId), "review");
    const list = this.versions.get(reviewId) ?? [];
    const version: ReviewVersion = {
      reviewId,
      version: list.length + 1,
      snapshotHtml: input.snapshotHtml,
      markdownSource: input.markdownSource,
      sourceMapJson: input.sourceMapJson,
      contentHash: input.contentHash,
      anchorNormalizerVersion: input.anchorNormalizerVersion,
      createdAt: new Date().toISOString(),
    };
    list.push(version);
    this.versions.set(reviewId, list);
    review.latestVersion = version.version;
    review.updatedAt = version.createdAt;
    await this.logEvent(reviewId, "publisher", review.publisherId, "version.published", { version: version.version });
    return version;
  }

  async getVersion(reviewId: string, version: number): Promise<ReviewVersion | undefined> {
    return this.versions.get(reviewId)?.find((item) => item.version === version);
  }

  async getLatestVersion(reviewId: string): Promise<ReviewVersion | undefined> {
    const list = this.versions.get(reviewId) ?? [];
    return list.at(-1);
  }

  async listVersions(reviewId: string, cursor: string | undefined, limit: number): Promise<Page<ReviewVersion>> {
    return paginate(this.versions.get(reviewId) ?? [], cursor, limit);
  }

  async listComments(reviewId: string, cursor: string | undefined, limit: number, status?: string): Promise<Page<ReviewComment>> {
    const comments = (this.comments.get(reviewId) ?? [])
      .filter((comment) => comment.status !== "deleted")
      .filter((comment) => !status || comment.status === status);
    return paginate(comments, cursor, limit);
  }

  async createComment(reviewId: string, input: CreateCommentInput): Promise<ReviewComment> {
    const now = new Date().toISOString();
    const comment: ReviewComment = {
      id: makeId("cmt"),
      commentId: "",
      reviewId,
      version: input.version,
      parentCommentId: input.parentCommentId,
      status: "open",
      author: input.authorDisplayName,
      authorDisplayName: input.authorDisplayName,
      authorId: input.authorId,
      body: input.body,
      selectedText: input.selectedText,
      suggestedReplacement: input.suggestedReplacement,
      suggestionMode: input.suggestionMode,
      anchor: input.anchor,
      currentAnchor: input.anchor,
      anchorConfidence: anchorConfidence(input.anchor),
      anchorRemapReason: "authored_anchor",
      anchorRemappedVersion: input.version,
      orphaned: anchorConfidence(input.anchor) === "orphan",
      remoteRevision: 1,
      createdAt: now,
      updatedAt: now,
    };
    comment.commentId = comment.id;
    const list = this.comments.get(reviewId) ?? [];
    list.push(comment);
    this.comments.set(reviewId, list);
    await this.logEvent(reviewId, "reviewer", input.authorId, "comment.created", { commentId: comment.id });
    return comment;
  }

  async updateComment(reviewId: string, commentId: string, input: UpdateCommentInput): Promise<ReviewComment | "conflict" | undefined> {
    const comment = this.findComment(reviewId, commentId);
    if (!comment || comment.status === "deleted") return undefined;
    if (input.authorId !== comment.authorId) return undefined;
    if (comment.remoteRevision !== input.expectedRevision) return "conflict";
    if (input.body !== undefined) comment.body = input.body;
    if (input.suggestedReplacement !== undefined) comment.suggestedReplacement = input.suggestedReplacement;
    if (input.suggestionMode !== undefined) comment.suggestionMode = input.suggestionMode;
    comment.remoteRevision += 1;
    comment.updatedAt = new Date().toISOString();
    await this.logEvent(reviewId, "reviewer", comment.authorId, "comment.edited", { commentId });
    return comment;
  }

  async updateCommentRemap(reviewId: string, commentId: string, input: CommentRemapInput): Promise<ReviewComment | undefined> {
    const comment = this.findComment(reviewId, commentId);
    if (!comment || comment.status === "deleted") return undefined;
    comment.currentAnchor = input.anchor;
    comment.anchorConfidence = input.confidence;
    comment.anchorRemapReason = input.reason;
    comment.anchorRemappedVersion = input.remappedVersion;
    comment.orphaned = input.confidence === "orphan";
    comment.updatedAt = new Date().toISOString();
    return comment;
  }

  async closeComment(reviewId: string, commentId: string, expectedRevision: number, closedBy: string, note = ""): Promise<ReviewComment | "conflict" | undefined> {
    const comment = this.findComment(reviewId, commentId);
    if (!comment || comment.status === "deleted") return undefined;
    if (comment.remoteRevision !== expectedRevision) return "conflict";
    comment.status = "closed";
    comment.resolvedBy = closedBy;
    comment.resolvedAt = new Date().toISOString();
    comment.resolutionNote = note;
    comment.remoteRevision += 1;
    comment.updatedAt = comment.resolvedAt;
    await this.logEvent(reviewId, "publisher", closedBy, "comment.closed", { commentId, note });
    return comment;
  }

  async deleteComment(reviewId: string, commentId: string, authorId: string, expectedRevision?: number): Promise<ReviewComment | "conflict" | undefined> {
    const comment = this.findComment(reviewId, commentId);
    if (!comment || comment.status === "deleted" || comment.authorId !== authorId) return undefined;
    if (expectedRevision !== undefined && comment.remoteRevision !== expectedRevision) return "conflict";
    comment.status = "deleted";
    comment.remoteRevision += 1;
    comment.updatedAt = new Date().toISOString();
    await this.logEvent(reviewId, "reviewer", authorId, "comment.deleted", { commentId });
    return comment;
  }

  async deleteCommentAsPublisher(reviewId: string, commentId: string, expectedRevision: number, deletedBy: string): Promise<ReviewComment | "conflict" | undefined> {
    const comment = this.findComment(reviewId, commentId);
    if (!comment || comment.status === "deleted") return undefined;
    if (comment.remoteRevision !== expectedRevision) return "conflict";
    comment.status = "deleted";
    comment.remoteRevision += 1;
    comment.updatedAt = new Date().toISOString();
    await this.logEvent(reviewId, "publisher", deletedBy, "comment.deleted", { commentId });
    return comment;
  }

  async resolveComment(reviewId: string, commentId: string, expectedRevision: number, resolvedBy: string, note = ""): Promise<ReviewComment | "conflict" | undefined> {
    const comment = this.findComment(reviewId, commentId);
    if (!comment || comment.status === "deleted") return undefined;
    if (comment.remoteRevision !== expectedRevision) return "conflict";
    comment.status = "resolved";
    comment.resolvedBy = resolvedBy;
    comment.resolvedAt = new Date().toISOString();
    comment.resolutionNote = note;
    comment.remoteRevision += 1;
    comment.updatedAt = comment.resolvedAt;
    await this.logEvent(reviewId, "publisher", resolvedBy, "agent.resolution_confirmed", { commentId });
    return comment;
  }

  async reopenComment(reviewId: string, commentId: string, expectedRevision: number, authorId: string): Promise<ReviewComment | "conflict" | undefined> {
    const comment = this.findComment(reviewId, commentId);
    if (!comment || comment.status === "deleted" || comment.authorId !== authorId) return undefined;
    if (comment.remoteRevision !== expectedRevision) return "conflict";
    comment.status = "open";
    comment.resolvedBy = undefined;
    comment.resolvedAt = undefined;
    comment.resolutionNote = undefined;
    comment.remoteRevision += 1;
    comment.updatedAt = new Date().toISOString();
    await this.logEvent(reviewId, "reviewer", authorId, "comment.reopened", { commentId });
    return comment;
  }

  async createFork(reviewId: string, input: CreateForkInput): Promise<ReviewForkDetail | undefined> {
    const base = await this.getVersion(reviewId, input.version);
    if (!base) return undefined;
    const diff = lineDiff(input.version, base.markdownSource, input.markdownSource);
    const now = new Date().toISOString();
    const fork: StoredFork = {
      forkId: makeId("frk"),
      reviewId,
      version: input.version,
      authorId: input.authorId,
      authorDisplayName: input.authorDisplayName,
      markdownSource: input.markdownSource,
      diff,
      diffSummary: diffSummary(diff),
      createdAt: now,
    };
    const list = this.forks.get(reviewId) ?? [];
    list.push(fork);
    this.forks.set(reviewId, list);
    await this.logEvent(reviewId, "reviewer", input.authorId, "fork.submitted", { forkId: fork.forkId });
    return fork;
  }

  async listForks(reviewId: string, cursor: string | undefined, limit: number): Promise<Page<ReviewForkSummary>> {
    const page = paginate(this.forks.get(reviewId) ?? [], cursor, limit);
    return {
      items: page.items.map(({ forkId, version, authorDisplayName, createdAt, diffSummary }) => ({
        forkId,
        version,
        authorDisplayName,
        createdAt,
        diffSummary,
      })),
      nextCursor: page.nextCursor,
    };
  }

  async getFork(reviewId: string, forkId: string): Promise<ReviewForkDetail | undefined> {
    return this.forks.get(reviewId)?.find((fork) => fork.forkId === forkId);
  }

  async logEvent(_reviewId: string, _actorType: string, _actorId: string | undefined, _eventType: string, _payload?: unknown): Promise<void> {
    return;
  }

  private findComment(reviewId: string, commentId: string): ReviewComment | undefined {
    return this.comments.get(reviewId)?.find((comment) => comment.id === commentId);
  }
}

export function clampLimit(raw: unknown, fallback = 50, max = 250): number {
  const parsed = Number(raw ?? fallback);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(1, Math.min(Math.trunc(parsed), max));
}

function paginate<T extends { createdAt: string; id?: string; forkId?: string; version?: number }>(
  items: T[],
  cursor: string | undefined,
  limit: number
): Page<T> {
  const cursorValue = decodeCursor(cursor);
  const sorted = [...items].sort((lhs, rhs) => {
    if (lhs.createdAt !== rhs.createdAt) return lhs.createdAt < rhs.createdAt ? -1 : 1;
    return itemId(lhs).localeCompare(itemId(rhs));
  });
  const start = cursorValue
    ? sorted.findIndex((item) => item.createdAt > cursorValue.createdAt || (item.createdAt === cursorValue.createdAt && itemId(item) > cursorValue.id))
    : 0;
  const pageStart = start < 0 ? sorted.length : start;
  const pageItems = sorted.slice(pageStart, pageStart + limit);
  const last = pageItems.at(-1);
  return {
    items: pageItems,
    nextCursor: pageItems.length === limit && last ? encodeCursor({ createdAt: last.createdAt, id: itemId(last) }) : undefined,
  };
}

function itemId(item: { id?: string; forkId?: string; version?: number }): string {
  return item.id ?? item.forkId ?? String(item.version ?? "");
}

function required<T>(value: T | undefined, label: string): T {
  if (value === undefined) throw new Error(`missing ${label}`);
  return value;
}

function anchorConfidence(anchor: unknown): "exact" | "fuzzy" | "section" | "orphan" {
  if (typeof anchor === "object" && anchor !== null) {
    const value = (anchor as { confidence?: unknown }).confidence;
    if (value === "fuzzy" || value === "section" || value === "orphan") return value;
  }
  return "exact";
}
