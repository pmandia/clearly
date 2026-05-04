import type { ReviewAnchorConfidence, ReviewComment, ReviewRemappedComment } from "./types.js";

const FUZZY_THRESHOLD = 0.82;
const SELECTED_THRESHOLD = 0.72;
const TIE_BREAKER_MARGIN = 0.03;

type AnchorObject = Record<string, unknown>;

interface SourceMap {
  schemaVersion?: number;
  anchorNormalizerVersion?: number;
  blocks: SourceBlock[];
  headings: SourceHeading[];
}

interface SourceBlock {
  blockId: string;
  sourcepos: string;
  headingId?: string;
  blockType: string;
  textHash?: string;
  normalizedText: string;
  charLength?: number;
}

interface SourceHeading {
  headingId: string;
  sourcepos: string;
  title: string;
  level: number;
  parentHeadingId?: string;
}

interface TextRange {
  start: number;
  length: number;
}

interface BlockMatch {
  block: SourceBlock;
  range?: TextRange;
  score: number;
  selectedScore: number;
  prefixScore: number;
  suffixScore: number;
  documentIndex: number;
}

interface Token {
  value: string;
  start: number;
  end: number;
}

export function remapComment(comment: ReviewComment, sourceMapJson: unknown, remappedVersion: number): ReviewRemappedComment {
  const sourceMap = parseSourceMap(sourceMapJson);
  const original = asAnchor(comment.anchor);
  const selectedText = selectedTextFor(comment, original);

  const exactBlock = exactBlockMatch(original, sourceMap);
  if (exactBlock) {
    const anchor = anchorForMatch(original, exactBlock.block, exactBlock.range, "exact", selectedText);
    return {
      commentId: comment.id,
      confidence: "exact",
      reason: "block_text_hash_exact_match",
      anchor,
      remappedVersion,
    };
  }

  const exactSelected = exactSelectedMatch(original, selectedText, sourceMap);
  if (exactSelected) {
    const anchor = anchorForMatch(original, exactSelected.block, exactSelected.range, "exact", selectedText);
    return {
      commentId: comment.id,
      confidence: "exact",
      reason: "selected_text_exact_match",
      anchor,
      remappedVersion,
    };
  }

  const fuzzy = fuzzyMatch(original, selectedText, sourceMap);
  if (fuzzy) {
    const anchor = anchorForMatch(original, fuzzy.block, fuzzy.range, "fuzzy", selectedText);
    return {
      commentId: comment.id,
      confidence: "fuzzy",
      reason: `prefix_suffix_fuzzy_match:${fuzzy.score.toFixed(2)}`,
      anchor,
      remappedVersion,
    };
  }

  const section = sectionFallback(original, sourceMap);
  if (section) {
    return {
      commentId: comment.id,
      confidence: "section",
      reason: "heading_id_fallback",
      anchor: anchorForSectionFallback(original, section, selectedText),
      remappedVersion,
    };
  }

  return {
    commentId: comment.id,
    confidence: "orphan",
    reason: "orphaned_no_match",
    anchor: orphanAnchor(original, selectedText),
    remappedVersion,
  };
}

export function parseSourceMap(value: unknown): SourceMap {
  const object = typeof value === "object" && value !== null ? (value as Record<string, unknown>) : {};
  const rawBlocks = Array.isArray(object.blocks) ? object.blocks : [];
  const rawHeadings = Array.isArray(object.headings) ? object.headings : [];
  return {
    schemaVersion: numberValue(object.schemaVersion),
    anchorNormalizerVersion: numberValue(object.anchorNormalizerVersion),
    blocks: rawBlocks.flatMap((block, index) => parseBlock(block, index)),
    headings: rawHeadings.flatMap(parseHeading),
  };
}

function parseBlock(value: unknown, index: number): SourceBlock[] {
  if (typeof value !== "object" || value === null) return [];
  const object = value as Record<string, unknown>;
  const sourcepos = stringValue(object.sourcepos);
  const normalizedText = normalizeText(stringValue(object.normalizedText));
  if (!sourcepos && !normalizedText) return [];
  return [{
    blockId: stringValue(object.blockId) || `blk_${index + 1}`,
    sourcepos,
    headingId: optionalString(object.headingId),
    blockType: stringValue(object.blockType) || "paragraph",
    textHash: optionalString(object.textHash) ?? optionalString(object.blockTextHash),
    normalizedText,
    charLength: numberValue(object.charLength),
  }];
}

