import multipart from "@fastify/multipart";
import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import { sanitizeUploadedSnapshotHtml } from "./html.js";
import { renderReviewPage, snapshotHeaders } from "./web.js";
import { clampLimit, type ReviewStore } from "./store.js";
import { remapComment } from "./remapper.js";
import { hexMatches, hmacSha256 } from "./crypto.js";
import type { ServiceConfig } from "./config.js";
import type { CreateCommentInput, CreateForkInput, CreateReviewInput, CreateVersionInput, ReviewComment } from "./types.js";

const SNAPSHOT_HTML_LIMIT = 5_000_000;
const MARKDOWN_LIMIT = 2_000_000;
const COMMENT_BODY_LIMIT = 10_000;
const SUGGESTED_REPLACEMENT_LIMIT = 50_000;
const FORK_MARKDOWN_LIMIT = 1_000_000;
const SIGNED_MARKDOWN_URL_TTL_SECONDS = 5 * 60;

export function buildServer(store: ReviewStore, config: ServiceConfig): FastifyInstance {
  const app = Fastify({ logger: true });
  app.register(multipart, {
    limits: {
      fileSize: SNAPSHOT_HTML_LIMIT,
      files: 3,
      fields: 16,
    },
  });

  const commentPostLimiter = createMemoryRateLimiter(30, 60_000);
  const apiReadLimiter = createMemoryRateLimiter(120, 60_000);
  const snapshotGetLimiter = createMemoryRateLimiter(300, 60_000);
  const commentMutationLimiter = createMemoryRateLimiter(60, 60_000);
  const forkReviewerLimiter = createMemoryRateLimiter(5, 60 * 60_000);
  const forkReviewLimiter = createMemoryRateLimiter(20, 24 * 60 * 60_000);

  app.get("/healthz", async () => ({ ok: true }));

  app.post("/api/reviews", async (request, reply) => {
    requirePublisherAdmin(request, config);
    const input = await readReviewMultipart(request, true);
    const result = await store.createReview(input, config.publicBaseUrl);
    return reply.code(201).send({
      reviewId: result.review.id,
      reviewUrl: result.review.reviewUrl,
      publicReviewToken: result.publicReviewToken,
      accessToken: result.publisherAccessToken,
      keychainAccount: result.review.keychainAccount,
      publisherId: result.review.publisherId,
      version: result.version.version,
      snapshotUrl: `${config.publicBaseUrl.replace(/\/$/, "")}/r/${result.publicReviewToken}/snapshot/${result.version.version}`,
      createdAt: result.review.createdAt,
    });
  });

  app.get("/api/reviews/:reviewId", async (request, reply) => {
    requireRateLimit(apiReadLimiter, request.ip, "Too many API reads. Try again in a minute.");
    const review = await requireReview(request, store);
    await requireReviewAuth(request, store, config, review.id);
    return {
      reviewId: review.id,
      title: review.title,
      status: review.status,
      reviewUrl: review.reviewUrl,
      latestVersion: review.latestVersion,
      createdAt: review.createdAt,
      updatedAt: review.updatedAt,
      permissions: { canComment: true, canFork: true, canResolveOwn: true, canResolveAny: true },
    };
  });

  app.get("/api/reviews/:reviewId/versions", async (request, reply) => {
    requireRateLimit(apiReadLimiter, request.ip, "Too many API reads. Try again in a minute.");
    const review = await requireReview(request, store);
    await requireReviewAuth(request, store, config, review.id);
    const query = request.query as Record<string, unknown>;
    const page = await store.listVersions(review.id, stringParam(query.cursor), clampLimit(query.limit));
    return {
      reviewId: review.id,
      versions: page.items.map((version) => ({
        version: version.version,
        contentHash: version.contentHash,
        anchorNormalizerVersion: version.anchorNormalizerVersion,
        createdAt: version.createdAt,
      })),
      nextCursor: page.nextCursor,
    };
  });

  app.post("/api/reviews/:reviewId/versions", async (request, reply) => {
    const review = await requireReview(request, store);
    await requirePublisherForReview(request, store, config, review.id);
    const input = await readReviewMultipart(request, false);
    const version = await store.addVersion(review.id, input);
    const remappedComments = await remapCommentsForVersion(store, review.id, version.version, version.sourceMapJson);
    return {
      reviewId: review.id,
      version: version.version,
      snapshotUrl: `${config.publicBaseUrl.replace(/\/$/, "")}/api/reviews/${review.id}/versions/${version.version}/snapshot`,
      createdAt: version.createdAt,
      remappedComments,
    };
  });

  app.get("/api/reviews/:reviewId/versions/:version/snapshot", async (request, reply) => {
    requireRateLimit(snapshotGetLimiter, request.ip, "Too many snapshot requests. Try again in a minute.");
    const review = await requireReview(request, store);
    await requireReviewAuth(request, store, config, review.id);
    const version = await store.getVersion(review.id, numberParam((request.params as Record<string, string>).version));
    if (!version) throw notFound("version_not_found", "Review version not found.");
    return reply.headers(snapshotHeaders()).send(sanitizeUploadedSnapshotHtml(version.snapshotHtml));
  });

  app.get("/api/reviews/:reviewId/comments", async (request, reply) => {
    requireRateLimit(apiReadLimiter, request.ip, "Too many API reads. Try again in a minute.");
    const review = await requireReview(request, store);
    await requireReviewAuth(request, store, config, review.id);
    const query = request.query as Record<string, unknown>;
    const page = await store.listComments(review.id, stringParam(query.cursor), clampLimit(query.limit), stringParam(query.status));
    return commentsPage(review.id, page.items, page.nextCursor);
  });

  app.post("/api/reviews/:reviewId/comments", async (request, reply) => {
    requireRateLimit(commentPostLimiter, request.ip, "Too many comments from this IP. Try again in a minute.");
    const review = await requireReview(request, store);
    await requireReviewAuth(request, store, config, review.id);
    const input = commentInput(request.body);
    const comment = await store.createComment(review.id, input);
    return reply.code(201).send({ comment });
  });

  app.patch("/api/reviews/:reviewId/comments/:commentId", async (request, reply) => {
    requireRateLimit(commentMutationLimiter, request.ip, "Too many comment updates. Try again in a minute.");
    const review = await requireReview(request, store);
    await requireReviewAuth(request, store, config, review.id);
    const body = objectBody(request.body);
    const author = objectBody(body.author);
    const authorId = requiredString(body.authorId ?? author.authorId, "authorId");
    const comment = await store.updateComment(review.id, (request.params as Record<string, string>).commentId, {
      authorId,
      expectedRevision: numberParam(body.expectedRevision),
      body: stringParam(body.body),
      suggestedReplacement: checkedString(body.suggestedReplacement, SUGGESTED_REPLACEMENT_LIMIT, "suggestedReplacement", true),
      suggestionMode: stringParam(body.suggestionMode),
    });
    if (comment === "conflict") throw httpError(409, "remote_revision_conflict", "Comment revision changed before edit.");
    if (!comment) throw httpError(403, "forbidden", "Only the original reviewer can edit this comment.");
    return { comment };
  });

  app.post("/api/reviews/:reviewId/comments/:commentId/resolve", async (request) => {
    requireRateLimit(commentMutationLimiter, request.ip, "Too many comment updates. Try again in a minute.");
    const params = request.params as Record<string, string>;
    const review = await store.getReview(params.reviewId);
    if (!review) throw notFound("review_not_found", "Review not found.");
    await requirePublisherForReview(request, store, config, review.id);
    const body = objectBody(request.body);
    const result = await store.resolveComment(
      review.id,
      params.commentId,
      numberParam(body.expectedRevision),
      requiredString(body.resolvedBy, "resolvedBy"),
      stringParam(body.resolutionNote) ?? ""
    );
    if (result === "conflict") throw httpError(409, "conflict", "Comment revision changed before resolution.");
    if (!result) throw notFound("comment_not_found", "Comment not found.");
    return resolvePayload(result);
  });

  app.post("/api/reviews/:reviewId/comments/:commentId/close", async (request) => {
    requireRateLimit(commentMutationLimiter, request.ip, "Too many comment updates. Try again in a minute.");
    const params = request.params as Record<string, string>;
    const review = await store.getReview(params.reviewId);
    if (!review) throw notFound("review_not_found", "Review not found.");
    await requirePublisherForReview(request, store, config, review.id);
    const body = objectBody(request.body);
    const result = await store.closeComment(
      review.id,
      params.commentId,
      numberParam(body.expectedRevision),
      requiredString(body.closedBy ?? body.resolvedBy ?? "publisher", "closedBy"),
      stringParam(body.resolutionNote) ?? ""
    );
    if (result === "conflict") throw httpError(409, "conflict", "Comment revision changed before close.");
    if (!result) throw notFound("comment_not_found", "Comment not found.");
    return resolvePayload(result);
  });

  app.delete("/api/reviews/:reviewId/comments/:commentId", async (request) => {
    requireRateLimit(commentMutationLimiter, request.ip, "Too many comment updates. Try again in a minute.");
    const params = request.params as Record<string, string>;
    const review = await store.getReview(params.reviewId);
    if (!review) throw notFound("review_not_found", "Review not found.");
    await requirePublisherForReview(request, store, config, review.id);
    const body = objectBody(request.body);
    const result = await store.deleteCommentAsPublisher(
      review.id,
      params.commentId,
      numberParam(body.expectedRevision),
      requiredString(body.deletedBy ?? "publisher", "deletedBy")
    );
    if (result === "conflict") throw httpError(409, "conflict", "Comment revision changed before delete.");
    if (!result) throw notFound("comment_not_found", "Comment not found.");
    return deletePayload(result);
  });

  app.post("/api/reviews/:reviewId/comments/:commentId/reopen", async (request) => {
    requireRateLimit(commentMutationLimiter, request.ip, "Too many comment updates. Try again in a minute.");
    const params = request.params as Record<string, string>;
    const review = await store.getReview(params.reviewId);
    if (!review) throw notFound("review_not_found", "Review not found.");
    await requireReviewAuth(request, store, config, review.id);
    const body = objectBody(request.body);
    const result = await store.reopenComment(
      review.id,
      params.commentId,
      numberParam(body.expectedRevision),
      requiredString(body.authorId, "authorId")
    );
    if (result === "conflict") throw httpError(409, "conflict", "Comment revision changed before reopen.");
    if (!result) throw httpError(403, "forbidden", "Only the original reviewer can reopen this comment.");
    return { comment: result };
  });

  app.post("/api/reviews/:reviewId/revoke", async (request) => {
    const review = await requireReview(request, store);
    await requirePublisherForReview(request, store, config, review.id);
    const body = objectBody(request.body);
    const revoked = await store.revokeReview(review.id, stringParam(body.reason), review.publisherId);
    if (!revoked) throw notFound("review_not_found", "Review not found.");
    return {
      reviewId: revoked.id,
      status: revoked.status,
      revokedAt: revoked.revokedAt,
    };
  });

  app.post("/api/reviews/:reviewId/rotate-token", async (request) => {
    const review = await requireReview(request, store);
    await requirePublisherForReview(request, store, config, review.id);
    const body = objectBody(request.body);
    const rotated = await store.rotatePublicToken(review.id, config.publicBaseUrl, stringParam(body.reason), review.publisherId);
    if (!rotated) throw notFound("review_not_found", "Review not found.");
    return {
      reviewId: rotated.review.id,
      reviewUrl: rotated.review.reviewUrl,
      publicReviewToken: rotated.publicReviewToken,
      rotatedAt: rotated.review.updatedAt,
    };
  });

  app.get("/api/reviews/:reviewId/forks", async (request, reply) => {
    requireRateLimit(apiReadLimiter, request.ip, "Too many API reads. Try again in a minute.");
    const review = await requireReview(request, store);
    await requireReviewAuth(request, store, config, review.id);
    const query = request.query as Record<string, unknown>;
    const page = await store.listForks(review.id, stringParam(query.cursor), clampLimit(query.limit));
    return { reviewId: review.id, forks: page.items, nextCursor: page.nextCursor };
  });

  app.get("/api/reviews/:reviewId/forks/:forkId", async (request, reply) => {
    requireRateLimit(apiReadLimiter, request.ip, "Too many API reads. Try again in a minute.");
    const review = await requireReview(request, store);
    await requireReviewAuth(request, store, config, review.id);
    const fork = await store.getFork(review.id, (request.params as Record<string, string>).forkId);
    if (!fork) throw notFound("fork_not_found", "Fork not found.");
    const signed = signedMarkdownURL(config, { kind: "fork", reviewId: review.id, forkId: fork.forkId });
    return { ...publicForkDetail(fork), markdownUrl: signed.url, markdownUrlExpiresAt: signed.expiresAt };
  });

  app.post("/api/reviews/:reviewId/forks", async (request, reply) => {
    const review = await requireReview(request, store);
    await requireReviewAuth(request, store, config, review.id);
    const input = forkInput(request.body);
    requireRateLimit(forkReviewerLimiter, `${request.ip}:${input.authorId}`, "Too many fork submissions from this reviewer. Try again later.");
    requireRateLimit(forkReviewLimiter, review.id, "This review has reached the daily fork submission limit. Try again later.");
    const fork = await store.createFork(review.id, input);
    if (!fork) throw notFound("version_not_found", "Base version not found.");
    return reply.code(201).send({ fork });
  });

  app.get("/r/:token", async (request, reply) => {
    const token = (request.params as Record<string, string>).token;
    const review = await store.getReviewByPublicToken(token);
    if (!review) throw notFound("review_not_found", "Review not found.");
    const latest = await store.getLatestVersion(review.id);
    if (!latest) throw notFound("version_not_found", "Review has no snapshots.");
    return reply
      .headers({ "X-Robots-Tag": "noindex, nofollow", "Content-Type": "text/html; charset=utf-8" })
      .send(renderReviewPage(review, latest, token));
  });

  app.get("/r/:token/review.json", async (request) => {
    const token = (request.params as Record<string, string>).token;
    const review = await store.getReviewByPublicToken(token);
    if (!review) throw notFound("review_not_found", "Review not found.");
    const query = request.query as Record<string, unknown>;
    const page = await store.listComments(review.id, stringParam(query.cursor), clampLimit(query.limit));
    return {
      review: {
        reviewId: review.id,
        title: review.title,
        latestVersion: review.latestVersion,
      },
      comments: page.items,
      nextCursor: page.nextCursor,
    };
  });

  app.get("/r/:token/snapshot/:version", async (request, reply) => {
    requireRateLimit(snapshotGetLimiter, request.ip, "Too many snapshot requests. Try again in a minute.");
    const params = request.params as Record<string, string>;
    const review = await store.getReviewByPublicToken(params.token);
    if (!review) throw notFound("review_not_found", "Review not found.");
    const version = await store.getVersion(review.id, numberParam(params.version));
    if (!version) throw notFound("version_not_found", "Review version not found.");
    return reply.headers(snapshotHeaders()).send(sanitizeUploadedSnapshotHtml(version.snapshotHtml));
  });

  app.get("/r/:token/source-url/:version", async (request) => {
    const params = request.params as Record<string, string>;
    const review = await store.getReviewByPublicToken(params.token);
    if (!review) throw notFound("review_not_found", "Review not found.");
    const version = await store.getVersion(review.id, numberParam(params.version));
    if (!version) throw notFound("version_not_found", "Review version not found.");
    const signed = signedMarkdownURL(config, { kind: "source", reviewId: review.id, version: version.version });
    return { markdownUrl: signed.url, markdownUrlExpiresAt: signed.expiresAt };
  });

  app.get("/signed/markdown", async (request, reply) => {
    const signed = verifiedSignedMarkdownParams(request, config);
    if (signed.kind === "source") {
      const version = await store.getVersion(signed.reviewId, signed.version);
      if (!version) throw notFound("version_not_found", "Review version not found.");
      return reply
        .header("Content-Type", "text/markdown; charset=utf-8")
        .header("X-Robots-Tag", "noindex, nofollow")
        .send(version.markdownSource);
    }

    const fork = await store.getFork(signed.reviewId, signed.forkId);
    if (!fork) throw notFound("fork_not_found", "Fork not found.");
    return reply
      .header("Content-Type", "text/markdown; charset=utf-8")
      .header("X-Robots-Tag", "noindex, nofollow")
      .send(fork.markdownSource);
  });

  app.post("/r/:token/comments", async (request, reply) => {
    requireRateLimit(commentPostLimiter, request.ip, "Too many comments from this IP. Try again in a minute.");
    const review = await store.getReviewByPublicToken((request.params as Record<string, string>).token);
    if (!review) throw notFound("review_not_found", "Review not found.");
    const input = commentInput(request.body);
    const comment = await store.createComment(review.id, input);
    return reply.code(201).send({ comment });
  });

  app.delete("/r/:token/comments/:commentId", async (request) => {
    requireRateLimit(commentMutationLimiter, request.ip, "Too many comment updates. Try again in a minute.");
    const params = request.params as Record<string, string>;
    const review = await store.getReviewByPublicToken(params.token);
    if (!review) throw notFound("review_not_found", "Review not found.");
    const body = objectBody(request.body);
    const result = await store.deleteComment(
      review.id,
      params.commentId,
      requiredString(body.authorId, "authorId"),
      body.expectedRevision === undefined ? undefined : numberParam(body.expectedRevision)
    );
    if (result === "conflict") throw httpError(409, "conflict", "Comment revision changed before delete.");
    if (!result) throw httpError(403, "forbidden", "Only the original reviewer can delete this comment.");
    return deletePayload(result);
  });

  app.post("/r/:token/forks", async (request, reply) => {
    const review = await store.getReviewByPublicToken((request.params as Record<string, string>).token);
    if (!review) throw notFound("review_not_found", "Review not found.");
    const input = forkInput(request.body);
    requireRateLimit(forkReviewerLimiter, `${request.ip}:${input.authorId}`, "Too many fork submissions from this reviewer. Try again later.");
    requireRateLimit(forkReviewLimiter, review.id, "This review has reached the daily fork submission limit. Try again later.");
    const fork = await store.createFork(review.id, input);
    if (!fork) throw notFound("version_not_found", "Base version not found.");
    return reply.code(201).send({ fork });
  });

  app.setErrorHandler((error: Error & Partial<HttpError>, _request, reply) => {
    const statusCode = error.statusCode ?? 500;
    const code = error.code ?? "service_error";
    const message = statusCode === 500 ? "Internal service error." : error.message;
    reply.code(statusCode).send({ error: { code, message }, message });
  });

  return app;
}

