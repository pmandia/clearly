import Foundation

public enum ReviewAnchorConfidence: String, Codable, Equatable, Sendable {
    case exact
    case fuzzy
    case section
    case orphan
}

public enum ReviewAnchorBlockType: String, Codable, Equatable, Sendable {
    case paragraph
    case heading
    case listItem
    case quote
    case code
    case table
    case math
    case mermaid
    case image
    case frontmatter
    case multiBlock
}

public struct ReviewTextAnchor: Codable, Equatable, Sendable {
    public var sourcepos: String
    public var headingId: String?
    public var blockTextHash: String?
    public var charOffsetInBlock: Int?
    public var charLength: Int?
    public var selectedText: String?
    public var prefix: String?
    public var suffix: String?
    public var confidence: ReviewAnchorConfidence
    public var anchorNormalizerVersion: Int

    public init(
        sourcepos: String,
        headingId: String? = nil,
        blockTextHash: String? = nil,
        charOffsetInBlock: Int? = nil,
        charLength: Int? = nil,
        selectedText: String? = nil,
        prefix: String? = nil,
        suffix: String? = nil,
        confidence: ReviewAnchorConfidence = .exact,
        anchorNormalizerVersion: Int = ReviewStateStore.anchorNormalizerVersion
    ) {
        self.sourcepos = sourcepos
        self.headingId = headingId
        self.blockTextHash = blockTextHash
        self.charOffsetInBlock = charOffsetInBlock
        self.charLength = charLength
        self.selectedText = selectedText
        self.prefix = prefix
        self.suffix = suffix
        self.confidence = confidence
        self.anchorNormalizerVersion = anchorNormalizerVersion
    }
}

public struct ReviewCodeAnchor: Codable, Equatable, Sendable {
    public var sourcepos: String
    public var headingId: String?
    public var codeLanguage: String?
    public var startLine: Int
    public var endLine: Int
    public var startColumn: Int?
    public var endColumn: Int?
    public var selectedText: String?
    public var prefix: String?
    public var suffix: String?
    public var confidence: ReviewAnchorConfidence
    public var anchorNormalizerVersion: Int

    public init(
        sourcepos: String,
        headingId: String? = nil,
        codeLanguage: String? = nil,
        startLine: Int,
        endLine: Int,
        startColumn: Int? = nil,
        endColumn: Int? = nil,
        selectedText: String? = nil,
        prefix: String? = nil,
        suffix: String? = nil,
        confidence: ReviewAnchorConfidence = .exact,
        anchorNormalizerVersion: Int = ReviewStateStore.anchorNormalizerVersion
    ) {
        self.sourcepos = sourcepos
        self.headingId = headingId
        self.codeLanguage = codeLanguage
        self.startLine = startLine
        self.endLine = endLine
        self.startColumn = startColumn
        self.endColumn = endColumn
        self.selectedText = selectedText
        self.prefix = prefix
        self.suffix = suffix
        self.confidence = confidence
        self.anchorNormalizerVersion = anchorNormalizerVersion
    }
}

public struct ReviewTableAnchor: Codable, Equatable, Sendable {
    public var sourcepos: String
    public var headingId: String?
    public var rowIndex: Int
    public var columnIndex: Int
    public var charOffsetInCell: Int?
    public var charLength: Int?
    public var selectedText: String?
    public var prefix: String?
    public var suffix: String?
    public var multiCell: Bool
    public var confidence: ReviewAnchorConfidence
    public var anchorNormalizerVersion: Int

    public init(
        sourcepos: String,
        headingId: String? = nil,
        rowIndex: Int,
        columnIndex: Int,
        charOffsetInCell: Int? = nil,
        charLength: Int? = nil,
        selectedText: String? = nil,
        prefix: String? = nil,
        suffix: String? = nil,
        multiCell: Bool = false,
        confidence: ReviewAnchorConfidence = .exact,
        anchorNormalizerVersion: Int = ReviewStateStore.anchorNormalizerVersion
    ) {
        self.sourcepos = sourcepos
        self.headingId = headingId
        self.rowIndex = rowIndex
        self.columnIndex = columnIndex
        self.charOffsetInCell = charOffsetInCell
        self.charLength = charLength
        self.selectedText = selectedText
        self.prefix = prefix
        self.suffix = suffix
        self.multiCell = multiCell
        self.confidence = confidence
        self.anchorNormalizerVersion = anchorNormalizerVersion
    }
}

