import type { ReviewForkDiff, ReviewForkDiffSummary } from "./types.js";

export function lineDiff(baseVersion: number, before: string, after: string): ReviewForkDiff {
  const oldLines = normalizeLines(before);
  const newLines = normalizeLines(after);
  const lines: ReviewForkDiff["hunks"][number]["lines"] = [];
  let additions = 0;
  let deletions = 0;
  const max = Math.max(oldLines.length, newLines.length);

  for (let index = 0; index < max; index += 1) {
    const oldLine = oldLines[index];
    const newLine = newLines[index];
    if (oldLine === newLine && oldLine !== undefined) {
      lines.push({ type: "context", text: oldLine });
      continue;
    }
    if (oldLine !== undefined) {
      deletions += 1;
      lines.push({ type: "delete", text: oldLine });
    }
    if (newLine !== undefined) {
      additions += 1;
      lines.push({ type: "add", text: newLine });
    }
  }

  return {
    schemaVersion: 1,
    baseVersion,
    algorithm: "normalized-line-diff-v1",
    hunks: [
      {
        oldStart: 1,
        oldLines: oldLines.length,
        newStart: 1,
        newLines: newLines.length,
        lines,
      },
    ],
  };
}

export function diffSummary(diff: ReviewForkDiff): ReviewForkDiffSummary {
  let additions = 0;
  let deletions = 0;
  for (const hunk of diff.hunks) {
    for (const line of hunk.lines) {
      if (line.type === "add") additions += 1;
      if (line.type === "delete") deletions += 1;
    }
  }
  return { additions, deletions, changedSections: [] };
}

function normalizeLines(markdown: string): string[] {
  return markdown.replace(/\r\n?/g, "\n").replace(/[ \t]+$/gm, "").replace(/\n?$/, "\n").split("\n").slice(0, -1);
}