async function readReviewMultipart(request: FastifyRequest, includeTitle: boolean): Promise<CreateReviewInput> {
  if (!request.isMultipart()) throw httpError(400, "invalid_request", "Expected multipart/form-data.");
  const fields = new Map<string, string>();
  const files = new Map<string, Buffer>();
  for await (const part of request.parts()) {
    if (part.type === "file") {
      files.set(part.fieldname, await part.toBuffer());
    } else {
      fields.set(part.fieldname, String(part.value ?? ""));
    }
  }
  const markdownSource = requiredFile(files, "markdownSource", MARKDOWN_LIMIT).toString("utf8");
  const snapshotHtml = sanitizeUploadedSnapshotHtml(requiredFile(files, "snapshotHtml", SNAPSHOT_HTML_LIMIT).toString("utf8"));
  let sourceMapJson: unknown;
  try {
    sourceMapJson = JSON.parse(requiredFile(files, "sourceMapJson", 1_000_000).toString("utf8")) as unknown;
  } catch {
    throw httpError(400, "invalid_request", "sourceMapJson must be valid JSON.");
  }
  return {
    title: includeTitle ? requiredString(fields.get("title"), "title") : fields.get("title") ?? "Review",
    targetFile: fields.get("targetFile"),
    targetRelativePath: fields.get("targetRelativePath"),
    vaultId: fields.get("vaultId"),
    snapshotHtml,
    markdownSource,
    sourceMapJson,
    contentHash: requiredString(fields.get("contentHash"), "contentHash"),
    anchorNormalizerVersion: numberParam(fields.get("anchorNormalizerVersion") ?? 1),
  };
}