function parseHeading(value: unknown): SourceHeading[] {
  if (typeof value !== "object" || value === null) return [];
  const object = value as Record<string, unknown>;
  const headingId = stringValue(object.headingId);
  if (!headingId) return [];
  return [{
    headingId,
    sourcepos: stringValue(object.sourcepos),
    title: stringValue(object.title),
    level: numberValue(object.level) ?? 1,
    parentHeadingId: optionalString(object.parentHeadingId),
  }];
}

function exactBlockMatch(anchor: AnchorObject, sourceMap: SourceMap): BlockMatch | undefined {
  const hash = optionalString(anchor.blockTextHash) ?? optionalString(anchor.codeBlockHash) ?? optionalString(anchor.tableHash);
  if (!hash) return undefined;
  const candidates = candidateBlocks(anchor, sourceMap)
    .map((block, documentIndex) => ({ block, documentIndex }))
    .filter(({ block }) => block.textHash === hash);
  if (candidates.length === 0) return undefined;
  const sorted = sortMatches(candidates.map(({ block, documentIndex }) => ({
    block,
    documentIndex,
    range: rangeFromAnchor(anchor, block),
    score: 1,
    selectedScore: 1,
    prefixScore: 1,
    suffixScore: 1,
  })), anchor, sourceMap);
  return sorted[0];
}

function exactSelectedMatch(anchor: AnchorObject, selectedText: string, sourceMap: SourceMap): BlockMatch | undefined {
  const selected = normalizeText(selectedText);
  if (!selected) return undefined;

  const caseSensitive = collectExactMatches(anchor, sourceMap, selected, false);
  const matches = caseSensitive.length > 0 ? caseSensitive : collectExactMatches(anchor, sourceMap, selected, true);
  if (matches.length === 0) return undefined;

  const sorted = sortMatches(matches, anchor, sourceMap);
  if (sorted.length === 1) return sorted[0];
  if (isAmbiguous(sorted[0], sorted[1])) return undefined;
  return sorted[0];
}

function collectExactMatches(anchor: AnchorObject, sourceMap: SourceMap, selected: string, caseInsensitive: boolean): BlockMatch[] {
  const matches: BlockMatch[] = [];
  const blocks = candidateBlocks(anchor, sourceMap);
  for (const [documentIndex, block] of blocks.entries()) {
    const ranges = findAllRanges(block.normalizedText, selected, caseInsensitive);
    for (const range of ranges) {
      matches.push({
        block,
        range,
        score: 1,
        selectedScore: 1,
        prefixScore: 1,
        suffixScore: 1,
        documentIndex,
      });
    }
  }
  return matches;
}

function fuzzyMatch(anchor: AnchorObject, selectedText: string, sourceMap: SourceMap): BlockMatch | undefined {
  const prefixText = stringValue(anchor.prefix);
  const suffixText = stringValue(anchor.suffix);
  const selectedTokens = tokensFor(selectedText);
  const prefixTokens = tokensFor(prefixText).slice(-12);
  const suffixTokens = tokensFor(suffixText).slice(0, 12);
  if (selectedTokens.length === 0 && prefixTokens.length === 0 && suffixTokens.length === 0) return undefined;

  const matches: BlockMatch[] = [];
  for (const [documentIndex, block] of candidateBlocks(anchor, sourceMap).entries()) {
    const match = fuzzyMatchBlock(block, documentIndex, selectedText, prefixText, suffixText, selectedTokens, prefixTokens, suffixTokens);
    if (match) matches.push(match);
  }
  if (matches.length === 0) return undefined;

  const sorted = sortMatches(matches, anchor, sourceMap);
  const best = sorted[0];
  if (!best || best.score < FUZZY_THRESHOLD) return undefined;
  if (sorted.length > 1 && isAmbiguous(best, sorted[1])) return undefined;
  return best;
}

