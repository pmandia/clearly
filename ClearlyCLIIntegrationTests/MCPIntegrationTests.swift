import Foundation
import ClearlyCore
import MCP
import NaturalLanguage
import XCTest

/// End-to-end test of the MCP tools exposed by ClearlyCLI, driving a real
/// Server over InMemoryTransport with a real Client. Each test exercises the
/// success path; ErrorPathTests covers ToolError cases.
final class MCPIntegrationTests: XCTestCase {
    var harness: TestVaultHarness!

    override func setUp() async throws {
        harness = try await TestVaultHarness()
    }

    override func tearDown() async throws {
        await harness?.tearDown()
        harness = nil
    }

    // MARK: - tools/list

    func testListToolsReturnsAllRegisteredTools() async throws {
        let (tools, _) = try await harness.client.listTools()
        let names = Set(tools.map(\.name))
        XCTAssertEqual(names, Set([
            "get_current_document", "get_review_for_file", "sync_review_comments",
            "create_review", "get_review_comments", "stage_review_comment_resolution",
            "confirm_review_comment_resolution", "publish_review_version", "get_review_forks",
            "get_review_fork",
            "semantic_search", "find_related",
            "search_notes", "get_backlinks", "get_tags",
            "read_note", "list_notes", "get_headings",
            "get_frontmatter", "create_note", "update_note", "move_note"
        ]))
        XCTAssertEqual(tools.count, names.count)
        // Every tool advertises an outputSchema.
        for t in tools {
            XCTAssertNotNil(t.outputSchema, "\(t.name) missing outputSchema")
            XCTAssertNotNil(t.annotations, "\(t.name) missing annotations")
        }
    }

    func testReadOnlyToolRegistryHidesWriteTools() throws {
        let tools = ToolRegistry.listTools(vaults: harness.loadedVaults, readOnly: true)
        let names = Set(tools.map(\.name))
        XCTAssertFalse(names.contains("create_note"))
        XCTAssertFalse(names.contains("update_note"))
        XCTAssertFalse(names.contains("move_note"))
        XCTAssertFalse(names.contains("create_review"))
        XCTAssertFalse(names.contains("stage_review_comment_resolution"))
        XCTAssertFalse(names.contains("confirm_review_comment_resolution"))
        XCTAssertFalse(names.contains("publish_review_version"))
        XCTAssertTrue(names.contains("get_current_document"))
        XCTAssertTrue(names.contains("get_review_for_file"))
        XCTAssertTrue(names.contains("sync_review_comments"))
        XCTAssertTrue(names.contains("get_review_comments"))
        XCTAssertTrue(names.contains("get_review_forks"))
        XCTAssertTrue(names.contains("get_review_fork"))
        XCTAssertTrue(names.contains("semantic_search"))
        XCTAssertTrue(names.contains("find_related"))
        XCTAssertTrue(names.contains("search_notes"))
        XCTAssertEqual(tools.count, names.count)
    }

