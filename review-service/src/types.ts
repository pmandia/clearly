export type ActorKind = "publisher" | "reviewer";
export type ReviewAnchorConfidence = "exact" | "fuzzy" | "section" | "orphan";

export interface AuthContext {
  kind: ActorKind;
  token: string;
  reviewId?: string;
}

export interface ReviewRecord {
  id: string;
  status: "open" | "revoked" | "deleted";
  title: string;
  publicTokenHash: string;
  publisherTokenHash: string;
  publisherId: string;
  keychainAccount: string;
  reviewUrl: string;
  targetFile?: string;
  targetRelativePath?: string;
  vaultId?: string;
  latestVersion: number;
  revokedAt?: string;
  createdAt: string;
  updatedAt: string;
}

export interface ReviewVersion {
  reviewId: string;
  version: number;
  snapshotHtml: string;
  markdownSource: string;
  sourceMapJson: unknown;
  contentHash: string;
  anchorNormalizerVersion: number;
  createdAt: string;
}

export interface ReviewComment {
  id: string;
  commentId: string;
  reviewId: string;
  version: number;
  parentCommentId?: string;
  status: string;
  author: string;
  authorDisplayName: string;
  authorId: string;
  body: string;
  selectedText?: string;
  suggestedReplacement?: string;
  suggestionMode: string;
  anchor: unknown;
  currentAnchor: unknown;
  anchorConfidence: ReviewAnchorConfidence;
  anchorRemapReason?: string;
  anchorRemappedVersion?: number;
  orphaned: boolean;
  remoteRevision: number;
  createdAt: string;
  updatedAt: string;
  resolvedBy?: string;
  resolvedAt?: string;
  resolutionNote?: string;
}

export interface ReviewForkSummary {
  forkId: string;
  version: number;
  authorDisplayName: string;
  createdAt: string;
  diffSummary: ReviewForkDiffSummary;
}

export interface ReviewForkDetail extends ReviewForkSummary {
  reviewId: string;
  authorId: string;
  markdownSource: string;
  markdownUrl?: string;
  markdownUrlExpiresAt?: string;
  diff: ReviewForkDiff;
}

export interface ReviewForkDiffSummary {
  additions: number;
  deletions: number;
  changedSections: string[];
}

export interface ReviewForkDiff {
  schemaVersion: 1;
  baseVersion: number;
  algorithm: "normalized-line-diff-v1";
  hunks: Array<{
    oldStart: number;
    oldLines: number;
    newStart: number;
    newLines: number;
    lines: Array<{ type: "context" | "add" | "delete"; text: string }>;
  }>;
}

export interface CreateReviewInput {
  title: string;
  targetFile?: string;
  targetRelativePath?: string;
  vaultId?: string;
  snapshotHtml: string;
  markdownSource: string;
  sourceMapJson: unknown;
  contentHash: string;
  anchorNormalizerVersion: number;
}

export interface CreateReviewResult {
  review: ReviewRecord;
  version: ReviewVersion;
  publicReviewToken: string;
  publisherAccessToken: string;
}

export interface CreateVersionInput {
  snapshotHtml: string;
  markdownSource: string;
  sourceMapJson: unknown;
  contentHash: string;
  anchorNormalizerVersion: number;
}

export interface CreateCommentInput {
  version: number;
  parentCommentId?: string;
  authorId: string;
  authorDisplayName: string;
  body: string;
  selectedText?: string;
  suggestedReplacement?: string;
  suggestionMode: string;
  anchor: unknown;
}

export interface UpdateCommentInput {
  authorId: string;
  expectedRevision: number;
  body?: string;
  suggestedReplacement?: string;
  suggestionMode?: string;
}

export interface CommentRemapInput {
  anchor: unknown;
  confidence: ReviewAnchorConfidence;
  reason: string;
  remappedVersion: number;
}

export interface ReviewRemappedComment {
  commentId: string;
  confidence: ReviewAnchorConfidence;
  reason: string;
  anchor: unknown;
  remappedVersion: number;
}

export interface CreateForkInput {
  version: number;
  authorId: string;
  authorDisplayName: string;
  markdownSource: string;
}

export interface Page<T> {
  items: T[];
  nextCursor?: string;
}