function fuzzyMatchBlock(
  block: SourceBlock,
  documentIndex: number,
  selectedText: string,
  prefixText: string,
  suffixText: string,
  selectedTokens: string[],
  prefixTokens: string[],
  suffixTokens: string[]
): BlockMatch | undefined {
  const blockTokens = tokenizeWithOffsets(block.normalizedText);
  if (blockTokens.length === 0) return undefined;

  const blockWideTokens = tokensFor(block.normalizedText);
  const blockWideSelectedScore = selectedTokens.length === 0 ? 0 : componentScore(selectedText, selectedTokens, block.normalizedText, blockWideTokens);
  const blockWidePrefixScore = prefixTokens.length === 0 ? 0 : componentScore(prefixText, prefixTokens, block.normalizedText, blockWideTokens);
  const blockWideSuffixScore = suffixTokens.length === 0 ? 0 : componentScore(suffixText, suffixTokens, block.normalizedText, blockWideTokens);
  const blockWidePrefixComponent = prefixTokens.length === 0 ? blockWideSelectedScore : blockWidePrefixScore;
  const blockWideSuffixComponent = suffixTokens.length === 0 ? blockWideSelectedScore : blockWideSuffixScore;
  const blockWideScore = (blockWideSelectedScore * 0.60) + (blockWidePrefixComponent * 0.20) + (blockWideSuffixComponent * 0.20);
  let best: BlockMatch | undefined = fuzzyScoresPassGates(
    selectedText,
    block.normalizedText,
    selectedTokens,
    blockWideSelectedScore,
    blockWidePrefixScore,
    blockWideSuffixScore
  ) ? {
    block,
    score: blockWideScore,
    selectedScore: blockWideSelectedScore,
    prefixScore: blockWidePrefixScore,
    suffixScore: blockWideSuffixScore,
    documentIndex,
  } : undefined;

  const selectedLength = Math.max(1, selectedTokens.length);
  const minWindow = Math.max(1, Math.max(8, selectedLength - 4));
  const maxWindow = Math.max(minWindow, selectedLength + 12);

  for (let start = 0; start < blockTokens.length; start += 1) {
    const upperLength = Math.min(maxWindow, blockTokens.length - start);
    for (let length = Math.min(minWindow, upperLength); length <= upperLength; length += 1) {
      const window = blockTokens.slice(start, start + length);
      const candidateTokens = window.map((token) => token.value);
      const candidatePrefix = blockTokens.slice(Math.max(0, start - prefixTokens.length), start).map((token) => token.value);
      const candidateSuffix = blockTokens.slice(start + length, start + length + suffixTokens.length).map((token) => token.value);

      const selectedScore = selectedTokens.length === 0 ? 0 : dice(selectedTokens, candidateTokens);
      const prefixScore = prefixTokens.length === 0 ? 0 : dice(prefixTokens, candidatePrefix);
      const suffixScore = suffixTokens.length === 0 ? 0 : dice(suffixTokens, candidateSuffix);
      const prefixComponent = prefixTokens.length === 0 ? selectedScore : prefixScore;
      const suffixComponent = suffixTokens.length === 0 ? selectedScore : suffixScore;
      const score = (selectedScore * 0.60) + (prefixComponent * 0.20) + (suffixComponent * 0.20);

      if (!fuzzyScoresPassGates(selectedText, block.normalizedText, selectedTokens, selectedScore, prefixScore, suffixScore)) continue;

      const range = {
        start: window[0].start,
        length: Math.max(0, window[window.length - 1].end - window[0].start),
      };
      const candidate: BlockMatch = {
        block,
        range,
        score,
        selectedScore,
        prefixScore,
        suffixScore,
        documentIndex,
      };
      if (!best || candidate.score > best.score) best = candidate;
    }
  }

  return best;
}

function componentScore(needle: string, needleTokens: string[], haystack: string, haystackTokens: string[]): number {
  const normalizedNeedle = normalizeText(needle).toLowerCase();
  if (normalizedNeedle && haystack.toLowerCase().includes(normalizedNeedle)) return 1;
  const diceScore = dice(needleTokens, haystackTokens);
  if (!containsCJK(normalizedNeedle)) return diceScore;
  return Math.max(diceScore, containmentRecall(needleTokens, haystackTokens));
}

function containmentRecall(lhs: string[], rhs: string[]): number {
  if (lhs.length === 0 || rhs.length === 0) return 0;
  const left = new Set(lhs);
  const right = new Set(rhs);
  let intersection = 0;
  for (const token of left) {
    if (right.has(token)) intersection += 1;
  }
  return intersection / left.size;
}