public struct ReviewBlockAnchor: Codable, Equatable, Sendable {
    public var sourcepos: String
    public var headingId: String?
    public var blockTextHash: String?
    public var selectedText: String?
    public var confidence: ReviewAnchorConfidence
    public var anchorNormalizerVersion: Int

    public init(
        sourcepos: String,
        headingId: String? = nil,
        blockTextHash: String? = nil,
        selectedText: String? = nil,
        confidence: ReviewAnchorConfidence = .exact,
        anchorNormalizerVersion: Int = ReviewStateStore.anchorNormalizerVersion
    ) {
        self.sourcepos = sourcepos
        self.headingId = headingId
        self.blockTextHash = blockTextHash
        self.selectedText = selectedText
        self.confidence = confidence
        self.anchorNormalizerVersion = anchorNormalizerVersion
    }
}

public struct ReviewImageAnchor: Codable, Equatable, Sendable {
    public var sourcepos: String
    public var headingId: String?
    public var src: String?
    public var alt: String?
    public var confidence: ReviewAnchorConfidence
    public var anchorNormalizerVersion: Int

    public init(
        sourcepos: String,
        headingId: String? = nil,
        src: String? = nil,
        alt: String? = nil,
        confidence: ReviewAnchorConfidence = .exact,
        anchorNormalizerVersion: Int = ReviewStateStore.anchorNormalizerVersion
    ) {
        self.sourcepos = sourcepos
        self.headingId = headingId
        self.src = src
        self.alt = alt
        self.confidence = confidence
        self.anchorNormalizerVersion = anchorNormalizerVersion
    }
}

public struct ReviewMultiBlockAnchor: Codable, Equatable, Sendable {
    public var sourcepos: String
    public var headingId: String?
    public var selectedText: String?
    public var blockSourcePositions: [String]
    public var primaryBlock: ReviewTextAnchor
    public var confidence: ReviewAnchorConfidence
    public var anchorNormalizerVersion: Int

    public init(
        sourcepos: String,
        headingId: String? = nil,
        selectedText: String? = nil,
        blockSourcePositions: [String],
        primaryBlock: ReviewTextAnchor,
        confidence: ReviewAnchorConfidence = .exact,
        anchorNormalizerVersion: Int = ReviewStateStore.anchorNormalizerVersion
    ) {
        self.sourcepos = sourcepos
        self.headingId = headingId
        self.selectedText = selectedText
        self.blockSourcePositions = blockSourcePositions
        self.primaryBlock = primaryBlock
        self.confidence = confidence
        self.anchorNormalizerVersion = anchorNormalizerVersion
    }
}

public enum ReviewAnchor: Equatable, Sendable {
    case paragraph(ReviewTextAnchor)
    case heading(ReviewTextAnchor)
    case listItem(ReviewTextAnchor)
    case quote(ReviewTextAnchor)
    case code(ReviewCodeAnchor)
    case table(ReviewTableAnchor)
    case math(ReviewBlockAnchor)
    case mermaid(ReviewBlockAnchor)
    case image(ReviewImageAnchor)
    case frontmatter(ReviewBlockAnchor)
    case multiBlock(ReviewMultiBlockAnchor)

    public var blockType: ReviewAnchorBlockType {
        switch self {
        case .paragraph: return .paragraph
        case .heading: return .heading
        case .listItem: return .listItem
        case .quote: return .quote
        case .code: return .code
        case .table: return .table
        case .math: return .math
        case .mermaid: return .mermaid
        case .image: return .image
        case .frontmatter: return .frontmatter
        case .multiBlock: return .multiBlock
        }
    }

    public var sourcepos: String {
        switch self {
        case .paragraph(let anchor), .heading(let anchor), .listItem(let anchor), .quote(let anchor):
            return anchor.sourcepos
        case .code(let anchor):
            return anchor.sourcepos
        case .table(let anchor):
            return anchor.sourcepos
        case .math(let anchor), .mermaid(let anchor), .frontmatter(let anchor):
            return anchor.sourcepos
        case .image(let anchor):
            return anchor.sourcepos
        case .multiBlock(let anchor):
            return anchor.sourcepos
        }
    }

