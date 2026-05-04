import Foundation

public struct ReviewRemapResult: Codable, Equatable, Sendable {
    public let commentId: String?
    public let anchor: ReviewAnchor
    public let confidence: ReviewAnchorConfidence
    public let reason: String

    public init(commentId: String? = nil, anchor: ReviewAnchor, confidence: ReviewAnchorConfidence, reason: String) {
        self.commentId = commentId
        self.anchor = anchor
        self.confidence = confidence
        self.reason = reason
    }
}

public enum ReviewAnchorRemapper {
    public static let fuzzyThreshold = 0.82
    public static let selectedFuzzyThreshold = 0.72
    public static let shortSelectionContextThreshold = 0.80
    public static let tieBreakerMargin = 0.03

    public static func remap(comment: ReviewComment, into sourceMap: ReviewSourceMap) -> ReviewRemapResult {
        remap(anchor: comment.anchor, commentId: comment.id, into: sourceMap)
    }

    public static func remap(anchor: ReviewAnchor, commentId: String? = nil, into sourceMap: ReviewSourceMap) -> ReviewRemapResult {
        if let exact = exactMatch(for: anchor, in: sourceMap) {
            return ReviewRemapResult(
                commentId: commentId,
                anchor: anchorForMatch(anchor, block: exact.block, range: exact.range, confidence: .exact),
                confidence: .exact,
                reason: "selected_text_exact_match"
            )
        }

        if let fuzzy = fuzzyMatch(for: anchor, in: sourceMap) {
            return ReviewRemapResult(
                commentId: commentId,
                anchor: anchorForMatch(anchor, block: fuzzy.block, range: fuzzy.range, confidence: .fuzzy),
                confidence: .fuzzy,
                reason: String(format: "prefix_suffix_fuzzy_match:%.2f", fuzzy.score)
            )
        }

        if let section = sectionFallback(for: anchor, in: sourceMap) {
            return ReviewRemapResult(
                commentId: commentId,
                anchor: anchorForSectionFallback(anchor, block: section),
                confidence: .section,
                reason: "heading_id_fallback"
            )
        }

        return ReviewRemapResult(
            commentId: commentId,
            anchor: orphanAnchor(from: anchor),
            confidence: .orphan,
            reason: "orphaned_no_match"
        )
    }

    private static func exactMatch(for anchor: ReviewAnchor, in sourceMap: ReviewSourceMap) -> (block: ReviewSourceBlock, range: Range<String.Index>)? {
        guard let selected = normalizedSelection(anchor), !selected.isEmpty else { return nil }
        var matches: [(ReviewSourceBlock, Range<String.Index>)] = []

        for block in candidateBlocks(for: anchor, in: sourceMap) {
            let text = block.normalizedText
            if let range = text.range(of: selected, options: [.caseInsensitive, .diacriticInsensitive]) {
                matches.append((block, range))
            }
        }

        if matches.count == 1 { return matches[0] }

        let sameHeading = matches.filter { $0.0.headingId == anchor.headingId && anchor.headingId != nil }
        return sameHeading.count == 1 ? sameHeading[0] : nil
    }

    private static func fuzzyMatch(for anchor: ReviewAnchor, in sourceMap: ReviewSourceMap) -> (block: ReviewSourceBlock, range: Range<String.Index>?, score: Double)? {
        let selected = normalizedSelection(anchor) ?? ""
        let prefix = ReviewSourceMapBuilder.normalizeText(anchor.prefix ?? "")
        let suffix = ReviewSourceMapBuilder.normalizeText(anchor.suffix ?? "")
        let context = [prefix, selected, suffix].filter { !$0.isEmpty }.joined(separator: " ")
        guard !context.isEmpty else { return nil }

        let scored = candidateBlocks(for: anchor, in: sourceMap).map { block -> (block: ReviewSourceBlock, range: Range<String.Index>?, score: Double) in
            let text = block.normalizedText
            let selectedScore = selected.isEmpty ? 0 : componentSimilarity(selected, text)
            let prefixScore = prefix.isEmpty ? 0 : componentSimilarity(prefix, text)
            let suffixScore = suffix.isEmpty ? 0 : componentSimilarity(suffix, text)
            let prefixComponent = prefix.isEmpty ? selectedScore : prefixScore
            let suffixComponent = suffix.isEmpty ? selectedScore : suffixScore
            let score = (selectedScore * 0.60) + (prefixComponent * 0.20) + (suffixComponent * 0.20)
            let range = selected.isEmpty ? nil : text.range(of: selected, options: [.caseInsensitive, .diacriticInsensitive])
            let headingBoost = block.headingId == anchor.headingId && anchor.headingId != nil ? 0.08 : 0
            let shortSelection = similarityTokenCount(selected) < 6
            let contextScore = max(prefixScore, suffixScore)
            let passesGate = selectedScore >= selectedFuzzyThreshold
                && (!shortSelection || contextScore >= shortSelectionContextThreshold)
            return (block, range, passesGate ? min(score + headingBoost, 1.0) : 0)
        }.sorted {
            if abs($0.score - $1.score) > 0.0001 { return $0.score > $1.score }
            if $0.block.headingId == anchor.headingId { return true }
            return $0.block.sourcepos < $1.block.sourcepos
        }

        guard let best = scored.first, best.score >= fuzzyThreshold else { return nil }
        if scored.count > 1, best.score - scored[1].score < tieBreakerMargin {
            return nil
        }
        return best
    }