function fuzzyScoresPassGates(
  selectedText: string,
  blockText: string,
  selectedTokens: string[],
  selectedScore: number,
  prefixScore: number,
  suffixScore: number
): boolean {
  const hasExactSelected = normalizeText(selectedText) !== "" && blockText.toLowerCase().includes(normalizeText(selectedText).toLowerCase());
  if (selectedTokens.length >= 6 && selectedScore < SELECTED_THRESHOLD) return false;
  if (selectedTokens.length < 6 && !hasExactSelected && (prefixScore < 0.80 || suffixScore < 0.80)) return false;
  return true;
}

function sectionFallback(anchor: AnchorObject, sourceMap: SourceMap): SourceBlock | undefined {
  const headingId = optionalString(anchor.headingId);
  if (!headingId) return undefined;
  return sourceMap.blocks.find((block) => block.headingId === headingId && block.blockType !== "heading")
    ?? sourceMap.blocks.find((block) => block.headingId === headingId && block.blockType === "heading");
}

function candidateBlocks(anchor: AnchorObject, sourceMap: SourceMap): SourceBlock[] {
  const blockType = stringValue(anchor.blockType) || "paragraph";
  const preferred = preferredBlockTypes(blockType);
  const filtered = sourceMap.blocks.filter((block) => preferred.includes(block.blockType));
  return filtered.length > 0 ? filtered : sourceMap.blocks;
}

function preferredBlockTypes(blockType: string): string[] {
  switch (blockType) {
    case "paragraph":
    case "heading":
    case "listItem":
    case "quote":
    case "multiBlock":
      return ["paragraph", "heading", "listItem", "quote"];
    case "code":
    case "mermaid":
      return ["code", "mermaid"];
    case "table":
      return ["table"];
    case "math":
      return ["math"];
    case "image":
      return ["image"];
    case "frontmatter":
      return ["frontmatter"];
    default:
      return ["paragraph", "heading", "listItem", "quote"];
  }
}

function anchorForMatch(original: AnchorObject, block: SourceBlock, range: TextRange | undefined, confidence: ReviewAnchorConfidence, selectedText: string): AnchorObject {
  const base: AnchorObject = {
    ...original,
    blockType: anchorBlockTypeForSourceBlock(block.blockType),
    sourcepos: block.sourcepos,
    headingId: block.headingId ?? null,
    blockTextHash: block.textHash ?? null,
    selectedText: selectedText || optionalString(original.selectedText) || null,
    confidence,
    anchorNormalizerVersion: 1,
  };
  if (range) {
    base.charOffsetInBlock = range.start;
    base.charLength = range.length;
  }
  if (block.blockType === "code" || block.blockType === "mermaid") {
    base.blockType = "code";
    base.startLine = sourceStartLine(block.sourcepos) ?? numberValue(original.startLine) ?? numberValue(original.startCodeLine) ?? 1;
    base.endLine = sourceEndLine(block.sourcepos) ?? numberValue(original.endLine) ?? numberValue(original.endCodeLine) ?? base.startLine;
    base.startColumn = range?.start ?? numberValue(original.startColumn) ?? null;
    base.endColumn = range ? range.start + range.length : numberValue(original.endColumn) ?? null;
  } else if (block.blockType === "table") {
    base.rowIndex = numberValue(original.rowIndex) ?? 0;
    base.columnIndex = numberValue(original.columnIndex) ?? 0;
    base.charOffsetInCell = range?.start ?? numberValue(original.charOffsetInCell) ?? null;
    base.charLength = range?.length ?? numberValue(original.charLength) ?? null;
  } else if (block.blockType === "image") {
    base.blockType = "image";
    base.alt = selectedText || optionalString(original.alt) || null;
  }
  return base;
}

function anchorForSectionFallback(original: AnchorObject, block: SourceBlock, selectedText: string): AnchorObject {
  return {
    ...original,
    blockType: "paragraph",
    sourcepos: block.sourcepos,
    headingId: block.headingId ?? null,
    blockTextHash: block.textHash ?? null,
    selectedText: selectedText || optionalString(original.selectedText) || null,
    confidence: "section",
    anchorNormalizerVersion: 1,
  };
}

function orphanAnchor(original: AnchorObject, selectedText: string): AnchorObject {
  return {
    ...original,
    selectedText: selectedText || optionalString(original.selectedText) || null,
    confidence: "orphan",
    anchorNormalizerVersion: 1,
  };
}

