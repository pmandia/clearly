import DOMPurify from "isomorphic-dompurify";

const CLEARLY_SNAPSHOT_RE = /<main\b[^>]*\bdata-review-snapshot-version\s*=\s*(['"])1\1[^>]*>/i;
const STYLE_BLOCK_RE = /<style\b[^>]*>([\s\S]*?)<\/style>/gi;
const CSS_COMMENT_RE = /\/\*[\s\S]*?\*\//g;
const TRUSTED_SNAPSHOT_CSS = `
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
`;
const TRUSTED_SNAPSHOT_CSS_FINGERPRINT = cssFingerprint(TRUSTED_SNAPSHOT_CSS);
const ALLOWED_TAGS = [
  "html", "head", "body", "main", "title", "meta",
  "article", "section", "header", "footer", "nav", "aside",
  "h1", "h2", "h3", "h4", "h5", "h6",
  "p", "br", "hr", "blockquote", "pre", "code",
  "ul", "ol", "li", "dl", "dt", "dd",
  "strong", "b", "em", "i", "s", "del", "ins", "mark",
  "a", "img", "table", "thead", "tbody", "tfoot", "tr", "th", "td",
  "span", "div",
];
const ALLOWED_ATTR = [
  "alt", "aria-label", "aria-describedby", "class", "colspan", "content", "data-review-highlight",
  "data-review-snapshot-version", "data-sourcepos", "height", "href", "id", "lang", "name", "rel",
  "rowspan", "scope", "src", "target", "title", "width",
];

export function sanitizeSnapshotHtml(html: string): string {
  return DOMPurify.sanitize(html, {
    ALLOWED_TAGS,
    ALLOWED_ATTR,
    ALLOW_DATA_ATTR: true,
    WHOLE_DOCUMENT: true,
    RETURN_TRUSTED_TYPE: false,
    FORBID_ATTR: ["style"],
    FORBID_TAGS: ["script", "iframe", "object", "embed", "link", "style"],
    ALLOWED_URI_REGEXP: /^(?:(?:https?|mailto):|data:image\/(?:gif|png|jpeg|webp|avif|svg\+xml);base64,|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))/i,
  });
}

export function sanitizeUploadedSnapshotHtml(html: string): string {
  const trustedStyles = extractTrustedSnapshotStyles(html);
  const sanitized = sanitizeSnapshotHtml(html);
  if (trustedStyles.length === 0) return sanitized;

  const styleHtml = trustedStyles.map((style) => `<style>\n${style}\n</style>`).join("\n");
  if (/<\/head>/i.test(sanitized)) {
    return sanitized.replace(/<\/head>/i, `${styleHtml}\n</head>`);
  }
  return `${styleHtml}\n${sanitized}`;
}

function extractTrustedSnapshotStyles(html: string): string[] {
  if (!CLEARLY_SNAPSHOT_RE.test(html)) return [];
  return Array.from(html.matchAll(STYLE_BLOCK_RE))
    .map((match) => match[1]?.trim() ?? "")
    .filter(isTrustedSnapshotStyle);
}

function isTrustedSnapshotStyle(style: string): boolean {
  return cssFingerprint(style) === TRUSTED_SNAPSHOT_CSS_FINGERPRINT;
}

function cssFingerprint(style: string): string {
  return style
    .replace(CSS_COMMENT_RE, "")
    .replace(/\s+/g, " ")
    .replace(/\s*([{}:;,>])\s*/g, "$1")
    .trim();
}

export function escapeHtml(value: string | undefined | null): string {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function noIndexHeaders() {
  return {
    "X-Robots-Tag": "noindex, nofollow",
    "Cache-Control": "private, no-store",
  };
}