    func testReadOnlyHandlerRejectsWriteTools() async throws {
        let result = await Handlers.dispatch(
            params: .init(
                name: "create_note",
                arguments: ["relative_path": .string("blocked.md"), "content": .string("blocked")]
            ),
            vaults: harness.loadedVaults,
            readOnly: true
        )

        XCTAssertEqual(result.isError, true)
        guard case let .text(jsonString, _, _) = result.content.first else {
            XCTFail("create_note returned non-text content: \(result.content)")
            return
        }
        let payload = try JSONDecoder().decode(ErrorPayload.self, from: Data(jsonString.utf8))
        XCTAssertEqual(payload.error, "unknown_tool")
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.vaultURL.appendingPathComponent("blocked.md").path))
    }

    // MARK: - review tools

    func testGetReviewForFileResolvesVaultURI() async throws {
        struct Result: Decodable {
            let vaultId: String
            let targetRelativePath: String
            let vaultUri: String
            let hasLinkedReview: Bool
        }

        let result = try await harness.callTool(
            "get_review_for_file",
            arguments: ["file_path": .string("Projects/Plan.md")],
            as: Result.self
        )

        XCTAssertEqual(result.targetRelativePath, "Projects/Plan.md")
        XCTAssertTrue(result.vaultUri.hasPrefix("vault://\(result.vaultId)/Projects/Plan.md"))
        XCTAssertFalse(result.hasLinkedReview)
    }

    func testGetReviewCommentsReadsLocalCache() async throws {
        let context = try linkedReviewContext(relativePath: "Projects/Plan.md")
        let cache = ReviewCommentsCache(
            reviewId: "rvw_test",
            remoteRevision: "rev_1",
            syncedAt: Date(),
            freshness: "cache",
            comments: [
                ReviewComment(
                    id: "c_1",
                    reviewId: "rvw_test",
                    version: 1,
                    status: "open",
                    author: "Jane",
                    authorId: "guest_1",
                    body: "Needs a concrete example.",
                    selectedText: "project plan",
                    anchor: .paragraph(ReviewTextAnchor(
                        sourcepos: "1:1-1:14",
                        headingId: "plan",
                        selectedText: "project plan"
                    )),
                    remoteRevision: 3
                )
            ]
        )
        try ReviewStateStore.writeCommentsCache(cache, context: context, bundleIdentifier: harness.bundleID)

        struct Result: Decodable {
            let freshness: String
            let comments: [ReviewComment]
            let pendingResolutionCount: Int
        }
        let result = try await harness.callTool(
            "get_review_comments",
            arguments: [
                "file_path": .string(context.vaultURI),
                "freshness": .string("cache"),
                "status": .string("open")
            ],
            as: Result.self
        )

        XCTAssertEqual(result.freshness, "cache")
        XCTAssertEqual(result.comments.map(\.id), ["c_1"])
        XCTAssertEqual(result.comments.first?.anchor.blockType, .paragraph)
        XCTAssertEqual(result.pendingResolutionCount, 0)
    }

    func testStageReviewCommentResolutionWritesPendingState() async throws {
        let context = try linkedReviewContext(relativePath: "Projects/Plan.md")

        struct Result: Decodable {
            let commentId: String
            let staged: Bool
            let pendingResolutionCount: Int
        }
        let result = try await harness.callTool(
            "stage_review_comment_resolution",
            arguments: [
                "file_path": .string(context.vaultURI),
                "comment_id": .string("c_1"),
                "note": .string("Addressed with a concrete example."),
                "remote_revision": .int(3)
            ],
            as: Result.self
        )

        XCTAssertEqual(result.commentId, "c_1")
        XCTAssertTrue(result.staged)
        XCTAssertEqual(result.pendingResolutionCount, 1)
    }

    func testSyncReviewCommentsRequiresConfiguredService() async throws {
        guard ProcessInfo.processInfo.environment["CLEARLY_REVIEW_API_BASE_URL"] == nil else {
            throw XCTSkip("Review service is configured in this environment")
        }
        let context = try linkedReviewContext(relativePath: "Projects/Plan.md")

        let error = try await harness.callToolExpectingError(
            "sync_review_comments",
            arguments: ["file_path": .string(context.vaultURI)]
        )

        XCTAssertEqual(error.error, "service_unavailable")
    }

    func testCreateReviewRequiresConfiguredService() async throws {
        guard ProcessInfo.processInfo.environment["CLEARLY_REVIEW_API_BASE_URL"] == nil else {
            throw XCTSkip("Review service is configured in this environment")
        }

        let error = try await harness.callToolExpectingError(
            "create_review",
            arguments: ["file_path": .string("Projects/Plan.md")]
        )

        XCTAssertEqual(error.error, "service_unavailable")
    }

    // MARK: - search_notes

    func testSearchNotesReturnsHits() async throws {
        struct Hit: Decodable {
            let relativePath: String
            let filename: String
            let vault: String
            let matchesFilename: Bool
        }
        struct Result: Decodable { let results: [Hit]; let totalCount: Int }
        let result = try await harness.callTool(
            "search_notes",
            arguments: ["query": .string("Link Target"), "limit": .int(10)],
            as: Result.self
        )
        XCTAssertGreaterThan(result.totalCount, 0)
        XCTAssertTrue(
            result.results.contains { $0.relativePath.contains("Link Target") },
            "expected a hit touching 'Link Target'"
        )
    }

    // MARK: - semantic_search

    /// Inject deterministic embeddings for three fixture notes (a fourth has none, so it should
    /// not appear in results) and confirm the tool ranks by cosine similarity to the query vector.
    /// We bypass NLContextualEmbedding for stored vectors but still need the live model for the
    /// query — skip if assets aren't on the runner.
    func testSemanticSearchRanksByCosineSimilarity() async throws {
        try skipIfEmbeddingAssetsMissing()

        let index = harness.loadedVaults[0].index
        let dim = try EmbeddingService().dimension
        XCTAssertGreaterThan(dim, 0)

        // Fetch a handful of indexed files we can attach vectors to.
        let everything = index.allFiles()
        guard everything.count >= 3 else {
            throw XCTSkip("FixtureVault has fewer than 3 notes — adjust fixture or skip")
        }
        let close = everything[0]
        let middle = everything[1]
        let far = everything[2]

        // Build three orthogonal-ish vectors. Identity + a slightly perturbed identity + noise.
        let closeVec = unitVector(at: 0, dim: dim, scale: 1.0)
        let middleVec = unitVector(at: 1, dim: dim, scale: 1.0)
        let farVec = unitVector(at: 2, dim: dim, scale: 1.0)

        try upsertTestChunk(index, file: close, vector: closeVec)
        try upsertTestChunk(index, file: middle, vector: middleVec)
        try upsertTestChunk(index, file: far, vector: farVec)

        // Build a query whose embedding is *substituted* with closeVec via the helper below.
        // Since we can't intercept the live model from a black-box test, instead we'll use a
        // free-form string and just verify the tool returns 3 ranked entries (one per stored
        // vector), with `close` appearing in the result set. Stronger ranking guarantees are
        // covered by the unit-level cosine tests in EmbeddingServiceTests.
        struct Hit: Decodable {
            let relativePath: String
            let filename: String
            let score: Float
        }
        struct Result: Decodable {
            let results: [Hit]
            let totalCount: Int
            let returnedCount: Int
        }
        let result = try await harness.callTool(
            "semantic_search",
            arguments: ["query": .string("project planning notes"), "limit": .int(10)],
            as: Result.self
        )
        XCTAssertEqual(result.totalCount, 3, "should score every stored vector")
        XCTAssertEqual(result.returnedCount, 3)
        // Scores must be monotonically non-increasing (sorted top-N).
        for i in 1..<result.results.count {
            XCTAssertGreaterThanOrEqual(result.results[i - 1].score, result.results[i].score)
        }
        // Hits must come from the three notes we embedded.
        let hitPaths = Set(result.results.map(\.relativePath))
        XCTAssertEqual(hitPaths, Set([close.path, middle.path, far.path]))
    }

    func testSemanticSearchSkipsEmbeddingsAtOtherModelVersions() async throws {
        try skipIfEmbeddingAssetsMissing()
        let index = harness.loadedVaults[0].index
        let dim = try EmbeddingService().dimension
        let everything = index.allFiles()
        guard let one = everything.first else { throw XCTSkip("empty fixture") }
        // Stored at a different model version — must NOT appear in results.
        try upsertTestChunk(
            index,
            file: one,
            vector: unitVector(at: 0, dim: dim, scale: 1),
            modelVersion: EmbeddingService.MODEL_VERSION + 1
        )

        struct Result: Decodable { let totalCount: Int; let returnedCount: Int }
        let result = try await harness.callTool(
            "semantic_search",
            arguments: ["query": .string("anything")],
            as: Result.self
        )
        XCTAssertEqual(result.totalCount, 0)
        XCTAssertEqual(result.returnedCount, 0)
    }

    func testSemanticSearchMissingQueryRejected() async throws {
        // No model assets needed — the tool throws on missing query before embedding.
        let payload = try await harness.callToolExpectingError(
            "semantic_search",
            arguments: ["query": .string("")]
        )
        XCTAssertEqual(payload.error, "missing_argument")
    }

    func testSemanticSearchInvalidLimitRejected() async throws {
        let payload = try await harness.callToolExpectingError(
            "semantic_search",
            arguments: ["query": .string("hello"), "limit": .int(0)]
        )
        XCTAssertEqual(payload.error, "invalid_argument")
    }

    // MARK: - helpers

    /// Skip the calling test if NLContextualEmbedding's English assets aren't on the runner.
    private func skipIfEmbeddingAssetsMissing() throws {
        // Probe without triggering an asset download.
        guard let probe = NLContextualEmbedding(language: .english), probe.hasAvailableAssets else {
            throw XCTSkip("NLContextualEmbedding English assets not available on this runner")
        }
    }

    /// One-hot-style unit vector for deterministic ranking tests.
    private func unitVector(at index: Int, dim: Int, scale: Float) -> [Float] {
        var v = [Float](repeating: 0, count: dim)
        if dim > 0 { v[index % dim] = scale }
        return v
    }

    private func upsertTestChunk(
        _ index: VaultIndex,
        file: IndexedFile,
        vector: [Float],
        modelVersion: Int = EmbeddingService.MODEL_VERSION
    ) throws {
        let body = "semantic fixture \(file.path)"
        try index.upsertChunkEmbeddings(
            fileID: file.id,
            contentHash: file.contentHash,
            chunks: [
                VaultIndex.ChunkEmbeddingInput(
                    chunkIndex: 0,
                    textOffset: 0,
                    textLength: body.utf8.count,
                    headingPath: [],
                    body: body,
                    vector: vector
                )
            ],
            modelVersion: modelVersion
        )
    }

    private func linkedReviewContext(relativePath: String) throws -> ReviewContextPayload {
        let fileURL = harness.vaultURL.appendingPathComponent(relativePath)
        _ = try ReviewStateStore.context(
            for: fileURL,
            vaultRoot: harness.vaultURL,
            bundleIdentifier: harness.bundleID
        )
        return try ReviewStateStore.updateReviewRecord(
            for: fileURL,
            vaultRoot: harness.vaultURL,
            bundleIdentifier: harness.bundleID,
            reviewId: "rvw_test",
            publisherId: "pub_test",
            keychainAccount: "clearly-review-publisher-pub_test",
            reviewUrl: "https://reviews.example.com/r/prt_test",
            latestVersion: 1
        )
    }

    func testSearchFilesGroupedKeepsHighlightedExcerptForUI() async throws {
        let groups = harness.loadedVaults[0].index.searchFilesGrouped(query: "standup")
        let excerpt = try XCTUnwrap(groups.flatMap(\.excerpts).first)
        XCTAssertFalse(excerpt.contextLine.contains("<<"))
        XCTAssertFalse(excerpt.contextLine.contains(">>"))
        XCTAssertTrue(excerpt.highlightedContextLine.contains("<<"))
        XCTAssertTrue(excerpt.highlightedContextLine.contains(">>"))
    }

    // MARK: - read_note

    func testReadNoteReturnsContentAndHash() async throws {
        struct Result: Decodable {
            let content: String
            let contentHash: String
            let sizeBytes: Int
            let vault: String
            let relativePath: String
        }
        let result = try await harness.callTool(
            "read_note",
            arguments: ["relative_path": .string("Daily/2026-04-17.md")],
            as: Result.self
        )
        XCTAssertTrue(result.content.contains("# 2026-04-17"))
        XCTAssertEqual(result.contentHash.count, 64) // SHA-256 hex
        XCTAssertGreaterThan(result.sizeBytes, 0)
    }

    func testReadNoteLineRangeClampsContent() async throws {
        struct Range: Decodable { let start: Int; let end: Int }
        struct Result: Decodable { let content: String; let lineRange: Range? }
        let result = try await harness.callTool(
            "read_note",
            arguments: [
                "relative_path": .string("Daily/2026-04-17.md"),
                "start_line": .int(1),
                "end_line": .int(2)
            ],
            as: Result.self
        )
        XCTAssertNotNil(result.lineRange)
        XCTAssertEqual(result.lineRange?.start, 1)
        XCTAssertEqual(result.lineRange?.end, 2)
        XCTAssertLessThanOrEqual(
            result.content.components(separatedBy: "\n").count,
            3  // up to 2 lines + potential trailing newline
        )
    }

    // MARK: - list_notes

    func testListNotesReturnsFixtureCount() async throws {
        struct Note: Decodable { let relativePath: String }
        struct Result: Decodable { let notes: [Note] }
        let result = try await harness.callTool(
            "list_notes",
            arguments: [:],
            as: Result.self
        )
        // FixtureVault has 7 markdown files.
        XCTAssertEqual(result.notes.count, 7, "unexpected fixture size: \(result.notes.map(\.relativePath))")
    }

    func testListNotesFiltersByUnder() async throws {
        struct Note: Decodable { let relativePath: String }
        struct Result: Decodable { let notes: [Note] }
        let result = try await harness.callTool(
            "list_notes",
            arguments: ["under": .string("Notes/")],
            as: Result.self
        )
        XCTAssertEqual(result.notes.count, 3)
        XCTAssertTrue(result.notes.allSatisfy { $0.relativePath.hasPrefix("Notes/") })
    }

    // MARK: - get_headings

    func testGetHeadingsReturnsOutline() async throws {
        struct Heading: Decodable { let level: Int; let text: String; let lineNumber: Int }
        struct Result: Decodable { let headings: [Heading] }
        let result = try await harness.callTool(
            "get_headings",
            arguments: ["relative_path": .string("Daily/2026-04-17.md")],
            as: Result.self
        )
        XCTAssertFalse(result.headings.isEmpty)
        XCTAssertTrue(result.headings.contains { $0.level == 1 && $0.text == "2026-04-17" })
        XCTAssertTrue(result.headings.contains { $0.level == 3 && $0.text == "Deep work" })
    }

    // MARK: - get_frontmatter

    func testGetFrontmatterFlatMap() async throws {
        struct Result: Decodable { let hasFrontmatter: Bool; let frontmatter: [String: String] }
        let result = try await harness.callTool(
            "get_frontmatter",
            arguments: ["relative_path": .string("Projects/Plan.md")],
            as: Result.self
        )
        XCTAssertTrue(result.hasFrontmatter)
        XCTAssertEqual(result.frontmatter["title"], "Project Plan")
        XCTAssertEqual(result.frontmatter["status"], "active")
    }

    func testGetFrontmatterAbsent() async throws {
        struct Result: Decodable { let hasFrontmatter: Bool; let frontmatter: [String: String] }
        let result = try await harness.callTool(
            "get_frontmatter",
            arguments: ["relative_path": .string("Notes/Link Target.md")],
            as: Result.self
        )
        XCTAssertFalse(result.hasFrontmatter)
        XCTAssertTrue(result.frontmatter.isEmpty)
    }

    // MARK: - get_backlinks

    func testGetBacklinksSeparatesLinkedAndUnlinked() async throws {
        struct LinkedEntry: Decodable { let relativePath: String }
        struct UnlinkedEntry: Decodable { let relativePath: String }
        struct Result: Decodable {
            let linked: [LinkedEntry]
            let unlinked: [UnlinkedEntry]
            let relativePath: String
            let vault: String
        }
        let result = try await harness.callTool(
            "get_backlinks",
            arguments: ["relative_path": .string("Notes/Link Target.md")],
            as: Result.self
        )
        // Linker.md has two [[Link Target]] references; Plan.md has one.
        XCTAssertGreaterThanOrEqual(result.linked.count, 3)
        XCTAssertTrue(result.linked.contains { $0.relativePath == "Notes/Linker.md" })
        XCTAssertTrue(result.linked.contains { $0.relativePath == "Projects/Plan.md" })
        // Unlinked Mention.md references the target in plain text.
        XCTAssertTrue(result.unlinked.contains { $0.relativePath == "Notes/Unlinked Mention.md" })
    }

    // MARK: - get_tags

    func testGetTagsAllMode() async throws {
        struct TagCount: Decodable { let tag: String; let count: Int }
        struct Result: Decodable { let mode: String; let allTags: [TagCount]? }
        let result = try await harness.callTool(
            "get_tags",
            arguments: [:],
            as: Result.self
        )
        XCTAssertEqual(result.mode, "all")
        XCTAssertNotNil(result.allTags)
        XCTAssertTrue(result.allTags!.contains { $0.tag == "fixture" })
        XCTAssertTrue(result.allTags!.contains { $0.tag == "architecture" })
    }

    func testGetTagsByTagMode() async throws {
        struct FileEntry: Decodable { let relativePath: String; let vault: String }
        struct Result: Decodable { let mode: String; let files: [FileEntry]? }
        let result = try await harness.callTool(
            "get_tags",
            arguments: ["tag": .string("architecture")],
            as: Result.self
        )
        XCTAssertEqual(result.mode, "by_tag")
        XCTAssertNotNil(result.files)
        XCTAssertTrue(result.files!.contains { $0.relativePath == "Projects/Plan.md" })
    }

    // MARK: - create_note + update_note

    func testCreateNoteAndReadBack() async throws {
        struct CreateResult: Decodable {
            let vault: String
            let relativePath: String
            let contentHash: String
            let sizeBytes: Int
        }
        let create = try await harness.callTool(
            "create_note",
            arguments: [
                "relative_path": .string("Inbox/new-note.md"),
                "content": .string("# Fresh Note\n\nBody text.\n")
            ],
            as: CreateResult.self
        )
        XCTAssertEqual(create.relativePath, "Inbox/new-note.md")
        XCTAssertEqual(create.contentHash.count, 64)  // SHA-256 hex
        XCTAssertGreaterThan(create.sizeBytes, 0)

        // Read it back
        struct ReadResult: Decodable { let content: String }
        let read = try await harness.callTool(
            "read_note",
            arguments: ["relative_path": .string("Inbox/new-note.md")],
            as: ReadResult.self
        )
        XCTAssertTrue(read.content.contains("# Fresh Note"))
    }

    func testUpdateNoteAppend() async throws {
        struct Ignored: Decodable {}
        _ = try await harness.callTool(
            "create_note",
            arguments: [
                "relative_path": .string("Inbox/appendable.md"),
                "content": .string("Line 1\n")
            ],
            as: Ignored.self
        )
        _ = try await harness.callTool(
            "update_note",
            arguments: [
                "relative_path": .string("Inbox/appendable.md"),
                "mode": .string("append"),
                "content": .string("Line 2\n")
            ],
            as: Ignored.self
        )
        struct ReadResult: Decodable { let content: String }
        let read = try await harness.callTool(
            "read_note",
            arguments: ["relative_path": .string("Inbox/appendable.md")],
            as: ReadResult.self
        )
        XCTAssertTrue(read.content.contains("Line 1"))
        XCTAssertTrue(read.content.contains("Line 2"))
    }

    func testUpdateNoteLinkShowsInBacklinks() async throws {
        struct Ignored: Decodable {}
        _ = try await harness.callTool(
            "create_note",
            arguments: [
                "relative_path": .string("Inbox/link-added-later.md"),
                "content": .string("No links yet.\n")
            ],
            as: Ignored.self
        )
        _ = try await harness.callTool(
            "update_note",
            arguments: [
                "relative_path": .string("Inbox/link-added-later.md"),
                "mode": .string("append"),
                "content": .string("Now links [[Link Target]].\n")
            ],
            as: Ignored.self
        )

        struct LinkedEntry: Decodable { let relativePath: String }
        struct Result: Decodable { let linked: [LinkedEntry] }
        let backlinks = try await harness.callTool(
            "get_backlinks",
            arguments: ["relative_path": .string("Notes/Link Target.md")],
            as: Result.self
        )
        XCTAssertTrue(backlinks.linked.contains { $0.relativePath == "Inbox/link-added-later.md" })
    }

    func testUpdateNotePrependPreservesFrontmatter() async throws {
        struct Ignored: Decodable {}
        _ = try await harness.callTool(
            "create_note",
            arguments: [
                "relative_path": .string("Inbox/fm.md"),
                "content": .string("---\ntitle: FM\n---\n\nBody.\n")
            ],
            as: Ignored.self
        )
        _ = try await harness.callTool(
            "update_note",
            arguments: [
                "relative_path": .string("Inbox/fm.md"),
                "mode": .string("prepend"),
                "content": .string("## Top Heading\n\n")
            ],
            as: Ignored.self
        )
        struct ReadResult: Decodable { let content: String }
        let read = try await harness.callTool(
            "read_note",
            arguments: ["relative_path": .string("Inbox/fm.md")],
            as: ReadResult.self
        )
        // frontmatter stays first; inserted content lands after the closing ---
        let parts = read.content.components(separatedBy: "---\n")
        XCTAssertGreaterThanOrEqual(parts.count, 3)
        XCTAssertTrue(parts.last!.contains("## Top Heading"))
        XCTAssertTrue(parts.last!.contains("Body."))
    }
}