function commentInput(bodyValue: unknown): CreateCommentInput {
  const body = objectBody(bodyValue);
  const author = objectBody(body.author);
  const commentBody = checkedString(body.body, COMMENT_BODY_LIMIT, "body") ?? "";
  const suggestedReplacement = checkedString(body.suggestedReplacement, SUGGESTED_REPLACEMENT_LIMIT, "suggestedReplacement", true);
  return {
    version: numberParam(body.version),
    parentCommentId: stringParam(body.parentCommentId),
    authorId: requiredString(author.authorId ?? body.authorId, "author.authorId"),
    authorDisplayName: requiredString(author.displayName ?? author.authorDisplayName ?? body.authorDisplayName, "author.displayName"),
    body: commentBody,
    selectedText: stringParam(body.selectedText),
    suggestedReplacement,
    suggestionMode: stringParam(body.suggestionMode) ?? "advisory",
    anchor: body.anchor ?? { blockType: "paragraph", sourcepos: "", confidence: "section", anchorNormalizerVersion: 1 },
  };
}

function forkInput(bodyValue: unknown): CreateForkInput {
  const body = objectBody(bodyValue);
  const author = objectBody(body.author);
  return {
    version: numberParam(body.version),
    authorId: requiredString(author.authorId ?? body.authorId, "author.authorId"),
    authorDisplayName: requiredString(author.displayName ?? author.authorDisplayName ?? body.authorDisplayName, "author.displayName"),
    markdownSource: checkedString(body.markdownSource ?? body.markdown, FORK_MARKDOWN_LIMIT, "markdown") ?? "",
  };
}