    private static func sectionFallback(for anchor: ReviewAnchor, in sourceMap: ReviewSourceMap) -> ReviewSourceBlock? {
        guard let headingId = anchor.headingId else { return nil }
        return sourceMap.blocks.first { $0.headingId == headingId && $0.blockType != .heading }
            ?? sourceMap.blocks.first { $0.blockType == .heading && $0.headingId == headingId }
    }

    private static func candidateBlocks(for anchor: ReviewAnchor, in sourceMap: ReviewSourceMap) -> [ReviewSourceBlock] {
        let preferred: [ReviewAnchorBlockType]
        switch anchor.blockType {
        case .paragraph, .heading, .listItem, .quote, .multiBlock:
            preferred = [.paragraph, .heading, .listItem, .quote]
        case .code, .mermaid:
            preferred = [.code, .mermaid]
        case .table:
            preferred = [.table]
        case .math:
            preferred = [.math]
        case .image:
            preferred = [.image]
        case .frontmatter:
            preferred = [.frontmatter]
        }

        let filtered = sourceMap.blocks.filter { preferred.contains($0.blockType) }
        return filtered.isEmpty ? sourceMap.blocks : filtered
    }

    private static func anchorForMatch(
        _ original: ReviewAnchor,
        block: ReviewSourceBlock,
        range: Range<String.Index>?,
        confidence: ReviewAnchorConfidence
    ) -> ReviewAnchor {
        let offset = range.map { block.normalizedText.distance(from: block.normalizedText.startIndex, to: $0.lowerBound) }
        let length = range.map { block.normalizedText.distance(from: $0.lowerBound, to: $0.upperBound) }
        let text = original.selectedText
        let textAnchor = ReviewTextAnchor(
            sourcepos: block.sourcepos,
            headingId: block.headingId,
            blockTextHash: block.textHash,
            charOffsetInBlock: offset,
            charLength: length,
            selectedText: text,
            prefix: original.prefix,
            suffix: original.suffix,
            confidence: confidence,
            anchorNormalizerVersion: ReviewStateStore.anchorNormalizerVersion
        )

        switch block.blockType {
        case .heading:
            return .heading(textAnchor)
        case .listItem:
            return .listItem(textAnchor)
        case .quote:
            return .quote(textAnchor)
        case .code, .mermaid:
            return .code(ReviewCodeAnchor(
                sourcepos: block.sourcepos,
                headingId: block.headingId,
                codeLanguage: nil,
                startLine: sourceStartLine(block.sourcepos) ?? 1,
                endLine: sourceEndLine(block.sourcepos) ?? sourceStartLine(block.sourcepos) ?? 1,
                selectedText: text,
                prefix: original.prefix,
                suffix: original.suffix,
                confidence: confidence
            ))
        case .table:
            return .table(ReviewTableAnchor(
                sourcepos: block.sourcepos,
                headingId: block.headingId,
                rowIndex: 0,
                columnIndex: 0,
                charOffsetInCell: offset,
                charLength: length,
                selectedText: text,
                prefix: original.prefix,
                suffix: original.suffix,
                confidence: confidence
            ))
        case .image:
            return .image(ReviewImageAnchor(
                sourcepos: block.sourcepos,
                headingId: block.headingId,
                alt: text,
                confidence: confidence
            ))
        case .math:
            return .math(ReviewBlockAnchor(
                sourcepos: block.sourcepos,
                headingId: block.headingId,
                blockTextHash: block.textHash,
                selectedText: text,
                confidence: confidence
            ))
        case .frontmatter:
            return .frontmatter(ReviewBlockAnchor(
                sourcepos: block.sourcepos,
                headingId: block.headingId,
                blockTextHash: block.textHash,
                selectedText: text,
                confidence: confidence
            ))
        case .paragraph, .multiBlock:
            return .paragraph(textAnchor)
        }
    }

    private static func anchorForSectionFallback(_ original: ReviewAnchor, block: ReviewSourceBlock) -> ReviewAnchor {
        .paragraph(ReviewTextAnchor(
            sourcepos: block.sourcepos,
            headingId: block.headingId,
            blockTextHash: block.textHash,
            selectedText: original.selectedText,
            prefix: original.prefix,
            suffix: original.suffix,
            confidence: .section,
            anchorNormalizerVersion: ReviewStateStore.anchorNormalizerVersion
        ))
    }

