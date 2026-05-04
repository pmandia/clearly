import assert from "node:assert/strict";
import test from "node:test";
import { loadConfig } from "../src/config.js";
import { sanitizeUploadedSnapshotHtml } from "../src/html.js";
import { remapComment } from "../src/remapper.js";
import { buildServer } from "../src/server.js";
import { MemoryReviewStore } from "../src/store.js";

const config = {
  port: 0,
  publicBaseUrl: "https://reviews.example.test",
  publisherToken: "admin-token",
  publisherTokenHash: "unused",
  signedUrlSecret: "signed-url-secret",
};

test("requires a distinct signed URL secret at config load", () => {
  assert.throws(() => loadConfig({
    PORT: "0",
    PUBLIC_BASE_URL: "https://reviews.example.test",
    CLEARLY_REVIEW_PUBLISHER_TOKEN: "admin-token",
  }), /CLEARLY_REVIEW_SIGNED_URL_SECRET/);

  const loaded = loadConfig({
    PORT: "0",
    PUBLIC_BASE_URL: "https://reviews.example.test",
    CLEARLY_REVIEW_PUBLISHER_TOKEN: "admin-token",
    CLEARLY_REVIEW_SIGNED_URL_SECRET: "signed-url-secret",
  });
  assert.equal(loaded.signedUrlSecret, "signed-url-secret");
});

