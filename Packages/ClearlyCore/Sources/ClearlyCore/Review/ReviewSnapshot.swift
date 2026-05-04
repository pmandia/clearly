import CryptoKit
import Foundation

public struct ReviewSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let title: String
    public let contentHash: String
    public let snapshotSanitizerVersion: Int
    public let anchorNormalizerVersion: Int
    public let html: String
    public let sourceMap: ReviewSourceMap

    public init(
        schemaVersion: Int = ReviewStateStore.schemaVersion,
        title: String,
        contentHash: String,
        snapshotSanitizerVersion: Int = ReviewSnapshotSanitizer.version,
        anchorNormalizerVersion: Int = ReviewStateStore.anchorNormalizerVersion,
        html: String,
        sourceMap: ReviewSourceMap
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.contentHash = contentHash
        self.snapshotSanitizerVersion = snapshotSanitizerVersion
        self.anchorNormalizerVersion = anchorNormalizerVersion
        self.html = html
        self.sourceMap = sourceMap
    }
}

public struct ReviewSourceMap: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let anchorNormalizerVersion: Int
    public var blocks: [ReviewSourceBlock]
    public var headings: [ReviewSourceHeading]

    public init(
        schemaVersion: Int = ReviewStateStore.schemaVersion,
        anchorNormalizerVersion: Int = ReviewStateStore.anchorNormalizerVersion,
        blocks: [ReviewSourceBlock],
        headings: [ReviewSourceHeading]
    ) {
        self.schemaVersion = schemaVersion
        self.anchorNormalizerVersion = anchorNormalizerVersion
        self.blocks = blocks
        self.headings = headings
    }
}

public struct ReviewSourceBlock: Codable, Equatable, Sendable {
    public let blockId: String
    public let sourcepos: String
    public let headingId: String?
    public let blockType: ReviewAnchorBlockType
    public let textHash: String
    public let normalizedText: String
    public let charLength: Int

    public init(
        blockId: String,
        sourcepos: String,
        headingId: String?,
        blockType: ReviewAnchorBlockType,
        textHash: String,
        normalizedText: String,
        charLength: Int
    ) {
        self.blockId = blockId
        self.sourcepos = sourcepos
        self.headingId = headingId
        self.blockType = blockType
        self.textHash = textHash
        self.normalizedText = normalizedText
        self.charLength = charLength
    }
}

public struct ReviewSourceHeading: Codable, Equatable, Sendable {
    public let headingId: String
    public let sourcepos: String
    public let title: String
    public let level: Int
    public let parentHeadingId: String?

    public init(
        headingId: String,
        sourcepos: String,
        title: String,
        level: Int,
        parentHeadingId: String?
    ) {
        self.headingId = headingId
        self.sourcepos = sourcepos
        self.title = title
        self.level = level
        self.parentHeadingId = parentHeadingId
    }
}

public enum ReviewSnapshotRenderer {
    public static func render(markdown: String, title: String) -> ReviewSnapshot {
        let renderedBody = MarkdownRenderer.renderHTML(markdown, appLinkURLs: false, includeFrontmatter: false)
        let sanitizedBody = ReviewSnapshotSanitizer.sanitize(renderedBody)
        let sourceMap = ReviewSourceMapBuilder.build(fromSanitizedHTML: sanitizedBody)
        let wrapped = wrapSnapshotHTML(title: title, body: sanitizedBody)
        return ReviewSnapshot(
            title: title,
            contentHash: contentHash(for: markdown),
            html: wrapped,
            sourceMap: sourceMap
        )
    }