    private static func orphanAnchor(from original: ReviewAnchor) -> ReviewAnchor {
        .paragraph(ReviewTextAnchor(
            sourcepos: original.sourcepos,
            headingId: original.headingId,
            selectedText: original.selectedText,
            prefix: original.prefix,
            suffix: original.suffix,
            confidence: .orphan,
            anchorNormalizerVersion: ReviewStateStore.anchorNormalizerVersion
        ))
    }

    private static func normalizedSelection(_ anchor: ReviewAnchor) -> String? {
        guard let selected = anchor.selectedText else { return nil }
        let normalized = ReviewSourceMapBuilder.normalizeText(selected)
        return normalized.isEmpty ? nil : normalized
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(ngrams(for: lhs))
        let right = Set(ngrams(for: rhs))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let intersection = left.intersection(right).count
        return Double(2 * intersection) / Double(left.count + right.count)
    }

    private static func componentSimilarity(_ component: String, _ text: String) -> Double {
        if text.range(of: component, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return 1
        }
        let diceScore = similarity(component, text)
        guard containsCJK(component) else { return diceScore }
        return max(diceScore, containmentRecall(component, text))
    }

    private static func containmentRecall(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(ngrams(for: lhs))
        let right = Set(ngrams(for: rhs))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(left.count)
    }

    private static func ngrams(for text: String) -> [String] {
        let normalized = ReviewSourceMapBuilder.normalizeText(text).lowercased()
        let (words, cjkRuns) = tokenizeForSimilarity(normalized)
        var grams: [String] = []
        if words.count >= 3 {
            grams.append(contentsOf: stride(from: 0, through: words.count - 3, by: 1).map {
                words[$0..<$0 + 3].joined(separator: " ")
            })
        } else {
            grams.append(contentsOf: words)
        }
        for run in cjkRuns {
            grams.append(contentsOf: characterNgrams(run, sizes: [2, 3]))
        }
        if !grams.isEmpty { return grams }

        let scalars = Array(normalized.unicodeScalars.filter { !$0.properties.isWhitespace })
        guard scalars.count >= 2 else { return scalars.map(String.init) }
        return stride(from: 0, to: scalars.count - 1, by: 1).map { index in
            String(String.UnicodeScalarView([scalars[index], scalars[index + 1]]))
        }
    }

    private static func tokenizeForSimilarity(_ text: String) -> (words: [String], cjkRuns: [String]) {
        var words: [String] = []
        var cjkRuns: [String] = []
        var wordScalars: [UnicodeScalar] = []
        var cjkScalars: [UnicodeScalar] = []

        func flushWord() {
            guard wordScalars.count >= 2 else {
                wordScalars.removeAll()
                return
            }
            words.append(String(String.UnicodeScalarView(wordScalars)))
            wordScalars.removeAll()
        }

        func flushCJK() {
            guard !cjkScalars.isEmpty else { return }
            cjkRuns.append(String(String.UnicodeScalarView(cjkScalars)))
            cjkScalars.removeAll()
        }

        for scalar in text.unicodeScalars {
            if isCJKScalar(scalar) {
                flushWord()
                cjkScalars.append(scalar)
            } else if CharacterSet.alphanumerics.contains(scalar) {
                flushCJK()
                wordScalars.append(scalar)
            } else {
                flushWord()
                flushCJK()
            }
        }
        flushWord()
        flushCJK()
        return (words, cjkRuns)
    }

    private static func similarityTokenCount(_ text: String) -> Int {
        let normalized = ReviewSourceMapBuilder.normalizeText(text).lowercased()
        let tokenized = tokenizeForSimilarity(normalized)
        return tokenized.words.count + tokenized.cjkRuns.reduce(0) { count, run in
            count + run.unicodeScalars.count
        }
    }

    private static func characterNgrams(_ text: String, sizes: [Int]) -> [String] {
        let scalars = Array(text.unicodeScalars)
        var grams: [String] = []
        for size in sizes where scalars.count >= size {
            grams.append(contentsOf: stride(from: 0, through: scalars.count - size, by: 1).map { index in
                String(String.UnicodeScalarView(Array(scalars[index..<index + size])))
            })
        }
        if grams.isEmpty {
            return scalars.map(String.init)
        }
        return grams
    }

    private static func isCJKScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isCJKScalar)
    }

    private static func sourceStartLine(_ sourcepos: String) -> Int? {
        guard let colon = sourcepos.firstIndex(of: ":") else { return nil }
        return Int(sourcepos[..<colon])
    }

    private static func sourceEndLine(_ sourcepos: String) -> Int? {
        guard let dash = sourcepos.firstIndex(of: "-") else { return nil }
        let rest = sourcepos[sourcepos.index(after: dash)...]
        guard let colon = rest.firstIndex(of: ":") else { return nil }
        return Int(rest[..<colon])
    }
}