function commentsPage(reviewId: string, comments: ReviewComment[], nextCursor: string | undefined) {
  const latest = comments.reduce((value, comment) => Math.max(value, comment.remoteRevision), 0);
  return {
    reviewId,
    revision: `${comments.length}:${latest}`,
    comments,
    nextCursor,
  };
}

function resolvePayload(comment: ReviewComment) {
  return {
    status: comment.status,
    resolvedBy: comment.resolvedBy ?? "",
    resolvedAt: comment.resolvedAt,
    resolutionNote: comment.resolutionNote,
    remoteRevision: comment.remoteRevision,
  };
}

function deletePayload(comment: ReviewComment) {
  return {
    deleted: true,
    status: comment.status,
    remoteRevision: comment.remoteRevision,
  };
}

function publicForkDetail(fork: Awaited<ReturnType<ReviewStore["getFork"]>>) {
  if (!fork) return fork;
  return {
    forkId: fork.forkId,
    reviewId: fork.reviewId,
    version: fork.version,
    authorId: fork.authorId,
    authorDisplayName: fork.authorDisplayName,
    createdAt: fork.createdAt,
    diffSummary: fork.diffSummary,
    diff: fork.diff,
  };
}

type SignedMarkdownRequest =
  | { kind: "source"; reviewId: string; version: number }
  | { kind: "fork"; reviewId: string; forkId: string };

