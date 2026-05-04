import XCTest
@testable import ClearlyCore

final class ReviewSnapshotTests: XCTestCase {
    func testSnapshotBuildsSanitizedHTMLAndSourceMap() throws {
        let markdown = """
        # Rollout Plan

        This will improve onboarding before launch.

        ```swift
        let answer = 42
        ```

        | Area | Owner |
        | --- | --- |
        | Docs | Jane |
        """

        let snapshot = ReviewSnapshotRenderer.render(markdown: markdown, title: "proposal.md")

        XCTAssertTrue(snapshot.html.contains("<!doctype html>"))
        XCTAssertTrue(snapshot.html.contains("noindex,nofollow"))
        XCTAssertTrue(snapshot.contentHash.hasPrefix("sha256:"))
        XCTAssertEqual(snapshot.sourceMap.schemaVersion, 1)
        XCTAssertTrue(snapshot.sourceMap.blocks.contains { $0.blockType == .paragraph && $0.normalizedText.contains("improve onboarding") })
        XCTAssertTrue(snapshot.sourceMap.blocks.contains { $0.blockType == .code })
        XCTAssertTrue(snapshot.sourceMap.blocks.contains { $0.blockType == .table })
        XCTAssertEqual(snapshot.sourceMap.headings.first?.headingId, "rollout-plan")
    }

    func testSanitizerRemovesScriptsHandlersAndUnsafeURLs() {
        let dirty = #"""
        <p data-sourcepos="1:1-1:12" onclick="alert(1)"><a href="javascript:alert(1)">bad</a></p>
        <script>alert(1)</script>
        <img data-sourcepos="2:1-2:9" src="data:text/html,bad" onload="alert(1)">
        """#

        let clean = ReviewSnapshotSanitizer.sanitize(dirty)

        XCTAssertFalse(clean.localizedCaseInsensitiveContains("<script"))
        XCTAssertFalse(clean.localizedCaseInsensitiveContains("onclick"))
        XCTAssertFalse(clean.localizedCaseInsensitiveContains("onload"))
        XCTAssertFalse(clean.localizedCaseInsensitiveContains("javascript:"))
        XCTAssertFalse(clean.localizedCaseInsensitiveContains("data:text/html"))
        XCTAssertTrue(clean.contains("data-sourcepos"))
    }

    func testAnchorUnionRoundTripsBlockType() throws {
        let anchor = ReviewAnchor.paragraph(ReviewTextAnchor(
            sourcepos: "3:1-3:49",
            headingId: "rollout-plan",
            blockTextHash: "sha256:abc",
            charOffsetInBlock: 10,
            charLength: 12,
            selectedText: "improve onboarding",
            prefix: "This will",
            suffix: "before launch."
        ))

        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(ReviewAnchor.self, from: data)

        XCTAssertEqual(decoded.blockType, .paragraph)
        XCTAssertEqual(decoded, anchor)
    }

    func testRemapperUsesExactSelectedTextBeforeFallbacks() {
        let sourceMap = ReviewSourceMap(blocks: [
            ReviewSourceBlock(
                blockId: "blk_1",
                sourcepos: "9:1-9:80",
                headingId: "rollout-plan",
                blockType: .paragraph,
                textHash: ReviewSourceMapBuilder.normalizedTextHash("The updated plan will improve onboarding before launch."),
                normalizedText: "The updated plan will improve onboarding before launch.",
                charLength: 55
            )
        ], headings: [])
        let comment = ReviewComment(
            id: "c_1",
            version: 1,
            author: "Jane",
            authorId: "guest_1",
            body: "Please keep this concrete.",
            selectedText: "improve onboarding",
            anchor: .paragraph(ReviewTextAnchor(
                sourcepos: "3:1-3:49",
                headingId: "rollout-plan",
                selectedText: "improve onboarding",
                prefix: "This will",
                suffix: "before launch."
            ))
        )

        let result = ReviewAnchorRemapper.remap(comment: comment, into: sourceMap)

        XCTAssertEqual(result.confidence, .exact)
        XCTAssertEqual(result.anchor.sourcepos, "9:1-9:80")
    }

    func testRemapperOrphansWhenNoMatchExists() {
        let sourceMap = ReviewSourceMap(blocks: [
            ReviewSourceBlock(
                blockId: "blk_1",
                sourcepos: "9:1-9:20",
                headingId: "pricing",
                blockType: .paragraph,
                textHash: ReviewSourceMapBuilder.normalizedTextHash("Unrelated text"),
                normalizedText: "Unrelated text",
                charLength: 14
            )
        ], headings: [])
        let anchor = ReviewAnchor.paragraph(ReviewTextAnchor(
            sourcepos: "3:1-3:49",
            headingId: "rollout-plan",
            selectedText: "improve onboarding",
            prefix: "This will",
            suffix: "before launch."
        ))

        let result = ReviewAnchorRemapper.remap(anchor: anchor, into: sourceMap)

        XCTAssertEqual(result.confidence, .orphan)
        XCTAssertEqual(result.anchor.sourcepos, "3:1-3:49")
        XCTAssertEqual(result.anchor.confidence, .orphan)
    }

    func testRemapperUsesCJKCharacterNgramsForFuzzyMatches() {
        let sourceMap = ReviewSourceMap(blocks: [
            ReviewSourceBlock(
                blockId: "blk_1",
                sourcepos: "9:1-9:40",
                headingId: "plan",
                blockType: .paragraph,
                textHash: ReviewSourceMapBuilder.normalizedTextHash("これは重要な計画を確認しました。してください"),
                normalizedText: "これは重要な計画を確認しました。してください",
                charLength: 21
            )
        ], headings: [])
        let anchor = ReviewAnchor.paragraph(ReviewTextAnchor(
            sourcepos: "3:1-3:40",
            headingId: "plan",
            selectedText: "重要な計画を確認する",
            prefix: "これは",
            suffix: "してください"
        ))

        let result = ReviewAnchorRemapper.remap(anchor: anchor, into: sourceMap)

        XCTAssertEqual(result.confidence, .fuzzy)
        XCTAssertEqual(result.anchor.sourcepos, "9:1-9:40")
    }
}
