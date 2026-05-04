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
    :root {
      color-scheme: light;
      --bg: #f6f6f4;
      --surface: #ffffff;
      --surface-muted: #f1f2f4;
      --border: #dedfdf;
      --border-strong: #c6c8ca;
      --text: #242628;
      --muted: #6f7377;
      --soft: #9a9da1;
      --accent: #245fd6;
      --accent-soft: #e7eefc;
      --warning-soft: #fff2cc;
      --warning-border: #f1cb55;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }

    * { box-sizing: border-box; }
    html, body { height: 100%; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      overflow: hidden;
    }

    button, input, textarea, summary { font: inherit; }
    button {
      border: 1px solid var(--border-strong);
      border-radius: 7px;
      padding: 7px 11px;
      background: var(--surface);
      color: var(--text);
      cursor: pointer;
    }
    button:hover:not(:disabled) { border-color: #aeb2b7; background: #fafafa; }
    button:disabled { opacity: 0.45; cursor: default; }
    button.primary {
      border-color: var(--accent);
      background: var(--accent);
      color: white;
      font-weight: 600;
    }
    button.subtle {
      border-color: transparent;
      background: transparent;
      color: var(--muted);
      padding-inline: 4px;
    }

    .shell {
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(380px, 420px);
      height: 100vh;
      min-width: 0;
    }

    .document-pane {
      position: relative;
      min-width: 0;
      background: #fafafa;
      border-right: 1px solid var(--border);
    }
    .doc {
      display: block;
      width: 100%;
      height: 100%;
      border: 0;
      background: white;
    }
    .selection-popover {
      position: fixed;
      z-index: 20;
      display: flex;
      align-items: center;
      gap: 6px;
      padding: 7px 10px;
      border: 1px solid #1d4fb8;
      border-radius: 999px;
      background: var(--accent);
      color: white;
      font-size: 13px;
      font-weight: 600;
      box-shadow: 0 12px 28px rgba(27, 32, 38, 0.22);
      transform: translate(-50%, -100%);
    }
    .selection-popover[hidden] { display: none; }

    .review-pane {
      display: flex;
      flex-direction: column;
      min-width: 0;
      height: 100vh;
      background: var(--surface);
    }
    .review-header {
      padding: 18px 24px 14px;
      border-bottom: 1px solid var(--border);
    }
    .eyebrow {
      color: var(--soft);
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.12em;
      text-transform: uppercase;
      margin-bottom: 8px;
    }
    h1 {
      margin: 0;
      font-size: 19px;
      line-height: 1.2;
      letter-spacing: 0;
    }
    .meta {
      margin-top: 6px;
      color: var(--muted);
      font-size: 13px;
    }

    .review-scroll {
      overflow: auto;
      padding: 0;
    }
    .card {
      border: 1px solid var(--border);
      border-radius: 8px;
      background: var(--surface);
    }
    .composer-card {
      padding: 18px 24px 20px;
      border-bottom: 1px solid var(--border);
    }
    .composer-title {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      gap: 12px;
      margin-bottom: 12px;
    }
    .composer-title h2, .section-title h2 {
      margin: 0;
      font-size: 14px;
      line-height: 1.25;
    }
    .composer-title span {
      color: var(--muted);
      font-size: 12px;
      white-space: nowrap;
    }
    label {
      display: block;
      margin: 12px 0 6px;
      color: var(--muted);
      font-size: 12px;
      font-weight: 600;
    }
    input, textarea {
      width: 100%;
      border: 1px solid var(--border-strong);
      border-radius: 7px;
      padding: 9px 10px;
      background: var(--surface);
      color: var(--text);
    }
    textarea {
      min-height: 92px;
      resize: vertical;
      line-height: 1.35;
    }
    .name-row {
      display: grid;
      grid-template-columns: 1fr;
      gap: 8px;
    }
    .selection-box {
      border: 1px solid var(--border);
      border-radius: 7px;
      background: #fafafa;
      padding: 9px 10px;
      min-height: 44px;
      color: var(--muted);
      font-size: 13px;
      line-height: 1.35;
    }
    .selection-box.has-selection {
      background: var(--warning-soft);
      border-color: var(--warning-border);
      color: #3c3320;
    }
    .selection-box blockquote {
      margin: 0;
      padding-left: 10px;
      border-left: 3px solid var(--warning-border);
      white-space: pre-wrap;
    }
    .composer-error {
      min-height: 18px;
      margin-top: 8px;
      color: #b42318;
      font-size: 12px;
    }
    .composer-actions {
      display: flex;
      align-items: center;
      justify-content: flex-end;
      gap: 8px;
      margin-top: 12px;
    }
    details.suggestion {
      margin-top: 10px;
    }
    details.suggestion summary {
      color: var(--muted);
      font-size: 12px;
      cursor: pointer;
      user-select: none;
    }
    details.suggestion textarea {
      margin-top: 8px;
      min-height: 86px;
    }

    .section {
      padding: 18px 24px;
    }
    .section-title {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 12px;
      margin-bottom: 10px;
    }
    .count {
      color: var(--muted);
      font-size: 12px;
      font-weight: 500;
    }
    .comments {
      display: grid;
      gap: 10px;
    }
    .empty {
      border: 1px dashed var(--border-strong);
      border-radius: 8px;
      padding: 18px;
      color: var(--muted);
      background: #fbfbfb;
      font-size: 14px;
    }
    .comment {
      padding: 13px 14px;
      cursor: pointer;
      transition: border-color 140ms ease, background 140ms ease, box-shadow 140ms ease;
    }
    .comment:hover {
      border-color: #b7c0cf;
      background: #fcfdff;
    }
    .comment.is-focused {
      border-color: var(--accent);
      box-shadow: 0 0 0 3px var(--accent-soft);
    }
    .comment-meta {
      display: flex;
      align-items: center;
      gap: 8px;
      color: var(--muted);
      font-size: 12px;
      margin-bottom: 8px;
    }
    .comment-meta strong {
      color: var(--text);
      font-size: 13px;
    }
    .pill {
      border-radius: 999px;
      padding: 2px 7px;
      background: var(--surface-muted);
      color: var(--muted);
      font-size: 11px;
    }
    .quote {
      margin: 0 0 9px;
      padding: 8px 10px;
      border-left: 3px solid var(--warning-border);
      border-radius: 5px;
      background: var(--warning-soft);
      color: #3c3320;
      font-size: 12px;
      line-height: 1.35;
      white-space: pre-wrap;
      max-height: 110px;
      overflow: auto;
    }
    .comment-body {
      margin: 0;
      white-space: pre-wrap;
      line-height: 1.4;
      font-size: 14px;
    }
    .replacement {
      margin-top: 10px;
      padding: 9px 10px;
      border-radius: 6px;
      background: #eef7f0;
      color: #243b2a;
      font-size: 12px;
      white-space: pre-wrap;
    }
    .comment-actions {
      display: flex;
      gap: 6px;
      margin-top: 10px;
    }
    .comment-actions button {
      padding: 4px 8px;
      font-size: 12px;
    }

    .fork-card {
      margin: 0 24px 24px;
      padding: 0;
    }
    .fork-card summary {
      padding: 13px 14px;
      color: var(--muted);
      cursor: pointer;
      user-select: none;
    }
    .fork-body {
      border-top: 1px solid var(--border);
      padding: 14px;
    }
    .fork-body textarea {
      min-height: 220px;
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 12px;
    }
    .fork-actions {
      display: flex;
      justify-content: flex-end;
      gap: 8px;
      margin-top: 10px;
    }

    @media (max-width: 860px) {
      body { overflow: auto; }
      .shell {
        grid-template-columns: 1fr;
        grid-template-rows: minmax(55vh, 1fr) auto;
        height: auto;
        min-height: 100vh;
      }
      .document-pane {
        min-height: 55vh;
        border-right: 0;
        border-bottom: 1px solid var(--border);
      }
      .review-pane {
        height: auto;
        min-height: 45vh;
      }
      .doc { height: 55vh; }
      .review-scroll { overflow: visible; }
    }
  </style>
</head>
<body>
  <main class="shell" data-token="${escapeHtml(token)}" data-version="${latestVersion.version}">
    <section class="document-pane">
      <iframe class="doc" id="snapshot" title="Review snapshot" sandbox="allow-same-origin" src="/r/${encodeURIComponent(token)}/snapshot/${latestVersion.version}"></iframe>
      <button class="selection-popover" id="selection-popover" type="button" hidden>Comment</button>
    </section>

    <aside class="review-pane" aria-label="Review comments">
      <header class="review-header">
        <div class="eyebrow">Clearly Review</div>
        <h1>${escapeHtml(review.title)}</h1>
        <div class="meta">Version ${latestVersion.version} - ${escapeHtml(new Date(latestVersion.createdAt).toLocaleString())}</div>
      </header>

      <div class="review-scroll">
        <form class="composer-card" id="comment-form" data-role="review-composer">
          <div class="composer-title">
            <h2>New comment</h2>
            <span id="selection-state-label">General comment</span>
          </div>

          <div class="selection-box" id="selected">Highlight text in the document to attach this comment to a specific passage.</div>

          <div class="name-row">
            <label for="display-name">Your name</label>
            <input id="display-name" maxlength="80" autocomplete="name" placeholder="Name shown to the publisher">
          </div>

          <label for="body">Comment</label>
          <textarea id="body" maxlength="10000" placeholder="What should change, what is unclear, or what needs a decision?" required></textarea>

          <details class="suggestion">
            <summary>Suggested replacement</summary>
            <textarea id="suggested-replacement" maxlength="50000" placeholder="Optional. Keep this to the selected passage."></textarea>
          </details>

          <div class="composer-error" id="composer-error" role="status"></div>
          <div class="composer-actions">
            <button type="button" class="subtle" id="clear-selection">Clear</button>
            <button class="primary" type="submit" id="post-comment" disabled>Post Comment</button>
          </div>
        </form>

        <section class="section" aria-label="Comments">
          <div class="section-title">
            <h2>Comments <span class="count" id="comment-count"></span></h2>
            <button type="button" class="subtle" id="refresh-comments">Refresh</button>
          </div>
          <div class="comments" id="comments"></div>
        </section>

        <details class="card fork-card">
          <summary>Fork the Markdown instead</summary>
          <div class="fork-body">
            <p class="meta">Use this when a full alternate draft is clearer than individual comments.</p>
            <div class="fork-actions">
              <button type="button" id="load-fork">Load Markdown</button>
              <button class="primary" type="button" id="submit-fork" disabled>Submit Fork</button>
            </div>
            <label for="fork-markdown">Markdown fork</label>
            <textarea id="fork-markdown" spellcheck="false" placeholder="Load the Markdown, edit it here, then submit the fork."></textarea>
          </div>
        </details>
      </div>
    </aside>
  </main>

  <script>
    const root = document.querySelector(".shell");
    const token = root.dataset.token;
    const frame = document.getElementById("snapshot");
    const selectionPopover = document.getElementById("selection-popover");
    const selectedBox = document.getElementById("selected");
    const selectionStateLabel = document.getElementById("selection-state-label");
    const postButton = document.getElementById("post-comment");
    const bodyInput = document.getElementById("body");
    const errorBox = document.getElementById("composer-error");
    const commentsContainer = document.getElementById("comments");
    const commentCount = document.getElementById("comment-count");
    let latestVersion = Number(root.dataset.version);
    let selectedText = "";
    let selectedAnchor = null;
    let commentsCache = [];

    const guestIdKey = "clearlyReviewGuestId:" + token;
    const guestNameKey = "clearlyReviewDisplayName";
    const guestId = localStorage.getItem(guestIdKey) || "gst_" + crypto.randomUUID().replaceAll("-", "").slice(0, 16);
    localStorage.setItem(guestIdKey, guestId);

    const nameInput = document.getElementById("display-name");
    nameInput.value = localStorage.getItem(guestNameKey) || "";

    let boundSnapshotDocument = null;

    frame.addEventListener("load", () => {
      boundSnapshotDocument = null;
      bindSnapshotSelection();
    });
    frame.addEventListener("mouseup", () => setTimeout(captureSelectionFromFrame, 0));
    selectionPopover.addEventListener("click", () => {
      selectionPopover.hidden = true;
      bodyInput.focus();
    });
    document.getElementById("comment-form").addEventListener("submit", postComment);
    document.getElementById("clear-selection").addEventListener("click", () => clearSelection(true));
    document.getElementById("refresh-comments").addEventListener("click", loadComments);
    document.getElementById("load-fork").addEventListener("click", loadForkMarkdown);
    document.getElementById("submit-fork").addEventListener("click", submitFork);
    nameInput.addEventListener("change", () => localStorage.setItem(guestNameKey, nameInput.value.trim()));
    nameInput.addEventListener("input", () => localStorage.setItem(guestNameKey, nameInput.value.trim()));
    bodyInput.addEventListener("input", updateComposerState);

    retryBindSnapshotSelection();
    setInterval(() => {
      if (document.activeElement === frame) captureSelectionFromFrame();
    }, 300);
    loadComments();

    function bindSnapshotSelection() {
      const doc = snapshotDocument();
      if (!doc || !doc.body) return false;
      if (doc === boundSnapshotDocument) return true;
      boundSnapshotDocument = doc;
      injectSnapshotReviewStyles(doc);
      doc.addEventListener("mouseup", () => setTimeout(captureSelectionFromFrame, 0));
      doc.addEventListener("keyup", () => setTimeout(captureSelectionFromFrame, 0));
      doc.addEventListener("selectionchange", () => setTimeout(captureSelectionFromFrame, 0));
      doc.addEventListener("click", event => {
        const mark = event.target && event.target.closest ? event.target.closest("mark[data-review-highlight]") : null;
        if (mark) focusComment(mark.dataset.reviewHighlight);
      });
      applyCommentHighlights();
      return true;
    }

    function retryBindSnapshotSelection() {
      if (bindSnapshotSelection()) return;
      setTimeout(retryBindSnapshotSelection, 100);
    }

    function snapshotDocument() {
      try {
        return frame.contentDocument || frame.contentWindow.document;
      } catch {
        return null;
      }
    }

    function captureSelectionFromFrame() {
      const doc = snapshotDocument();
      const selection = frame.contentWindow && frame.contentWindow.getSelection ? frame.contentWindow.getSelection() : null;
      if (!doc || !selection || !selection.rangeCount || selection.isCollapsed) {
        selectionPopover.hidden = true;
        return false;
      }

      const range = selection.getRangeAt(0).cloneRange();
      const rawSelection = range.toString();
      const trimmed = rawSelection.trim();
      if (!trimmed) {
        selectionPopover.hidden = true;
        return false;
      }

      const block = closestAnchorBlock(range.commonAncestorContainer);
      const blockText = block ? block.textContent || "" : "";
      const leadingTrim = rawSelection.length - rawSelection.trimStart().length;
      let offset = block ? offsetWithinBlock(doc, block, range, leadingTrim) : -1;
      if (offset < 0 && blockText) offset = blockText.indexOf(trimmed);

      selectedText = trimmed;
      selectedAnchor = buildAnchor(block, blockText, offset, trimmed);
      renderSelectedText();
      positionSelectionPopover(range);
      updateComposerState();
      return true;
    }

    function closestAnchorBlock(node) {
      const element = node && node.nodeType === Node.ELEMENT_NODE ? node : node && node.parentElement;
      if (!element || !element.closest) return null;
      return element.closest("[data-sourcepos], p, li, blockquote, pre, td, th, h1, h2, h3, h4, h5, h6, img, table");
    }

    function offsetWithinBlock(doc, block, range, leadingTrim) {
      try {
        const prefixRange = doc.createRange();
        prefixRange.selectNodeContents(block);
        prefixRange.setEnd(range.startContainer, range.startOffset);
        return prefixRange.toString().length + leadingTrim;
      } catch {
        return -1;
      }
    }

    function buildAnchor(block, blockText, offset, text) {
      const safeOffset = Number.isFinite(offset) && offset >= 0 ? offset : null;
      const anchor = {
        blockType: blockTypeFor(block),
        sourcepos: block ? block.getAttribute("data-sourcepos") || "" : "",
        headingId: headingIdFor(block),
        charOffsetInBlock: safeOffset,
        charLength: text.length,
        selectedText: text,
        prefix: safeOffset === null ? null : blockText.slice(Math.max(0, safeOffset - 80), safeOffset),
        suffix: safeOffset === null ? null : blockText.slice(safeOffset + text.length, safeOffset + text.length + 80),
        confidence: "exact",
        anchorNormalizerVersion: 1
      };

      if (anchor.blockType === "table" && block) {
        const cell = block.closest("td, th");
        const row = cell && cell.parentElement;
        anchor.rowIndex = row ? Array.from(row.parentElement.children).indexOf(row) : null;
        anchor.columnIndex = cell ? Array.from(row.children).indexOf(cell) : null;
      }

      return anchor;
    }

    function blockTypeFor(block) {
      if (!block) return "paragraph";
      const tag = block.tagName.toLowerCase();
      if (/^h[1-6]$/.test(tag)) return "heading";
      if (tag === "li") return "listItem";
      if (tag === "blockquote") return "quote";
      if (tag === "pre" || tag === "code") return "code";
      if (tag === "td" || tag === "th" || tag === "table") return "table";
      if (tag === "img") return "image";
      return "paragraph";
    }

    function headingIdFor(block) {
      if (!block) return "";
      if (/^h[1-6]$/i.test(block.tagName) && block.id) return block.id;
      let previous = block.previousElementSibling;
      while (previous) {
        if (/^h[1-6]$/i.test(previous.tagName) && previous.id) return previous.id;
        previous = previous.previousElementSibling;
      }
      return "";
    }

    function positionSelectionPopover(range) {
      const rect = range.getBoundingClientRect();
      const frameRect = frame.getBoundingClientRect();
      if (!rect || (!rect.width && !rect.height)) {
        selectionPopover.hidden = true;
        return;
      }
      selectionPopover.style.left = (frameRect.left + rect.left + rect.width / 2) + "px";
      selectionPopover.style.top = Math.max(48, frameRect.top + rect.top - 8) + "px";
      selectionPopover.hidden = false;
    }

    function renderSelectedText() {
      selectedBox.classList.toggle("has-selection", Boolean(selectedText));
      selectionStateLabel.textContent = selectedText ? "Attached to selection" : "General comment";
      selectedBox.innerHTML = selectedText
        ? "<blockquote>" + escapeText(selectedText) + "</blockquote>"
        : "Highlight text in the document to attach this comment to a specific passage.";
      errorBox.textContent = "";
    }

    function clearSelection(clearFrameSelection) {
      selectedText = "";
      selectedAnchor = null;
      selectionPopover.hidden = true;
      if (clearFrameSelection) {
        const selection = frame.contentWindow && frame.contentWindow.getSelection ? frame.contentWindow.getSelection() : null;
        if (selection) selection.removeAllRanges();
      }
      renderSelectedText();
      updateComposerState();
    }

    function updateComposerState() {
      postButton.disabled = !bodyInput.value.trim();
    }

    function documentAnchor() {
      return {
        blockType: "paragraph",
        sourcepos: "",
        headingId: "",
        charOffsetInBlock: null,
        charLength: 0,
        selectedText: null,
        prefix: null,
        suffix: null,
        confidence: "section",
        anchorNormalizerVersion: 1
      };
    }

    async function postComment(event) {
      event.preventDefault();
      const displayName = nameInput.value.trim() || "Reviewer";
      localStorage.setItem(guestNameKey, displayName);
      const body = bodyInput.value.trim();
      if (!body) {
        updateComposerState();
        return;
      }

      postButton.disabled = true;
      postButton.textContent = "Posting...";
      const suggestedReplacement = document.getElementById("suggested-replacement").value.trim();
      const response = await fetch("/r/" + encodeURIComponent(token) + "/comments", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          version: latestVersion,
          author: { authorId: guestId, displayName },
          body,
          selectedText,
          suggestedReplacement,
          suggestionMode: suggestedReplacement ? "advisory" : "advisory",
          anchor: selectedAnchor || documentAnchor()
        })
      });

      postButton.textContent = "Post Comment";
      if (!response.ok) {
        errorBox.textContent = await response.text();
        updateComposerState();
        return;
      }

      bodyInput.value = "";
      document.getElementById("suggested-replacement").value = "";
      clearSelection(true);
      await loadComments();
    }

    async function loadComments() {
      const payload = await fetchReviewJSON();
      latestVersion = payload.review.latestVersion;
      root.dataset.reviewId = payload.review.reviewId;
      commentsCache = payload.comments || [];
      renderComments();
      applyCommentHighlights();
    }

    function renderComments() {
      const comments = commentsCache;
      const openCount = comments.filter(comment => comment.status === "open").length;
      commentCount.textContent = comments.length ? "(" + openCount + " open / " + comments.length + " total)" : "";
      if (!comments.length) {
        commentsContainer.innerHTML = '<div class="empty">No comments yet. Highlight text in the document to start a review thread.</div>';
        return;
      }

      commentsContainer.innerHTML = comments.map(comment => {
        const id = comment.id || comment.commentId;
        const confidence = comment.anchorConfidence || (comment.currentAnchor && comment.currentAnchor.confidence) || (comment.anchor && comment.anchor.confidence) || "exact";
        return '<article class="card comment" data-comment-id="' + escapeText(id) + '">' +
          '<div class="comment-meta"><strong>' + escapeText(comment.authorDisplayName || comment.author || "Reviewer") + '</strong>' +
          '<span class="pill">' + escapeText(comment.status || "open") + '</span>' +
          '<span class="pill">' + escapeText(confidence) + '</span>' +
          '<span>' + escapeText(formatDate(comment.createdAt)) + '</span></div>' +
          (comment.selectedText ? '<blockquote class="quote">' + escapeText(comment.selectedText) + '</blockquote>' : '') +
          '<p class="comment-body">' + escapeText(comment.body) + '</p>' +
          (comment.suggestedReplacement ? '<div class="replacement"><strong>Suggested replacement</strong><br>' + escapeText(comment.suggestedReplacement) + '</div>' : '') +
          actionsFor(comment) +
          '</article>';
      }).join("");

      commentsContainer.querySelectorAll("[data-comment-id]").forEach(card => {
        card.addEventListener("click", event => {
          if (event.target.closest("button")) return;
          scrollToCommentAnchor(card.dataset.commentId);
          focusComment(card.dataset.commentId);
        });
      });
      commentsContainer.querySelectorAll("[data-edit-comment]").forEach(button => button.addEventListener("click", event => {
        event.stopPropagation();
        editComment(button.dataset.editComment);
      }));
      commentsContainer.querySelectorAll("[data-reopen-comment]").forEach(button => button.addEventListener("click", event => {
        event.stopPropagation();
        reopenComment(button.dataset.reopenComment);
      }));
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
      const comment = commentsCache.find(item => (item.id || item.commentId) === commentId);
      if (!comment) return;
      const body = prompt("Edit comment", comment.body || "");
      if (body === null || !body.trim()) return;
      const response = await fetch("/api/reviews/" + encodeURIComponent(root.dataset.reviewId) + "/comments/" + encodeURIComponent(commentId), {
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
      const comment = commentsCache.find(item => (item.id || item.commentId) === commentId);
      if (!comment) return;
      const response = await fetch("/api/reviews/" + encodeURIComponent(root.dataset.reviewId) + "/comments/" + encodeURIComponent(commentId) + "/reopen", {
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

    function injectSnapshotReviewStyles(doc) {
      if (doc.getElementById("clearly-review-ui-style")) return;
      const style = doc.createElement("style");
      style.id = "clearly-review-ui-style";
      style.textContent = 'mark[data-review-highlight] { background: #fff2a8; color: inherit; border-radius: 3px; padding: 0 1px; cursor: pointer; } mark[data-review-highlight][data-focused="true"] { background: #ffd86b; box-shadow: 0 0 0 2px rgba(36, 95, 214, 0.22); } .clearly-review-block-highlight { outline: 2px solid rgba(36, 95, 214, 0.30); outline-offset: 3px; border-radius: 4px; }';
      doc.head.appendChild(style);
    }

    function applyCommentHighlights() {
      const doc = snapshotDocument();
      if (!doc) return;
      injectSnapshotReviewStyles(doc);
      clearCommentHighlights(doc);
      commentsCache
        .filter(comment => comment.status === "open")
        .forEach(comment => highlightComment(doc, comment));
    }

    function clearCommentHighlights(doc) {
      doc.querySelectorAll("mark[data-review-highlight]").forEach(mark => {
        const parent = mark.parentNode;
        while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
        parent.removeChild(mark);
        parent.normalize();
      });
      doc.querySelectorAll(".clearly-review-block-highlight").forEach(element => {
        element.classList.remove("clearly-review-block-highlight");
      });
    }

    function highlightComment(doc, comment) {
      const id = comment.id || comment.commentId;
      const anchor = comment.currentAnchor || comment.anchor || {};
      const block = blockForAnchor(doc, anchor);
      if (!block) return;
      const text = comment.selectedText || anchor.selectedText || "";
      const offset = Number.isFinite(anchor.charOffsetInBlock) ? anchor.charOffsetInBlock : block.textContent.indexOf(text);
      if (text && offset >= 0 && wrapTextRange(doc, block, offset, text.length, id)) return;
      block.classList.add("clearly-review-block-highlight");
    }

    function blockForAnchor(doc, anchor) {
      if (anchor && anchor.sourcepos) {
        const bySource = Array.from(doc.querySelectorAll("[data-sourcepos]"))
          .find(element => element.getAttribute("data-sourcepos") === String(anchor.sourcepos));
        if (bySource) return bySource;
      }
      if (anchor && anchor.headingId) {
        const heading = doc.getElementById(anchor.headingId);
        if (heading) return heading;
      }
      return null;
    }

    function wrapTextRange(doc, rootNode, start, length, commentId) {
      const end = start + length;
      const walker = doc.createTreeWalker(rootNode, NodeFilter.SHOW_TEXT);
      const nodes = [];
      let position = 0;
      let node;
      while ((node = walker.nextNode())) {
        const value = node.nodeValue || "";
        const nodeStart = position;
        const nodeEnd = position + value.length;
        if (nodeEnd > start && nodeStart < end) {
          nodes.push({ node, nodeStart, nodeEnd });
        }
        position = nodeEnd;
      }
      if (!nodes.length) return false;
      nodes.forEach(item => {
        const localStart = Math.max(0, start - item.nodeStart);
        const localEnd = Math.min((item.node.nodeValue || "").length, end - item.nodeStart);
        if (localEnd <= localStart) return;
        const range = doc.createRange();
        range.setStart(item.node, localStart);
        range.setEnd(item.node, localEnd);
        const mark = doc.createElement("mark");
        mark.dataset.reviewHighlight = commentId;
        range.surroundContents(mark);
      });
      return true;
    }

    function scrollToCommentAnchor(commentId) {
      const doc = snapshotDocument();
      if (!doc) return;
      const target = findHighlightMark(doc, commentId) ||
        blockForAnchor(doc, (commentsCache.find(comment => (comment.id || comment.commentId) === commentId) || {}).currentAnchor || {});
      if (target && target.scrollIntoView) target.scrollIntoView({ block: "center", behavior: "smooth" });
    }

    function focusComment(commentId) {
      commentsContainer.querySelectorAll(".comment.is-focused").forEach(card => card.classList.remove("is-focused"));
      const card = Array.from(commentsContainer.querySelectorAll("[data-comment-id]"))
        .find(element => element.dataset.commentId === commentId);
      if (card) {
        card.classList.add("is-focused");
        card.scrollIntoView({ block: "nearest", behavior: "smooth" });
      }
      const doc = snapshotDocument();
      if (doc) {
        doc.querySelectorAll("mark[data-review-highlight]").forEach(mark => {
          mark.dataset.focused = mark.dataset.reviewHighlight === commentId ? "true" : "false";
        });
      }
    }

    function findHighlightMark(doc, commentId) {
      return Array.from(doc.querySelectorAll("mark[data-review-highlight]"))
        .find(mark => mark.dataset.reviewHighlight === commentId) || null;
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
      document.getElementById("submit-fork").disabled = true;
      alert("Fork submitted.");
    }

    function formatDate(value) {
      if (!value) return "";
      try {
        return new Date(value).toLocaleDateString(undefined, { month: "short", day: "numeric" });
      } catch {
        return "";
      }
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