function signedMarkdownURL(config: ServiceConfig, input: SignedMarkdownRequest): { url: string; expiresAt: string } {
  const secret = signedUrlSecret(config);
  const expires = Math.floor(Date.now() / 1000) + SIGNED_MARKDOWN_URL_TTL_SECONDS;
  const query = new URLSearchParams({
    kind: input.kind,
    reviewId: input.reviewId,
    expires: String(expires),
  });
  if (input.kind === "source") {
    query.set("version", String(input.version));
  } else {
    query.set("forkId", input.forkId);
  }
  query.set("signature", hmacSha256(signedMarkdownPayload(input, expires), secret));
  return {
    url: `${config.publicBaseUrl.replace(/\/$/, "")}/signed/markdown?${query.toString()}`,
    expiresAt: new Date(expires * 1000).toISOString(),
  };
}

function verifiedSignedMarkdownParams(request: FastifyRequest, config: ServiceConfig): SignedMarkdownRequest {
  const secret = signedUrlSecret(config);
  const query = request.query as Record<string, unknown>;
  const kind = requiredString(query.kind, "kind");
  const reviewId = requiredString(query.reviewId, "reviewId");
  const expires = numberParam(query.expires);
  const signature = requiredString(query.signature, "signature");
  if (expires < Math.floor(Date.now() / 1000)) {
    throw httpError(403, "signed_url_expired", "Signed Markdown URL has expired.");
  }
  const input: SignedMarkdownRequest =
    kind === "source"
      ? { kind, reviewId, version: numberParam(query.version) }
      : kind === "fork"
        ? { kind, reviewId, forkId: requiredString(query.forkId, "forkId") }
        : (() => {
            throw httpError(400, "invalid_request", "kind must be source or fork.");
          })();
  const expected = hmacSha256(signedMarkdownPayload(input, expires), secret);
  if (!hexMatches(signature, expected)) {
    throw httpError(403, "forbidden", "Signed Markdown URL is invalid.");
  }
  return input;
}