    private static func wrapSnapshotHTML(title: String, body: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="robots" content="noindex,nofollow">
        <title>\(escapeHTML(title))</title>
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
        \(body)
        </main>
        </body>
        </html>
        """
    }

    private static func contentHash(for markdown: String) -> String {
        let digest = SHA256.hash(data: Data(markdown.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

public enum ReviewSnapshotSanitizer {
    public static let version = 1

    public static func sanitize(_ html: String) -> String {
        var result = html
        result = removeBlocks(named: ["script", "iframe", "object", "embed"], from: result)
        result = removeTags(named: ["link", "meta", "style"], from: result)
        result = removeAttributes(matching: #"\s+on[a-zA-Z]+\s*=\s*"[^"]*""#, from: result)
        result = removeAttributes(matching: #"\s+on[a-zA-Z]+\s*=\s*'[^']*'"#, from: result)
        result = removeAttributes(matching: #"\s+style\s*=\s*"[^"]*""#, from: result)
        result = removeAttributes(matching: #"\s+style\s*=\s*'[^']*'"#, from: result)
        result = removeUnsafeURLAttributes(from: result, attribute: "href")
        result = removeUnsafeURLAttributes(from: result, attribute: "src")
        return result
    }

    private static func removeBlocks(named names: [String], from html: String) -> String {
        names.reduce(html) { partial, name in
            partial.replacingOccurrences(
                of: #"<\#(name)\b[\s\S]*?<\/\#(name)\s*>"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
    }

    private static func removeTags(named names: [String], from html: String) -> String {
        names.reduce(html) { partial, name in
            partial.replacingOccurrences(
                of: #"<\/?\#(name)\b[^>]*>"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
    }

    private static func removeAttributes(matching pattern: String, from html: String) -> String {
        html.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
    }

    private static func removeUnsafeURLAttributes(from html: String, attribute: String) -> String {
        html.replacingOccurrences(
            of: #"\s+\#(attribute)\s*=\s*(["'])\s*(?:javascript|data:text\/html)[^"']*\1"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}

public enum ReviewSourceMapBuilder {
    public static func build(fromSanitizedHTML html: String) -> ReviewSourceMap {
        let headings = extractHeadings(from: html)
        let blocks = extractBlocks(from: html, headings: headings)
        return ReviewSourceMap(blocks: blocks, headings: headings)
    }

    private static func extractHeadings(from html: String) -> [ReviewSourceHeading] {
        let pattern = #"<h([1-6])\b([^>]*)data-sourcepos="([^"]+)"([^>]*)>([\s\S]*?)<\/h\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        var stack: [(level: Int, id: String)] = []
        var headings: [ReviewSourceHeading] = []

        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            guard let level = Int(ns.substring(with: match.range(at: 1))) else { continue }
            let attributes = ns.substring(with: match.range(at: 2)) + ns.substring(with: match.range(at: 4))
            let sourcepos = ns.substring(with: match.range(at: 3))
            let title = normalizeText(stripTags(ns.substring(with: match.range(at: 5))))
            let headingId = attribute("id", in: attributes) ?? slugify(title)
            while let last = stack.last, last.level >= level {
                stack.removeLast()
            }
            let parentHeadingId = stack.last?.id
            headings.append(ReviewSourceHeading(
                headingId: headingId,
                sourcepos: sourcepos,
                title: title,
                level: level,
                parentHeadingId: parentHeadingId
            ))
            stack.append((level, headingId))
        }

        return headings
    }

    private static func extractBlocks(from html: String, headings: [ReviewSourceHeading]) -> [ReviewSourceBlock] {
        let pattern = #"<(h[1-6]|p|li|blockquote|pre|table|div|img)\b([^>]*)data-sourcepos="([^"]+)"([^>]*)(?:>([\s\S]*?)<\/\1>|\/?>)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        var blocks: [ReviewSourceBlock] = []

        for (index, match) in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).enumerated() {
            let tag = ns.substring(with: match.range(at: 1)).lowercased()
            let attributes = ns.substring(with: match.range(at: 2)) + ns.substring(with: match.range(at: 4))
            let sourcepos = ns.substring(with: match.range(at: 3))
            let body = match.range(at: 5).location == NSNotFound ? "" : ns.substring(with: match.range(at: 5))
            let blockType = blockType(tag: tag, attributes: attributes, body: body)
            let text = normalizeText(stripTags(body.isEmpty ? attributes : body))
            let headingId = currentHeadingId(for: sourcepos, headings: headings)
            let normalized = blockType == .image ? normalizeText(attribute("alt", in: attributes) ?? "") : text
            let hash = normalizedTextHash(normalized)
            blocks.append(ReviewSourceBlock(
                blockId: String(format: "blk_%04d", index + 1),
                sourcepos: sourcepos,
                headingId: blockType == .heading ? headingIdFor(sourcepos: sourcepos, headings: headings) : headingId,
                blockType: blockType,
                textHash: hash,
                normalizedText: normalized,
                charLength: normalized.count
            ))
        }

        return blocks
    }

    public static func normalizeText(_ text: String) -> String {
        decodeHTMLEntities(text)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizedTextHash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(normalizeText(text).utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func blockType(tag: String, attributes: String, body: String) -> ReviewAnchorBlockType {
        if tag.hasPrefix("h") { return .heading }
        if tag == "li" { return .listItem }
        if tag == "blockquote" { return .quote }
        if tag == "pre" {
            let text = stripTags(body).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.hasPrefix("mermaid") ? .mermaid : .code
        }
        if tag == "table" { return .table }
        if tag == "img" { return .image }
        if attributes.contains("frontmatter") { return .frontmatter }
        if attributes.contains("math-block") { return .math }
        return .paragraph
    }

    private static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\#(name)="([^"]*)""#, options: [.caseInsensitive]) else { return nil }
        let ns = attributes as NSString
        guard let match = regex.firstMatch(in: attributes, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func headingIdFor(sourcepos: String, headings: [ReviewSourceHeading]) -> String? {
        headings.first { $0.sourcepos == sourcepos }?.headingId
    }

    private static func currentHeadingId(for sourcepos: String, headings: [ReviewSourceHeading]) -> String? {
        guard let line = startLine(sourcepos) else { return nil }
        return headings
            .compactMap { heading -> (line: Int, id: String)? in
                guard let headingLine = startLine(heading.sourcepos), headingLine <= line else { return nil }
                return (headingLine, heading.headingId)
            }
            .max(by: { $0.line < $1.line })?
            .id
    }

    private static func startLine(_ sourcepos: String) -> Int? {
        guard let colon = sourcepos.firstIndex(of: ":") else { return nil }
        return Int(sourcepos[..<colon])
    }

    private static func slugify(_ text: String) -> String {
        let lower = text.lowercased()
        let replaced = lower.replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        let trimmed = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "section" : trimmed
    }
}