    public var headingId: String? {
        switch self {
        case .paragraph(let anchor), .heading(let anchor), .listItem(let anchor), .quote(let anchor):
            return anchor.headingId
        case .code(let anchor):
            return anchor.headingId
        case .table(let anchor):
            return anchor.headingId
        case .math(let anchor), .mermaid(let anchor), .frontmatter(let anchor):
            return anchor.headingId
        case .image(let anchor):
            return anchor.headingId
        case .multiBlock(let anchor):
            return anchor.headingId
        }
    }

    public var selectedText: String? {
        switch self {
        case .paragraph(let anchor), .heading(let anchor), .listItem(let anchor), .quote(let anchor):
            return anchor.selectedText
        case .code(let anchor):
            return anchor.selectedText
        case .table(let anchor):
            return anchor.selectedText
        case .math(let anchor), .mermaid(let anchor), .frontmatter(let anchor):
            return anchor.selectedText
        case .image(let anchor):
            return anchor.alt
        case .multiBlock(let anchor):
            return anchor.selectedText
        }
    }

    public var prefix: String? {
        switch self {
        case .paragraph(let anchor), .heading(let anchor), .listItem(let anchor), .quote(let anchor):
            return anchor.prefix
        case .code(let anchor):
            return anchor.prefix
        case .table(let anchor):
            return anchor.prefix
        case .multiBlock(let anchor):
            return anchor.primaryBlock.prefix
        default:
            return nil
        }
    }

    public var suffix: String? {
        switch self {
        case .paragraph(let anchor), .heading(let anchor), .listItem(let anchor), .quote(let anchor):
            return anchor.suffix
        case .code(let anchor):
            return anchor.suffix
        case .table(let anchor):
            return anchor.suffix
        case .multiBlock(let anchor):
            return anchor.primaryBlock.suffix
        default:
            return nil
        }
    }

    public var confidence: ReviewAnchorConfidence {
        switch self {
        case .paragraph(let anchor), .heading(let anchor), .listItem(let anchor), .quote(let anchor):
            return anchor.confidence
        case .code(let anchor):
            return anchor.confidence
        case .table(let anchor):
            return anchor.confidence
        case .math(let anchor), .mermaid(let anchor), .frontmatter(let anchor):
            return anchor.confidence
        case .image(let anchor):
            return anchor.confidence
        case .multiBlock(let anchor):
            return anchor.confidence
        }
    }
}

extension ReviewAnchor: Codable {
    private enum CodingKeys: String, CodingKey {
        case blockType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let blockType = try container.decode(ReviewAnchorBlockType.self, forKey: .blockType)
        switch blockType {
        case .paragraph:
            self = .paragraph(try ReviewTextAnchor(from: decoder))
        case .heading:
            self = .heading(try ReviewTextAnchor(from: decoder))
        case .listItem:
            self = .listItem(try ReviewTextAnchor(from: decoder))
        case .quote:
            self = .quote(try ReviewTextAnchor(from: decoder))
        case .code:
            self = .code(try ReviewCodeAnchor(from: decoder))
        case .table:
            self = .table(try ReviewTableAnchor(from: decoder))
        case .math:
            self = .math(try ReviewBlockAnchor(from: decoder))
        case .mermaid:
            self = .mermaid(try ReviewBlockAnchor(from: decoder))
        case .image:
            self = .image(try ReviewImageAnchor(from: decoder))
        case .frontmatter:
            self = .frontmatter(try ReviewBlockAnchor(from: decoder))
        case .multiBlock:
            self = .multiBlock(try ReviewMultiBlockAnchor(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(blockType, forKey: .blockType)
        switch self {
        case .paragraph(let anchor), .heading(let anchor), .listItem(let anchor), .quote(let anchor):
            try anchor.encode(to: encoder)
        case .code(let anchor):
            try anchor.encode(to: encoder)
        case .table(let anchor):
            try anchor.encode(to: encoder)
        case .math(let anchor), .mermaid(let anchor), .frontmatter(let anchor):
            try anchor.encode(to: encoder)
        case .image(let anchor):
            try anchor.encode(to: encoder)
        case .multiBlock(let anchor):
            try anchor.encode(to: encoder)
        }
    }
}