function signedMarkdownPayload(input: SignedMarkdownRequest, expires: number): string {
  return input.kind === "source"
    ? `source:${input.reviewId}:${input.version}:${expires}`
    : `fork:${input.reviewId}:${input.forkId}:${expires}`;
}

function signedUrlSecret(config: ServiceConfig): string {
  if (!config.signedUrlSecret) {
    throw httpError(503, "service_unavailable", "CLEARLY_REVIEW_SIGNED_URL_SECRET is not configured.");
  }
  return config.signedUrlSecret;
}

async function remapCommentsForVersion(store: ReviewStore, reviewId: string, remappedVersion: number, sourceMapJson: unknown) {
  const remapped = [];
  let cursor: string | undefined;
  do {
    const page = await store.listComments(reviewId, cursor, 250, "open");
    for (const comment of page.items) {
      const result = remapComment(comment, sourceMapJson, remappedVersion);
      await store.updateCommentRemap(reviewId, comment.id, {
        anchor: result.anchor,
        confidence: result.confidence,
        reason: result.reason,
        remappedVersion: result.remappedVersion,
      });
      remapped.push(result);
    }
    cursor = page.nextCursor;
  } while (cursor);
  return remapped;
}

async function requireReview(request: FastifyRequest, store: ReviewStore) {
  const reviewId = (request.params as Record<string, string>).reviewId;
  const review = await store.getReview(reviewId);
  if (!review) throw notFound("review_not_found", "Review not found.");
  return review;
}

