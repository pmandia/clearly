import XCTest
@testable import ClearlyCore

final class ReviewStateTests: XCTestCase {
    private var tempRoot: URL!
    private let bundleIdentifier = "com.sabotage.clearly.tests"

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClearlyReviewStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        if let appSupportRoot = try? ReviewStateStore.appSupportRoot(bundleIdentifier: bundleIdentifier) {
            try? FileManager.default.removeItem(at: appSupportRoot)
        }
        tempRoot = nil
    }

    func testEnsureVaultIdentityPersistsStableID() throws {
        let first = try ReviewStateStore.ensureVaultIdentity(vaultRoot: tempRoot)
        let second = try ReviewStateStore.ensureVaultIdentity(vaultRoot: tempRoot)

        XCTAssertEqual(first.vaultId, second.vaultId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent(".clearly/vault.json").path))
    }

    func testContextCreatesManifestRecord() throws {
        let fileURL = tempRoot.appendingPathComponent("proposal.md")
        try "# Proposal\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let context = try ReviewStateStore.context(
            for: fileURL,
            vaultRoot: tempRoot,
            bundleIdentifier: bundleIdentifier
        )
        let manifest = try ReviewStateStore.loadManifest(
            vaultId: context.vaultId,
            bundleIdentifier: bundleIdentifier
        )

        XCTAssertEqual(context.targetRelativePath, "proposal.md")
        XCTAssertEqual(context.vaultURI, "vault://\(context.vaultId)/proposal.md")
        XCTAssertEqual(manifest.reviews.count, 1)
        XCTAssertEqual(manifest.reviews[0].fileId, context.fileId)
    }

    func testVaultURIParsing() throws {
        let parsed = try ReviewFilePath.parseVaultURI("vault://vlt_123/folder/proposal.md")
        XCTAssertEqual(parsed.vaultId, "vlt_123")
        XCTAssertEqual(parsed.relativePath, "folder/proposal.md")
    }

    func testPendingResolutionsRoundTripInReviewStateDirectory() throws {
        let fileURL = tempRoot.appendingPathComponent("proposal.md")
        try "# Proposal\n".write(to: fileURL, atomically: true, encoding: .utf8)
        var context = try ReviewStateStore.context(
            for: fileURL,
            vaultRoot: tempRoot,
            bundleIdentifier: bundleIdentifier
        )
        context = try ReviewStateStore.updateReviewRecord(
            for: fileURL,
            vaultRoot: tempRoot,
            bundleIdentifier: bundleIdentifier,
            reviewId: "rvw_123"
        )
        let pending = PendingReviewResolutions(
            reviewId: "rvw_123",
            pending: [
                PendingReviewResolution(
                    commentId: "cmt_1",
                    remoteRevision: 4,
                    note: "Addressed in local diff.",
                    stagedBy: "agent"
                )
            ]
        )

        try ReviewStateStore.writePendingResolutions(
            pending,
            context: context,
            bundleIdentifier: bundleIdentifier
        )
        let loaded = try ReviewStateStore.readPendingResolutions(
            context: context,
            bundleIdentifier: bundleIdentifier
        )
        let url = try ReviewStateStore.pendingResolutionsURL(
            context: context,
            bundleIdentifier: bundleIdentifier
        )

        XCTAssertEqual(loaded.reviewId, "rvw_123")
        XCTAssertEqual(loaded.pending.first?.commentId, "cmt_1")
        XCTAssertTrue(url.path.contains("/ReviewState/\(context.vaultId)/rvw_123/pending-resolutions.json"))
    }

    func testPendingResolutionLockRecoversFromStaleDirectory() async throws {
        let fileURL = tempRoot.appendingPathComponent("proposal.md")
        try "# Proposal\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try ReviewStateStore.context(
            for: fileURL,
            vaultRoot: tempRoot,
            bundleIdentifier: bundleIdentifier
        )
        let context = try ReviewStateStore.updateReviewRecord(
            for: fileURL,
            vaultRoot: tempRoot,
            bundleIdentifier: bundleIdentifier,
            reviewId: "rvw_123"
        )
        let pendingURL = try ReviewStateStore.pendingResolutionsURL(
            context: context,
            bundleIdentifier: bundleIdentifier
        )
        let lockURL = pendingURL.deletingLastPathComponent().appendingPathComponent("pending-resolutions.lock", isDirectory: true)
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lockURL, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: lockURL.path)

        let value = try await ReviewStateStore.withPendingResolutionsLock(
            context: context,
            bundleIdentifier: bundleIdentifier
        ) {
            "acquired"
        }

        XCTAssertEqual(value, "acquired")
        XCTAssertFalse(FileManager.default.fileExists(atPath: lockURL.path))
    }

    func testManifestRefusesNewerSchemaVersion() throws {
        let fileURL = tempRoot.appendingPathComponent("proposal.md")
        try "# Proposal\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let context = try ReviewStateStore.context(
            for: fileURL,
            vaultRoot: tempRoot,
            bundleIdentifier: bundleIdentifier
        )
        let manifestURL = try ReviewStateStore.manifestURL(vaultId: context.vaultId, bundleIdentifier: bundleIdentifier)
        let future = """
        {
          "schemaVersion": 999,
          "vaultId": "\(context.vaultId)",
          "reviews": []
        }
        """
        try future.write(to: manifestURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try ReviewStateStore.loadManifest(vaultId: context.vaultId, bundleIdentifier: bundleIdentifier)) { error in
            guard case ReviewStateError.schemaVersionUnsupported = error else {
                return XCTFail("Expected schemaVersionUnsupported, got \(error)")
            }
        }
    }
}