test("creates a review, accepts public comments, and lets publisher resolve them", async () => {
  const app = buildServer(new MemoryReviewStore(), config);
  await app.ready();
  tAfter(() => app.close());

  const created = await createReview(app);
  assert.equal(created.version, 1);
  assert.match(created.reviewUrl, /^https:\/\/reviews\.example\.test\/r\//);
  assert.ok(created.accessToken);

  const page = await app.inject({ method: "GET", url: `/r/${created.publicReviewToken}` });
  assert.equal(page.statusCode, 200);
  assert.match(page.body, /Clearly Review/);

  const snapshot = await app.inject({ method: "GET", url: `/r/${created.publicReviewToken}/snapshot/1` });
  assert.equal(snapshot.statusCode, 200, snapshot.body);
  assert.match(snapshot.body, /<style>/);
  assert.match(snapshot.body, /main \{ max-width: 820px/);
  assert.doesNotMatch(snapshot.body, /<script/i);
  assert.doesNotMatch(snapshot.body, /onclick=/i);

  const commentResponse = await app.inject({
    method: "POST",
    url: `/r/${created.publicReviewToken}/comments`,
    headers: { "content-type": "application/json" },
    payload: {
      version: 1,
      author: { authorId: "gst_1", displayName: "Jane" },
      body: "This section needs a clearer launch date.",
      selectedText: "launch date",
      anchor: paragraphAnchor("launch date"),
    },
  });
  assert.equal(commentResponse.statusCode, 201, commentResponse.body);
  const comment = commentResponse.json().comment;
  assert.equal(comment.remoteRevision, 1);

  const missingAuthorPatch = await app.inject({
    method: "PATCH",
    url: `/api/reviews/${created.reviewId}/comments/${comment.id}`,
    headers: { authorization: `Bearer ${created.publicReviewToken}`, "content-type": "application/json" },
    payload: {
      expectedRevision: 1,
      body: "Hijacked.",
    },
  });
  assert.equal(missingAuthorPatch.statusCode, 400, missingAuthorPatch.body);

  const wrongAuthorPatch = await app.inject({
    method: "PATCH",
    url: `/api/reviews/${created.reviewId}/comments/${comment.id}`,
    headers: { authorization: `Bearer ${created.publicReviewToken}`, "content-type": "application/json" },
    payload: {
      expectedRevision: 1,
      authorId: "gst_other",
      body: "Hijacked.",
    },
  });
  assert.equal(wrongAuthorPatch.statusCode, 403, wrongAuthorPatch.body);

  const deleteResponse = await app.inject({
    method: "DELETE",
    url: `/api/reviews/${created.reviewId}/comments/${comment.id}`,
    headers: { authorization: `Bearer ${created.publicReviewToken}`, "content-type": "application/json" },
    payload: { authorId: "gst_1" },
  });
  assert.equal(deleteResponse.statusCode, 404);

  const commentsResponse = await app.inject({
    method: "GET",
    url: `/api/reviews/${created.reviewId}/comments`,
    headers: { authorization: `Bearer ${created.accessToken}` },
  });
  assert.equal(commentsResponse.statusCode, 200, commentsResponse.body);
  assert.equal(commentsResponse.json().comments.length, 1);

  const resolved = await app.inject({
    method: "POST",
    url: `/api/reviews/${created.reviewId}/comments/${comment.id}/resolve`,
    headers: { authorization: `Bearer ${created.accessToken}`, "content-type": "application/json" },
    payload: {
      expectedRevision: 1,
      resolvedBy: "publisher",
      resolutionNote: "Edited locally.",
    },
  });
  assert.equal(resolved.statusCode, 200, resolved.body);
  assert.equal(resolved.json().status, "resolved");
  assert.equal(resolved.json().remoteRevision, 2);

  const staleResolve = await app.inject({
    method: "POST",
    url: `/api/reviews/${created.reviewId}/comments/${comment.id}/resolve`,
    headers: { authorization: `Bearer ${created.accessToken}`, "content-type": "application/json" },
    payload: {
      expectedRevision: 1,
      resolvedBy: "publisher",
    },
  });
  assert.equal(staleResolve.statusCode, 409);
});

test("snapshot sanitizer preserves only the exact trusted wrapper style", () => {
  const trusted = sanitizeUploadedSnapshotHtml(reviewSnapshotHtml("<p onclick=\"x()\">Safe text</p><svg><g onload=\"x()\"></g></svg><a href=\"javascript:alert(1)\">bad</a>"));
  assert.match(trusted, /<style>/);
  assert.match(trusted, /main \{ max-width: 820px/);
  assert.doesNotMatch(trusted, /onclick=/i);
  assert.doesNotMatch(trusted, /onload=/i);
  assert.doesNotMatch(trusted, /<svg/i);
  assert.doesNotMatch(trusted, /javascript:/i);

  const malicious = sanitizeUploadedSnapshotHtml(`<!doctype html><main data-review-snapshot-version="1">Text</main>
    <style>/* main { max-width: 820px [data-sourcepos] mark[data-review-highlight] */ body { color: red; }</style>`);
  assert.doesNotMatch(malicious, /body \{ color: red/i);
  assert.doesNotMatch(malicious, /<style>/i);
});

test("service remapper uses CJK character ngrams for fuzzy matches", () => {
  const result = remapComment({
    id: "cjk_1",
    commentId: "cjk_1",
    reviewId: "rvw_test",
    version: 1,
    status: "open",
    author: "Jane",
    authorDisplayName: "Jane",
    authorId: "gst_1",
    body: "Clarify this.",
    selectedText: "重要な計画を確認する",
    suggestionMode: "advisory",
    anchor: {
      blockType: "paragraph",
      sourcepos: "1:1-1:20",
      headingId: "plan",
      selectedText: "重要な計画を確認する",
      prefix: "これは",
      suffix: "してください",
      confidence: "exact",
      anchorNormalizerVersion: 1,
    },
    currentAnchor: {},
    anchorConfidence: "exact",
    orphaned: false,
    remoteRevision: 1,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  }, sourceMap([
    paragraphBlock("2:1-2:40", "これは重要な計画を確認しました。してください", "sha256:cjk", "plan"),
  ]), 2);

  assert.equal(result.confidence, "fuzzy");
  assert.equal((result.anchor as Record<string, unknown>).sourcepos, "2:1-2:40");
});

test("comments are cursor paginated deterministically", async () => {
  const app = buildServer(new MemoryReviewStore(), config);
  await app.ready();
  tAfter(() => app.close());

  const created = await createReview(app);
  for (let index = 0; index < 3; index += 1) {
    const response = await app.inject({
      method: "POST",
      url: `/r/${created.publicReviewToken}/comments`,
      headers: { "content-type": "application/json" },
      payload: {
        version: 1,
        author: { authorId: `gst_${index}`, displayName: `Reviewer ${index}` },
        body: `Comment ${index}`,
        anchor: paragraphAnchor(`Comment ${index}`),
      },
    });
    assert.equal(response.statusCode, 201, response.body);
  }

  const first = await app.inject({
    method: "GET",
    url: `/api/reviews/${created.reviewId}/comments?limit=2`,
    headers: { authorization: `Bearer ${created.accessToken}` },
  });
  assert.equal(first.statusCode, 200, first.body);
  assert.equal(first.json().comments.length, 2);
  assert.ok(first.json().nextCursor);

  const second = await app.inject({
    method: "GET",
    url: `/api/reviews/${created.reviewId}/comments?limit=2&cursor=${encodeURIComponent(first.json().nextCursor)}`,
    headers: { authorization: `Bearer ${created.accessToken}` },
  });
  assert.equal(second.statusCode, 200, second.body);
  assert.equal(second.json().comments.length, 1);
});

test("publishes a new version and reports remap confidence", async () => {
  const app = buildServer(new MemoryReviewStore(), config);
  await app.ready();
  tAfter(() => app.close());

  const created = await createReview(app);
  const commentResponse = await app.inject({
    method: "POST",
    url: `/r/${created.publicReviewToken}/comments`,
    headers: { "content-type": "application/json" },
    payload: {
      version: 1,
      author: { authorId: "gst_1", displayName: "Jane" },
      body: "Keep this sentence.",
      selectedText: "important sentence",
      anchor: paragraphAnchor("important sentence"),
    },
  });
  assert.equal(commentResponse.statusCode, 201, commentResponse.body);

  const body = multipartBody(
    {
      contentHash: "hash-v2",
      anchorNormalizerVersion: "1",
    },
    {
      snapshotHtml: "<main><p data-sourcepos=\"1:1-1:20\">An important sentence remains.</p></main>",
      markdownSource: "An important sentence remains.\n",
      sourceMapJson: JSON.stringify(sourceMap([
        paragraphBlock("1:1-1:40", "An important sentence remains.", "sha256:v2"),
      ])),
    }
  );
  const published = await app.inject({
    method: "POST",
    url: `/api/reviews/${created.reviewId}/versions`,
    headers: {
      authorization: `Bearer ${created.accessToken}`,
      "content-type": `multipart/form-data; boundary=${body.boundary}`,
    },
    payload: body.payload,
  });
  assert.equal(published.statusCode, 200, published.body);
  assert.equal(published.json().version, 2);
  assert.equal(published.json().remappedComments[0].confidence, "exact");
  assert.equal(published.json().remappedComments[0].reason, "selected_text_exact_match");

  const synced = await app.inject({
    method: "GET",
    url: `/api/reviews/${created.reviewId}/comments`,
    headers: { authorization: `Bearer ${created.accessToken}` },
  });
  assert.equal(synced.statusCode, 200, synced.body);
  assert.equal(synced.json().comments[0].anchorConfidence, "exact");
  assert.equal(synced.json().comments[0].currentAnchor.sourcepos, "1:1-1:40");
});

test("remaps moved comments fuzzily and keeps deleted comments visible as orphaned", async () => {
  const app = buildServer(new MemoryReviewStore(), config);
  await app.ready();
  tAfter(() => app.close());

  const created = await createReview(app);
  const fuzzyComment = await app.inject({
    method: "POST",
    url: `/r/${created.publicReviewToken}/comments`,
    headers: { "content-type": "application/json" },
    payload: {
      version: 1,
      author: { authorId: "gst_1", displayName: "Jane" },
      body: "This should stay attached after rewrite.",
      selectedText: "important sentence for launch plan remains here",
      anchor: {
        ...paragraphAnchor("important sentence for launch plan remains here"),
        prefix: "",
        suffix: ".",
      },
    },
  });
  assert.equal(fuzzyComment.statusCode, 201, fuzzyComment.body);

  const orphanComment = await app.inject({
    method: "POST",
    url: `/r/${created.publicReviewToken}/comments`,
    headers: { "content-type": "application/json" },
    payload: {
      version: 1,
      author: { authorId: "gst_2", displayName: "Sam" },
      body: "This deleted text should become orphaned.",
      selectedText: "deleted claim",
      anchor: {
        ...paragraphAnchor("deleted claim"),
        sourcepos: "3:1-3:20",
        prefix: "Remove",
        suffix: "now",
      },
    },
  });
  assert.equal(orphanComment.statusCode, 201, orphanComment.body);

  const body = multipartBody(
    {
      contentHash: "hash-v2",
      anchorNormalizerVersion: "1",
    },
    {
      snapshotHtml: "<main><h2 data-sourcepos=\"1:1-1:10\" id=\"plan\">Plan</h2><p data-sourcepos=\"2:1-2:80\">A very important sentence for the launch plan remains here.</p></main>",
      markdownSource: "## Plan\n\nA very important sentence for the launch plan remains here.\n",
      sourceMapJson: JSON.stringify(sourceMap([
        headingBlock("1:1-1:10", "Plan", "plan"),
        paragraphBlock("2:1-2:80", "A very important sentence for the launch plan remains here.", "sha256:fuzzy", "plan"),
      ])),
    }
  );
  const published = await app.inject({
    method: "POST",
    url: `/api/reviews/${created.reviewId}/versions`,
    headers: {
      authorization: `Bearer ${created.accessToken}`,
      "content-type": `multipart/form-data; boundary=${body.boundary}`,
    },
    payload: body.payload,
  });
  assert.equal(published.statusCode, 200, published.body);
  const remaps = published.json().remappedComments;
  assert.equal(remaps.length, 2);
  assert.equal(remaps.find((item: { confidence: string }) => item.confidence === "orphan").confidence, "orphan");
  assert.ok(remaps.some((item: { confidence: string }) => item.confidence === "fuzzy" || item.confidence === "section"));
});

test("supports reviewer forks plus publisher token rotation and revocation", async () => {
  const app = buildServer(new MemoryReviewStore(), config);
  await app.ready();
  tAfter(() => app.close());

  const created = await createReview(app);
  const directSource = await app.inject({
    method: "GET",
    url: `/r/${created.publicReviewToken}/source/1`,
  });
  assert.equal(directSource.statusCode, 404);

  const sourceUrl = await app.inject({
    method: "GET",
    url: `/r/${created.publicReviewToken}/source-url/1`,
  });
  assert.equal(sourceUrl.statusCode, 200, sourceUrl.body);
  assert.match(sourceUrl.json().markdownUrl, /\/signed\/markdown\?/);

  const source = await app.inject({
    method: "GET",
    url: signedPath(sourceUrl.json().markdownUrl),
  });
  assert.equal(source.statusCode, 200, source.body);
  assert.match(source.body, /An important sentence/);

  const tamperedSignature = new URL(sourceUrl.json().markdownUrl);
  tamperedSignature.searchParams.set("signature", "0".repeat(64));
  const badSignature = await app.inject({
    method: "GET",
    url: signedPath(tamperedSignature.toString()),
  });
  assert.equal(badSignature.statusCode, 403, badSignature.body);

  const tamperedExpires = new URL(sourceUrl.json().markdownUrl);
  tamperedExpires.searchParams.set("expires", String(Math.floor(Date.now() / 1000) + 3600));
  const badExpires = await app.inject({
    method: "GET",
    url: signedPath(tamperedExpires.toString()),
  });
  assert.equal(badExpires.statusCode, 403, badExpires.body);

  const expired = new URL(sourceUrl.json().markdownUrl);
  expired.searchParams.set("expires", "1");
  const expiredResponse = await app.inject({
    method: "GET",
    url: signedPath(expired.toString()),
  });
  assert.equal(expiredResponse.statusCode, 403, expiredResponse.body);
  assert.equal(expiredResponse.json().error.code, "signed_url_expired");

  const forkResponse = await app.inject({
    method: "POST",
    url: `/r/${created.publicReviewToken}/forks`,
    headers: { "content-type": "application/json" },
    payload: {
      version: 1,
      author: { authorId: "gst_fork", displayName: "Forker" },
      markdown: "An important sentence.\n\nA forked addition.\n",
    },
  });
  assert.equal(forkResponse.statusCode, 201, forkResponse.body);
  const forkId = forkResponse.json().fork.forkId;

  const forkDetail = await app.inject({
    method: "GET",
    url: `/api/reviews/${created.reviewId}/forks/${forkId}`,
    headers: { authorization: `Bearer ${created.accessToken}` },
  });
  assert.equal(forkDetail.statusCode, 200, forkDetail.body);
  assert.equal(forkDetail.json().markdownSource, undefined);
  assert.match(forkDetail.json().markdownUrl, /\/signed\/markdown\?/);
  assert.equal(forkDetail.json().diff.algorithm, "normalized-line-diff-v1");

  const forkMarkdown = await app.inject({
    method: "GET",
    url: signedPath(forkDetail.json().markdownUrl),
  });
  assert.equal(forkMarkdown.statusCode, 200, forkMarkdown.body);
  assert.match(forkMarkdown.body, /forked addition/);

  const directForkMarkdown = await app.inject({
    method: "GET",
    url: `/api/reviews/${created.reviewId}/forks/${forkId}/markdown`,
    headers: { authorization: `Bearer ${created.accessToken}` },
  });
  assert.equal(directForkMarkdown.statusCode, 404);

  const rotated = await app.inject({
    method: "POST",
    url: `/api/reviews/${created.reviewId}/rotate-token`,
    headers: { authorization: `Bearer ${created.accessToken}`, "content-type": "application/json" },
    payload: { reason: "test" },
  });
  assert.equal(rotated.statusCode, 200, rotated.body);
  assert.notEqual(rotated.json().publicReviewToken, created.publicReviewToken);

  const oldLink = await app.inject({ method: "GET", url: `/r/${created.publicReviewToken}` });
  assert.equal(oldLink.statusCode, 404);
  const newLink = await app.inject({ method: "GET", url: `/r/${rotated.json().publicReviewToken}` });
  assert.equal(newLink.statusCode, 200, newLink.body);

  const revoked = await app.inject({
    method: "POST",
    url: `/api/reviews/${created.reviewId}/revoke`,
    headers: { authorization: `Bearer ${created.accessToken}`, "content-type": "application/json" },
    payload: { reason: "done" },
  });
  assert.equal(revoked.statusCode, 200, revoked.body);
  const revokedLink = await app.inject({ method: "GET", url: `/r/${rotated.json().publicReviewToken}` });
  assert.equal(revokedLink.statusCode, 404);
});

async function createReview(app: ReturnType<typeof buildServer>) {
  const body = multipartBody(
    {
      title: "Proposal",
      targetRelativePath: "proposal.md",
      vaultId: "vlt_test",
      contentHash: "hash-v1",
      anchorNormalizerVersion: "1",
    },
    {
      snapshotHtml: reviewSnapshotHtml("<p data-sourcepos=\"1:1-1:24\" onclick=\"bad()\">An important sentence.</p><script>alert('x')</script>"),
      markdownSource: "An important sentence.\n",
      sourceMapJson: JSON.stringify(sourceMap([
        paragraphBlock("1:1-1:24", "An important sentence.", "sha256:v1"),
        paragraphBlock("3:1-3:20", "Remove deleted claim now.", "sha256:deleted"),
      ])),
    }
  );
  const response = await app.inject({
    method: "POST",
    url: "/api/reviews",
    headers: {
      authorization: "Bearer admin-token",
      "content-type": `multipart/form-data; boundary=${body.boundary}`,
    },
    payload: body.payload,
  });
  assert.equal(response.statusCode, 201, response.body);
  return response.json() as {
    reviewId: string;
    reviewUrl: string;
    publicReviewToken: string;
    accessToken: string;
    version: number;
  };
}

function reviewSnapshotHtml(body: string) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="robots" content="noindex,nofollow">
<title>Proposal</title>
<style>
:root { color-scheme: light dark; }
body { margin: 0; font: 16px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: CanvasText; background: Canvas; }
main { max-width: 820px; margin: 0 auto; padding: 32px 20px 56px; }
pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
pre { overflow: auto; padding: 12px; border: 1px solid color-mix(in srgb, CanvasText 16%, transparent); border-radius: 6px; }
img { max-width: 100%; height: auto; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); padding: 6px 8px; }
[data-sourcepos] { scroll-margin-top: 16px; }
mark[data-review-highlight] { background: #ffe58a; color: inherit; }
</style>
</head>
<body>
<main data-review-snapshot-version="1">
${body}
</main>
</body>
</html>`;
}

function signedPath(url: string): string {
  return new URL(url).pathname + new URL(url).search;
}

function paragraphAnchor(selectedText: string) {
  return {
    blockType: "paragraph",
    sourcepos: "1:1-1:24",
    charOffsetInBlock: 3,
    charLength: selectedText.length,
    selectedText,
    prefix: "An ",
    suffix: ".",
    confidence: "exact",
    anchorNormalizerVersion: 1,
  };
}

function sourceMap(blocks: Array<Record<string, unknown>>) {
  return {
    schemaVersion: 1,
    anchorNormalizerVersion: 1,
    blocks,
    headings: [
      {
        headingId: "plan",
        sourcepos: "1:1-1:10",
        title: "Plan",
        level: 2,
        parentHeadingId: null,
      },
    ],
  };
}

function paragraphBlock(sourcepos: string, normalizedText: string, textHash: string, headingId?: string) {
  return {
    blockId: sourcepos,
    sourcepos,
    headingId,
    blockType: "paragraph",
    textHash,
    normalizedText,
    charLength: normalizedText.length,
  };
}

function headingBlock(sourcepos: string, normalizedText: string, headingId: string) {
  return {
    blockId: sourcepos,
    sourcepos,
    headingId,
    blockType: "heading",
    textHash: "sha256:heading",
    normalizedText,
    charLength: normalizedText.length,
  };
}

function multipartBody(fields: Record<string, string>, files: Record<string, string>) {
  const boundary = `test-${Math.random().toString(16).slice(2)}`;
  const chunks: Buffer[] = [];
  for (const [name, value] of Object.entries(fields)) {
    chunks.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n${value}\r\n`));
  }
  for (const [name, value] of Object.entries(files)) {
    chunks.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${name}"; filename="${name}"\r\nContent-Type: application/octet-stream\r\n\r\n${value}\r\n`));
  }
  chunks.push(Buffer.from(`--${boundary}--\r\n`));
  return { boundary, payload: Buffer.concat(chunks) };
}

function tAfter(fn: () => unknown | Promise<unknown>) {
  test.after(fn);
}