async function requireReviewAuth(request: FastifyRequest, store: ReviewStore, config: ServiceConfig, reviewId: string): Promise<void> {
  const token = bearerToken(request);
  if (!token) throw httpError(401, "unauthenticated", "Missing bearer token.");
  const publicReview = await store.getReviewByPublicToken(token);
  if (publicReview?.id === reviewId) return;
  if (await store.verifyPublisher(reviewId, token, config.publisherTokenHash)) return;
  throw httpError(403, "forbidden", "Token does not grant access to this review.");
}

async function requirePublisherForReview(request: FastifyRequest, store: ReviewStore, config: ServiceConfig, reviewId: string): Promise<void> {
  const token = bearerToken(request);
  if (!token) throw httpError(401, "unauthenticated", "Missing publisher bearer token.");
  if (!(await store.verifyPublisher(reviewId, token, config.publisherTokenHash))) {
    throw httpError(403, "forbidden", "Publisher token does not grant access to this review.");
  }
}

function requirePublisherAdmin(request: FastifyRequest, config: ServiceConfig): void {
  if (!config.publisherToken) throw httpError(503, "service_unavailable", "CLEARLY_REVIEW_PUBLISHER_TOKEN is not configured.");
  if (bearerToken(request) !== config.publisherToken) {
    throw httpError(401, "unauthenticated", "Missing or invalid publisher bearer token.");
  }
}

function bearerToken(request: FastifyRequest): string | undefined {
  const value = request.headers.authorization;
  const match = typeof value === "string" ? /^Bearer\s+(.+)$/i.exec(value) : undefined;
  return match?.[1];
}

function requiredFile(files: Map<string, Buffer>, key: string, maxBytes: number): Buffer {
  const file = files.get(key);
  if (!file) throw httpError(400, "invalid_request", `Missing multipart file ${key}.`);
  if (file.byteLength > maxBytes) throw httpError(413, "payload_too_large", `${key} exceeds the size cap.`);
  return file;
}

function objectBody(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : {};
}

function checkedString(value: unknown, maxLength: number, name: string, optional = false): string | undefined {
  if (optional && (value === undefined || value === null || value === "")) return undefined;
  const text = requiredString(value, name);
  if (text.length > maxLength) throw httpError(413, "payload_too_large", `${name} exceeds the length cap.`);
  return text;
}

function requiredString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.trim() === "") throw httpError(400, "invalid_request", `${name} is required.`);
  return value;
}

function stringParam(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function numberParam(value: unknown): number {
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isInteger(parsed) || parsed < 0) throw httpError(400, "invalid_request", "Expected a non-negative integer.");
  return parsed;
}

function notFound(code: string, message: string): HttpError {
  return httpError(404, code, message);
}

function httpError(statusCode: number, code: string, message: string): HttpError {
  const error = new Error(message) as HttpError;
  error.statusCode = statusCode;
  error.code = code;
  return error;
}

function requireRateLimit(limiter: (key: string) => boolean, key: string, message: string): void {
  if (!limiter(key)) throw httpError(429, "rate_limited", message);
}

interface HttpError extends Error {
  statusCode?: number;
  code?: string;
}


function createMemoryRateLimiter(limit: number, windowMs: number) {
  const buckets = new Map<string, { count: number; resetAt: number }>();
  return (key: string): boolean => {
    const now = Date.now();
    const bucket = buckets.get(key);
    if (!bucket || bucket.resetAt <= now) {
      buckets.set(key, { count: 1, resetAt: now + windowMs });
      return true;
    }
    bucket.count += 1;
    return bucket.count <= limit;
  };
}