function sortMatches(matches: BlockMatch[], anchor: AnchorObject, sourceMap: SourceMap): BlockMatch[] {
  const headingId = optionalString(anchor.headingId);
  const originalLine = sourceStartLine(stringValue(anchor.sourcepos));
  return [...matches].sort((lhs, rhs) => {
    if (Math.abs(lhs.score - rhs.score) > 0.000001) return rhs.score - lhs.score;
    if (headingId) {
      const lhsSameHeading = lhs.block.headingId === headingId ? 1 : 0;
      const rhsSameHeading = rhs.block.headingId === headingId ? 1 : 0;
      if (lhsSameHeading !== rhsSameHeading) return rhsSameHeading - lhsSameHeading;
      const lhsSameParent = sameParentHeading(lhs.block.headingId, headingId, sourceMap) ? 1 : 0;
      const rhsSameParent = sameParentHeading(rhs.block.headingId, headingId, sourceMap) ? 1 : 0;
      if (lhsSameParent !== rhsSameParent) return rhsSameParent - lhsSameParent;
    }
    if (originalLine !== undefined) {
      const lhsLine = sourceStartLine(lhs.block.sourcepos) ?? 0;
      const rhsLine = sourceStartLine(rhs.block.sourcepos) ?? 0;
      const lhsDistance = Math.abs(lhsLine - originalLine);
      const rhsDistance = Math.abs(rhsLine - originalLine);
      if (lhsDistance !== rhsDistance) return lhsDistance - rhsDistance;
    }
    if (Math.abs(lhs.selectedScore - rhs.selectedScore) > 0.000001) return rhs.selectedScore - lhs.selectedScore;
    return lhs.documentIndex - rhs.documentIndex;
  });
}

function isAmbiguous(best: BlockMatch, runnerUp: BlockMatch): boolean {
  return Math.abs(best.score - runnerUp.score) < TIE_BREAKER_MARGIN;
}

function sameParentHeading(lhsHeadingId: string | undefined, rhsHeadingId: string, sourceMap: SourceMap): boolean {
  if (!lhsHeadingId) return false;
  const lhs = sourceMap.headings.find((heading) => heading.headingId === lhsHeadingId);
  const rhs = sourceMap.headings.find((heading) => heading.headingId === rhsHeadingId);
  return Boolean(lhs?.parentHeadingId && rhs?.parentHeadingId && lhs.parentHeadingId === rhs.parentHeadingId);
}

function selectedTextFor(comment: ReviewComment, anchor: AnchorObject): string {
  return normalizeText(
    comment.selectedText
    ?? optionalString(anchor.selectedText)
    ?? optionalString(anchor.alt)
    ?? ""
  );
}

function rangeFromAnchor(anchor: AnchorObject, block: SourceBlock): TextRange | undefined {
  const start = numberValue(anchor.charOffsetInBlock) ?? numberValue(anchor.charOffsetInCell) ?? numberValue(anchor.startColumn);
  const length = numberValue(anchor.charLength);
  if (start === undefined || length === undefined) return undefined;
  if (start < 0 || length < 0 || start > block.normalizedText.length) return undefined;
  return { start, length: Math.min(length, Math.max(0, block.normalizedText.length - start)) };
}

function anchorBlockTypeForSourceBlock(blockType: string): string {
  switch (blockType) {
    case "heading":
    case "listItem":
    case "quote":
    case "code":
    case "table":
    case "math":
    case "mermaid":
    case "image":
    case "frontmatter":
      return blockType;
    default:
      return "paragraph";
  }
}

function findAllRanges(text: string, needle: string, caseInsensitive: boolean): TextRange[] {
  const haystack = caseInsensitive ? text.toLowerCase() : text;
  const target = caseInsensitive ? needle.toLowerCase() : needle;
  const ranges: TextRange[] = [];
  let index = haystack.indexOf(target);
  while (index >= 0) {
    ranges.push({ start: index, length: target.length });
    index = haystack.indexOf(target, index + Math.max(1, target.length));
  }
  return ranges;
}

