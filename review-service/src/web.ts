import { escapeHtml, noIndexHeaders } from "./html.js";
import type { ReviewRecord, ReviewVersion } from "./types.js";

export function renderReviewPage(review: ReviewRecord, latestVersion: ReviewVersion, token: string): string {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex,nofollow">
  <title>${escapeHtml(review.title)} - Clearly Review</title>
  <style>
    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    * { box-sizing: border-box; }
    body { margin: 0; background: Canvas; color: CanvasText; }
    .shell { display: grid; grid-template-columns: minmax(0, 1fr) 360px; height: 100vh; }
    .doc { border: 0; width: 100%; height: 100%; background: white; }
    aside { border-left: 1px solid color-mix(in srgb, CanvasText 18%, transparent); overflow: auto; }
    header, .panel, .composer { padding: 14px 16px; border-bottom: 1px solid color-mix(in srgb, CanvasText 14%, transparent); }
    h1 { font-size: 15px; line-height: 1.3; margin: 0 0 4px; }
    .meta { color: color-mix(in srgb, CanvasText 62%, transparent); font-size: 12px; }
    label { display: block; font-size: 12px; color: color-mix(in srgb, CanvasText 66%, transparent); margin: 10px 0 5px; }
    input, textarea { width: 100%; border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); border-radius: 6px; padding: 8px; font: inherit; background: Canvas; color: CanvasText; }
    textarea { min-height: 86px; resize: vertical; }
    button { border: 1px solid color-mix(in srgb, CanvasText 20%, transparent); border-radius: 6px; padding: 7px 10px; font: inherit; background: ButtonFace; color: ButtonText; cursor: pointer; }
    button.primary { background: #2357d8; border-color: #2357d8; color: white; }
    button:disabled { opacity: .5; cursor: default; }
    .row { display: flex; gap: 8px; align-items: center; }
    .row > * { flex: 1; }
    .selected { font-size: 12px; padding: 8px; background: color-mix(in srgb, CanvasText 7%, transparent); border-radius: 6px; max-height: 90px; overflow: auto; white-space: pre-wrap; }
    .comment { padding: 12px 16px; border-bottom: 1px solid color-mix(in srgb, CanvasText 10%, transparent); }
    .comment strong { font-size: 13px; }
    .comment p { margin: 8px 0 0; white-space: pre-wrap; }
    .comment-actions { display: flex; gap: 6px; margin-top: 8px; }
    .comment-actions button { font-size: 12px; padding: 4px 7px; }
    .pill { display: inline-block; border-radius: 999px; padding: 2px 7px; font-size: 11px; background: color-mix(in srgb, CanvasText 8%, transparent); margin-left: 6px; }
    .empty { padding: 18px 16px; color: color-mix(in srgb, CanvasText 60%, transparent); }
    .fork-panel { padding: 14px 16px; border-bottom: 1px solid color-mix(in srgb, CanvasText 14%, transparent); }
    .fork-panel[hidden] { display: none; }
    .fork-panel textarea { min-height: 240px; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 13px; }
    @media (max-width: 820px) {
      .shell { grid-template-columns: 1fr; grid-template-rows: minmax(45vh, 1fr) auto; height: auto; min-height: 100vh; }
      aside { border-left: 0; border-top: 1px solid color-mix(in srgb, CanvasText 18%, transparent); max-height: none; }
      .doc { height: 55vh; }
    }
  </style>
</head>
<body>
  <main class="shell" data-token="${escapeHtml(token)}" data-version="${latestVersion.version}">
    <iframe class="doc" id="snapshot" title="Review snapshot" sandbox="allow-same-origin" src="/r/${encodeURIComponent(token)}/snapshot/${latestVersion.version}"></iframe>
    <aside>
      <header>
        <h1>${escapeHtml(review.title)}</h1>
        <div class="meta">Version ${latestVersion.version} · ${escapeHtml(new Date(latestVersion.createdAt).toLocaleString())}</div>
      </header>
      <form class="composer" id="comment-form">
        <div class="row">
          <button type="button" id="capture">Use Selection</button>
          <button class="primary" type="submit">Post Comment</button>
        </div>
        <label for="display-name">Name</label>
        <input id="display-name" maxlength="80" autocomplete="name">
        <label>Selection</label>
        <div class="selected" id="selected">Select text in the document, then use the selection.</div>
        <label for="body">Comment</label>
        <textarea id="body" maxlength="10000" required></textarea>
        <label for="suggested-replacement">Suggested replacement</label>
        <textarea id="suggested-replacement" maxlength="50000"></textarea>
      </form>
      <section class="fork-panel">
        <div class="row">
          <button type="button" id="load-fork">Fork Markdown</button>
          <button class="primary" type="button" id="submit-fork" disabled>Submit Fork</button>
        </div>
      </section>
      <section class="fork-panel" id="fork-editor" hidden>
        <label for="fork-markdown">Markdown fork</label>
        <textarea id="fork-markdown" spellcheck="false"></textarea>
      </section>
      <section id="comments"></section>
    </aside>
  </main>
  <script>
    const root = document.querySelector(".shell");
    const token = root.dataset.token;
    let latestVersion = Number(root.dataset.version);
    let selectedText = "";
    let selectedAnchor = null;
    const guestIdKey = "clearlyReviewGuestId";
    const guestNameKey = "clearlyReviewDisplayName";
    const guestId = localStorage.getItem(guestIdKey) || "gst_" + crypto.randomUUID().replaceAll("-", "").slice(0, 16);
    localStorage.setItem(guestIdKey, guestId);
    const nameInput = document.getElementById("display-name");
    nameInput.value = localStorage.getItem(guestNameKey) || "";

    document.getElementById("capture").addEventListener("click", captureSelection);
    document.getElementById("comment-form").addEventListener("submit", postComment);
    document.getElementById("load-fork").addEventListener("click", loadForkMarkdown);
    document.getElementById("submit-fork").addEventListener("click", submitFork);
    nameInput.addEventListener("change", () => localStorage.setItem(guestNameKey, nameInput.value.trim()));
    loadComments();

    function captureSelection() {
      const frame = document.getElementById("snapshot");
      const selection = frame.contentWindow.getSelection();
      selectedText = String(selection || "").trim();
      const range = selection && selection.rangeCount ? selection.getRangeAt(0) : null;
      const node = range ? (range.commonAncestorContainer.nodeType === 1 ? range.commonAncestorContainer : range.commonAncestorContainer.parentElement) : null;
      const block = node && node.closest ? node.closest("[data-sourcepos],p,li,blockquote,pre,td,th,h1,h2,h3,h4,h5,h6") : null;
      const blockText = block ? block.textContent || "" : "";
      const offset = selectedText && blockText ? Math.max(0, blockText.indexOf(selectedText)) : null;
      selectedAnchor = {
        blockType: blockTypeFor(block),
        sourcepos: block ? block.getAttribute("data-sourcepos") || "" : "",
        charOffsetInBlock: offset,
        charLength: selectedText.length || null,
        selectedText: selectedText || null,
        prefix: selectedText && offset !== null ? blockText.slice(Math.max(0, offset - 48), offset) : null,
        suffix: selectedText && offset !== null ? blockText.slice(offset + selectedText.length, offset + selectedText.length + 48) : null,
        confidence: selectedText ? "exact" : "section",
        anchorNormalizerVersion: 1
      };
      document.getElementById("selected").textContent = selectedText || "No text selected; comment will attach to the current document.";
    }

    function blockTypeFor(block) {
      if (!block) return "paragraph";
      const tag = block.tagName.toLowerCase();
      if (/^h[1-6]$/.test(tag)) return "heading";
      if (tag === "li") return "listItem";
      if (tag === "blockquote") return "quote";
      if (tag === "pre" || tag === "code") return "code";
      if (tag === "td" || tag === "th") return "table";
      return "paragraph";
    }

    async function postComment(event) {
      event.preventDefault();
      const displayName = nameInput.value.trim() || "Reviewer";
      localStorage.setItem(guestNameKey, displayName);
      const body = document.getElementById("body").value.trim();
      if (!body) return;
      if (!selectedAnchor) captureSelection();
      const suggestedReplacement = document.getElementById("suggested-replacement").value;
      const response = await fetch("/r/" + encodeURIComponent(token) + "/comments", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          version: latestVersion,
          author: { authorId: guestId, displayName },
          body,
          selectedText,
          suggestedReplacement,
          suggestionMode: suggestedReplacement.trim() ? "advisory" : "advisory",
          anchor: selectedAnchor || { blockType: "paragraph", sourcepos: "", confidence: "section", anchorNormalizerVersion: 1 }
        })
      });
      if (!response.ok) {
        alert(await response.text());
        return;
      }
      document.getElementById("body").value = "";
      document.getElementById("suggested-replacement").value = "";
      selectedText = "";
      selectedAnchor = null;
      document.getElementById("selected").textContent = "Select text in the document, then use the selection.";
      await loadComments();
    }

    async function loadComments() {
      const payload = await fetchReviewJSON();
      latestVersion = payload.review.latestVersion;
      root.dataset.reviewId = payload.review.reviewId;
      const container = document.getElementById("comments");
      const comments = payload.comments || [];
      if (!comments.length) {
        container.innerHTML = '<div class="empty">No comments yet.</div>';
        return;
      }
      container.innerHTML = comments.map(comment => '<article class="comment" data-comment-id="' + escapeText(comment.id || comment.commentId) + '"><strong>' +
        escapeText(comment.authorDisplayName || comment.author || "Reviewer") + '</strong><span class="pill">' +
        escapeText(comment.status) + '</span><span class="pill">' +
        escapeText(comment.anchorConfidence || (comment.currentAnchor && comment.currentAnchor.confidence) || (comment.anchor && comment.anchor.confidence) || "exact") + '</span><p>' + escapeText(comment.body) + '</p>' +
        (comment.selectedText ? '<div class="selected">' + escapeText(comment.selectedText) + '</div>' : '') +
        (comment.suggestedReplacement ? '<div class="selected">' + escapeText(comment.suggestedReplacement) + '</div>' : '') +
        actionsFor(comment) +
        '</article>').join("");
      container.querySelectorAll("[data-edit-comment]").forEach(button => button.addEventListener("click", () => editComment(button.dataset.editComment)));
      container.querySelectorAll("[data-reopen-comment]").forEach(button => button.addEventListener("click", () => reopenComment(button.dataset.reopenComment)));
    }

    function actionsFor(comment) {
      const id = comment.id || comment.commentId;
      const owns = comment.authorId === guestId;
      if (!owns) return "";
      const buttons = [];
      if (comment.status === "open") {
        buttons.push('<button type="button" data-edit-comment="' + escapeText(id) + '">Edit</button>');
      }
      if (comment.status === "resolved") {
        buttons.push('<button type="button" data-reopen-comment="' + escapeText(id) + '">Reopen</button>');
      }
      return buttons.length ? '<div class="comment-actions">' + buttons.join("") + '</div>' : "";
    }

    async function editComment(commentId) {
      const payload = await fetchReviewJSON();
      const comment = (payload.comments || []).find(item => (item.id || item.commentId) === commentId);
      if (!comment) return;
      const body = prompt("Edit comment", comment.body || "");
      if (body === null || !body.trim()) return;
      const response = await fetch("/api/reviews/" + encodeURIComponent(payload.review.reviewId) + "/comments/" + encodeURIComponent(commentId), {
        method: "PATCH",
        headers: { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
        body: JSON.stringify({
          expectedRevision: comment.remoteRevision,
          authorId: guestId,
          body
        })
      });
      if (!response.ok) {
        alert(await response.text());
        return;
      }
      await loadComments();
    }

    async function reopenComment(commentId) {
      const payload = await fetchReviewJSON();
      const comment = (payload.comments || []).find(item => (item.id || item.commentId) === commentId);
      if (!comment) return;
      const response = await fetch("/api/reviews/" + encodeURIComponent(payload.review.reviewId) + "/comments/" + encodeURIComponent(commentId) + "/reopen", {
        method: "POST",
        headers: { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
        body: JSON.stringify({
          expectedRevision: comment.remoteRevision,
          authorId: guestId
        })
      });
      if (!response.ok) {
        alert(await response.text());
        return;
      }
      await loadComments();
    }

    async function fetchReviewJSON() {
      const comments = [];
      let review = null;
      let cursor = null;
      do {
        const url = "/r/" + encodeURIComponent(token) + "/review.json?limit=250" + (cursor ? "&cursor=" + encodeURIComponent(cursor) : "");
        const page = await fetch(url).then(r => r.json());
        review = page.review;
        comments.push(...(page.comments || []));
        cursor = page.nextCursor || null;
      } while (cursor);
      return { review, comments };
    }

    async function loadForkMarkdown() {
      const signed = await fetch("/r/" + encodeURIComponent(token) + "/source-url/" + latestVersion);
      if (!signed.ok) {
        alert(await signed.text());
        return;
      }
      const signedPayload = await signed.json();
      const response = await fetch(signedPayload.markdownUrl);
      if (!response.ok) {
        alert(await response.text());
        return;
      }
      document.getElementById("fork-markdown").value = await response.text();
      document.getElementById("fork-editor").hidden = false;
      document.getElementById("submit-fork").disabled = false;
    }

    async function submitFork() {
      const displayName = nameInput.value.trim() || "Reviewer";
      localStorage.setItem(guestNameKey, displayName);
      const markdown = document.getElementById("fork-markdown").value;
      const response = await fetch("/r/" + encodeURIComponent(token) + "/forks", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          version: latestVersion,
          author: { authorId: guestId, displayName },
          markdown
        })
      });
      if (!response.ok) {
        alert(await response.text());
        return;
      }
      document.getElementById("fork-editor").hidden = true;
      document.getElementById("submit-fork").disabled = true;
      alert("Fork submitted.");
    }

    function escapeText(value) {
      return String(value || "").replace(/[&<>"']/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));
    }
  </script>
</body>
</html>`;
}

export function snapshotHeaders() {
  return {
    ...noIndexHeaders(),
    "Content-Type": "text/html; charset=utf-8",
    "Content-Security-Policy": "default-src 'none'; img-src https: data:; style-src 'unsafe-inline'; font-src data:; frame-ancestors 'self'",
  };
}