function tokenizeWithOffsets(text: string): Token[] {
  const normalized = normalizeText(text).toLowerCase();
  const wordMatches = Array.from(normalized.matchAll(/[\p{L}\p{N}]+/gu));
  if (wordMatches.length > 0) {
    return wordMatches.flatMap((match) => {
      const value = match[0];
      const start = match.index ?? 0;
      if (containsCJK(value)) return cjkTokensWithOffsets(value, start);
      return [{
        value: match[0],
        start: match.index ?? 0,
        end: (match.index ?? 0) + match[0].length,
      }];
    })
      .filter((token) => token.value.length >= 2 || /^\p{N}+$/u.test(token.value) || containsCJK(token.value));
  }

  const chars = Array.from(normalized).filter(isTokenChar);
  return chars.map((char, index) => ({ value: char, start: index, end: index + char.length }));
}

function tokensFor(text: string): string[] {
  const normalized = normalizeText(text).toLowerCase();
  const wordTokens = Array.from(normalized.matchAll(/[\p{L}\p{N}]+/gu))
    .flatMap((match) => containsCJK(match[0]) ? cjkNgrams(match[0]) : [match[0]])
    .filter((token) => token.length >= 2 || /^\p{N}+$/u.test(token) || containsCJK(token));
  if (wordTokens.length > 0) return wordTokens;
  const compact = Array.from(normalized).filter(isTokenChar);
  if (compact.length <= 1) return compact;
  const grams: string[] = [];
  for (let index = 0; index < compact.length - 1; index += 1) {
    grams.push(compact.slice(index, index + 2).join(""));
  }
  for (let index = 0; index < compact.length - 2; index += 1) {
    grams.push(compact.slice(index, index + 3).join(""));
  }
  return grams;
}

function cjkTokensWithOffsets(value: string, startOffset: number): Token[] {
  const chars = Array.from(value);
  if (chars.length === 1) {
    return [{ value, start: startOffset, end: startOffset + value.length }];
  }
  const tokens: Token[] = [];
  for (let index = 0; index < chars.length; index += 1) {
    for (const size of [2, 3]) {
      if (index + size > chars.length) continue;
      const token = chars.slice(index, index + size).join("");
      tokens.push({ value: token, start: startOffset + index, end: startOffset + index + token.length });
    }
  }
  return tokens.length ? tokens : [{ value, start: startOffset, end: startOffset + value.length }];
}

function cjkNgrams(value: string): string[] {
  const chars = Array.from(value);
  if (chars.length <= 1) return chars;
  const grams: string[] = [];
  for (let index = 0; index < chars.length; index += 1) {
    for (const size of [2, 3]) {
      if (index + size > chars.length) continue;
      grams.push(chars.slice(index, index + size).join(""));
    }
  }
  return grams.length ? grams : chars;
}

function dice(lhs: string[], rhs: string[]): number {
  if (lhs.length === 0 || rhs.length === 0) return 0;
  const left = new Set(lhs);
  const right = new Set(rhs);
  let intersection = 0;
  for (const token of left) {
    if (right.has(token)) intersection += 1;
  }
  return (2 * intersection) / (left.size + right.size);
}

export function normalizeText(text: string): string {
  return decodeHtmlEntities(text)
    .replace(/\s+/gu, " ")
    .trim();
}

function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, "\"")
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&#(\d+);/g, (_match, raw: string) => {
      const codePoint = Number(raw);
      return Number.isFinite(codePoint) ? String.fromCodePoint(codePoint) : "";
    });
}

function containsCJK(value: string): boolean {
  return /[\u3040-\u30FF\u3400-\u9FFF\uAC00-\uD7AF\uF900-\uFAFF]/u.test(value);
}

function isTokenChar(value: string): boolean {
  return /[\p{L}\p{N}\u3040-\u30FF\u3400-\u9FFF\uAC00-\uD7AF\uF900-\uFAFF]/u.test(value);
}

function asAnchor(value: unknown): AnchorObject {
  return typeof value === "object" && value !== null ? (value as AnchorObject) : {};
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function numberValue(value: unknown): number | undefined {
  const parsed = typeof value === "number" ? value : typeof value === "string" ? Number(value) : Number.NaN;
  return Number.isFinite(parsed) ? parsed : undefined;
}

function sourceStartLine(sourcepos: string): number | undefined {
  const match = /^(\d+):/.exec(sourcepos);
  return match ? Number(match[1]) : undefined;
}

function sourceEndLine(sourcepos: string): number | undefined {
  const match = /-(\d+):/.exec(sourcepos);
  return match ? Number(match[1]) : undefined;
}
