import Foundation
import ClearlyCore

struct ReviewFileArgs: Decodable {
    let filePath: String?
    let vault: String?

    init(filePath: String?, vault: String?) {
        self.filePath = filePath
        self.vault = vault
    }
}

struct ReviewForkArgs: Decodable {
    let filePath: String?
    let forkId: String
    let vault: String?

    init(filePath: String?, forkId: String, vault: String?) {
        self.filePath = filePath
        self.forkId = forkId
        self.vault = vault
    }
}

struct ReviewCommentsArgs: Decodable {
    let filePath: String?
    let status: String?
    let freshness: String?
    let vault: String?

    init(filePath: String?, status: String?, freshness: String?, vault: String?) {
        self.filePath = filePath
        self.status = status
        self.freshness = freshness
        self.vault = vault
    }
}

struct StageReviewResolutionArgs: Decodable {
    let filePath: String?
    let commentId: String
    let note: String?
    let remoteRevision: Int?
    let vault: String?

    init(filePath: String?, commentId: String, note: String?, remoteRevision: Int?, vault: String?) {
        self.filePath = filePath
        self.commentId = commentId
        self.note = note
        self.remoteRevision = remoteRevision
        self.vault = vault
    }
}

struct ConfirmReviewResolutionArgs: Decodable {
    let filePath: String?
    let commentId: String
    let note: String?
    let expectedRevision: Int?
    let confirm: Bool?
    let vault: String?

    init(filePath: String?, commentId: String, note: String?, expectedRevision: Int?, confirm: Bool?, vault: String?) {
        self.filePath = filePath
        self.commentId = commentId
        self.note = note
        self.expectedRevision = expectedRevision
        self.confirm = confirm
        self.vault = vault
    }
}

struct MutateReviewCommentArgs: Decodable {
    let filePath: String?
    let commentId: String
    let note: String?
    let expectedRevision: Int?
    let vault: String?

    init(filePath: String?, commentId: String, note: String?, expectedRevision: Int?, vault: String?) {
        self.filePath = filePath
        self.commentId = commentId
        self.note = note
        self.expectedRevision = expectedRevision
        self.vault = vault
    }
}

struct CurrentDocumentResult: Encodable {
    let appInstanceId: String
    let updatedAt: Date
    let vaultId: String
    let vaultRoot: String
    let fileId: String
    let targetRelativePath: String
    let targetAbsolutePath: String
    let documentTitle: String
}

struct ReviewContextResult: Encodable {
    let schemaVersion: Int
    let generatedAt: Date
    let freshness: String
    let vaultId: String
    let vaultRoot: String
    let fileId: String
    let targetRelativePath: String
    let targetAbsolutePath: String
    let targetContentHash: String
    let vaultURI: String
    let reviewId: String?
    let reviewUrl: String?
    let commentsCachePath: String
    let syncedAt: Date?
    let hasLinkedReview: Bool
}

struct ReviewCommentsResult: Encodable {
    let review: ReviewContextResult
    let stale: Bool
    let syncedAt: Date?
    let freshness: String
    let comments: [ReviewComment]
    let pendingResolutionCount: Int
    let error: ReviewToolErrorPayload?
    let cachedFallback: [ReviewComment]?
}

struct StageReviewResolutionResult: Encodable {
    let review: ReviewContextResult
    let commentId: String
    let staged: Bool
    let commentMissingInCache: Bool
    let pendingResolutionCount: Int
    let remoteStatus: String?
    let resolvedBy: String?
    let resolvedAt: Date?
    let remoteRevision: Int?
    let resolutionNote: String?
    let anchorConfidence: ReviewAnchorConfidence?
    let anchorRemapReason: String?
}

struct ReviewCommentMutationResult: Encodable {
    let review: ReviewContextResult
    let commentId: String
    let status: String
    let remoteRevision: Int?
    let syncedAt: Date?
}

struct ReviewToolErrorPayload: Encodable {
    let code: String
    let message: String
}

struct PublishReviewVersionResult: Encodable {
    let review: ReviewContextResult
    let published: Bool
    let version: Int?
    let snapshotUrl: String?
    let contentHash: String?
    let remappedComments: [ReviewServiceRemappedComment]
    let reason: String?
}

struct CreateReviewResult: Encodable {
    let review: ReviewContextResult
    let created: Bool
    let reviewId: String?
    let reviewUrl: String?
    let version: Int?
    let snapshotUrl: String?
    let reason: String?
}

struct ReviewForksResult: Encodable {
    let review: ReviewContextResult
    let forks: [ReviewForkSummary]
}

struct ReviewForkResult: Encodable {
    let review: ReviewContextResult
    let fork: ReviewForkDetail
    let markdownSource: String?
}

func getCurrentDocument(vaults: [LoadedVault]) async throws -> CurrentDocumentResult {
    let state: CurrentReviewDocumentState
    do {
        state = try ReviewStateStore.readCurrentDocument(bundleIdentifier: appBundleIdentifier(vaults: vaults))
    } catch ReviewStateError.staleCurrentDocument {
        throw ToolError.staleCurrentDocument
    } catch {
        throw ToolError.staleCurrentDocument
    }
    return CurrentDocumentResult(
        appInstanceId: state.appInstanceId,
        updatedAt: state.updatedAt,
        vaultId: state.vaultId,
        vaultRoot: state.vaultRoot,
        fileId: state.fileId,
        targetRelativePath: state.targetRelativePath,
        targetAbsolutePath: state.targetAbsolutePath,
        documentTitle: state.documentTitle
    )
}

func getReviewForFile(_ args: ReviewFileArgs, vaults: [LoadedVault]) async throws -> ReviewContextResult {
    let resolved = try resolveReviewFile(filePath: args.filePath, vaultHint: args.vault, vaults: vaults)
    let context = try ReviewStateStore.context(
        for: resolved.fileURL,
        vaultRoot: resolved.vault.url,
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    )
    return ReviewContextResult(context)
}

func syncReviewComments(_ args: ReviewFileArgs, vaults: [LoadedVault]) async throws -> ReviewCommentsResult {
    let resolved = try resolveReviewFile(filePath: args.filePath, vaultHint: args.vault, vaults: vaults)
    let context = try ReviewStateStore.context(
        for: resolved.fileURL,
        vaultRoot: resolved.vault.url,
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    )
    guard let reviewId = context.reviewId else {
        throw ToolError.reviewNotFound(context.vaultURI)
    }

    let client = try reviewServiceClient(context: context, vaults: vaults)
    let cache = try await client.fetchAllComments(reviewId: reviewId)
    try ReviewStateStore.writeCommentsCache(cache, context: context, bundleIdentifier: appBundleIdentifier(vaults: vaults))
    let updated = try ReviewStateStore.updateReviewRecord(
        for: resolved.fileURL,
        vaultRoot: resolved.vault.url,
        bundleIdentifier: appBundleIdentifier(vaults: vaults),
        syncedAt: cache.syncedAt
    )

    return ReviewCommentsResult(
        review: ReviewContextResult(updated),
        stale: false,
        syncedAt: cache.syncedAt,
        freshness: "latest",
        comments: cache.comments,
        pendingResolutionCount: try pendingResolutionCount(context: updated, vaults: vaults),
        error: nil,
        cachedFallback: nil
    )
}

func getReviewComments(_ args: ReviewCommentsArgs, vaults: [LoadedVault]) async throws -> ReviewCommentsResult {
    if args.freshness != "cache" {
        do {
            return try await syncReviewComments(
                ReviewFileArgs(filePath: args.filePath, vault: args.vault),
                vaults: vaults
            )
        } catch ToolError.networkUnreachable(let message) {
            return try cachedReviewCommentsResult(args, vaults: vaults, networkError: message)
        }
    }

    return try cachedReviewCommentsResult(args, vaults: vaults, networkError: nil)
}

private func cachedReviewCommentsResult(_ args: ReviewCommentsArgs, vaults: [LoadedVault], networkError: String?) throws -> ReviewCommentsResult {
    let resolved = try resolveReviewFile(filePath: args.filePath, vaultHint: args.vault, vaults: vaults)
    let context = try ReviewStateStore.context(
        for: resolved.fileURL,
        vaultRoot: resolved.vault.url,
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    )
    let cache = try ReviewStateStore.readCommentsCache(context: context, bundleIdentifier: appBundleIdentifier(vaults: vaults))
    let filtered = args.status.map { status in
        cache.comments.filter { $0.status == status }
    } ?? cache.comments

    return ReviewCommentsResult(
        review: ReviewContextResult(context),
        stale: true,
        syncedAt: cache.syncedAt,
        freshness: "cache",
        comments: filtered,
        pendingResolutionCount: try pendingResolutionCount(context: context, vaults: vaults),
        error: networkError.map { ReviewToolErrorPayload(code: "network_unreachable", message: "Review service is unreachable: \($0)") },
        cachedFallback: networkError == nil ? nil : filtered
    )
}

func stageReviewCommentResolution(_ args: StageReviewResolutionArgs, vaults: [LoadedVault]) async throws -> StageReviewResolutionResult {
    let resolved = try resolveReviewFile(filePath: args.filePath, vaultHint: args.vault, vaults: vaults)
    let context = try ReviewStateStore.context(
        for: resolved.fileURL,
        vaultRoot: resolved.vault.url,
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    )
    guard context.reviewId != nil else {
        throw ToolError.reviewNotFound(context.vaultURI)
    }
    let cache = try ReviewStateStore.readCommentsCache(context: context, bundleIdentifier: appBundleIdentifier(vaults: vaults))
    let comment = cache.comments.first(where: { $0.id == args.commentId })
    if comment == nil && args.remoteRevision == nil {
        throw ToolError.invalidArgument(name: "remote_revision", reason: "is required when the comment is not present in comments-cache.json")
    }
    let pendingCount = try await ReviewStateStore.withPendingResolutionsLock(
        context: context,
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    ) {
        var pending = try readPendingResolutions(context: context, vaults: vaults)
        pending.pending.removeAll { $0.commentId == args.commentId }
        pending.pending.append(PendingReviewResolution(
            commentId: args.commentId,
            remoteRevision: args.remoteRevision ?? comment?.remoteRevision,
            note: args.note ?? "",
            stagedBy: "agent",
            stagedAt: Date(),
            anchorSnapshot: comment.map { $0.currentAnchor ?? $0.anchor },
            anchorConfidence: comment?.anchorConfidence,
            anchorRemappedVersion: comment?.anchorRemappedVersion
        ))
        pending.updatedAt = Date()
        try ReviewStateStore.writePendingResolutions(
            pending,
            context: context,
            bundleIdentifier: appBundleIdentifier(vaults: vaults)
        )
        return pending.pending.count
    }
    return StageReviewResolutionResult(
        review: ReviewContextResult(context),
        commentId: args.commentId,
        staged: true,
        commentMissingInCache: comment == nil,
        pendingResolutionCount: pendingCount,
        remoteStatus: nil,
        resolvedBy: nil,
        resolvedAt: nil,
        remoteRevision: args.remoteRevision ?? comment?.remoteRevision,
        resolutionNote: nil,
        anchorConfidence: comment?.anchorConfidence,
        anchorRemapReason: comment?.anchorRemapReason
    )
}

func createReview(_ args: ReviewFileArgs, vaults: [LoadedVault]) async throws -> CreateReviewResult {
    let resolved = try resolveReviewFile(filePath: args.filePath, vaultHint: args.vault, vaults: vaults)
    let context = try ReviewStateStore.context(
        for: resolved.fileURL,
        vaultRoot: resolved.vault.url,
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    )
    if context.reviewId != nil {
        return CreateReviewResult(
            review: ReviewContextResult(context),
            created: false,
            reviewId: context.reviewId,
            reviewUrl: context.reviewUrl,
            version: nil,
            snapshotUrl: nil,
            reason: "review_already_linked"
        )
    }

    let markdown: String
    do {
        markdown = try String(contentsOf: resolved.fileURL, encoding: .utf8)
    } catch {
        throw ToolError.fileUnreadable(resolved.fileURL.path)
    }

    let client = try reviewServiceClient(context: context, vaults: vaults)
    let response = try await client.createReview(
        markdown: markdown,
        title: resolved.fileURL.lastPathComponent,
        targetRelativePath: context.targetRelativePath,
        vaultId: context.vaultId
    )
    let snapshot = ReviewSnapshotRenderer.render(markdown: markdown, title: resolved.fileURL.lastPathComponent)
    let updated = try ReviewStateStore.updateReviewRecord(
        for: resolved.fileURL,
        vaultRoot: resolved.vault.url,
        bundleIdentifier: appBundleIdentifier(vaults: vaults),
        reviewId: response.reviewId,
        publisherId: response.publisherId,
        keychainAccount: response.keychainAccount,
        reviewUrl: response.reviewUrl,
        latestVersion: response.version,
        targetContentHash: snapshot.contentHash,
        syncedAt: Date()
    )

    return CreateReviewResult(
        review: ReviewContextResult(updated),
        created: true,
        reviewId: response.reviewId,
        reviewUrl: response.reviewUrl,
        version: response.version,
        snapshotUrl: response.snapshotUrl,
        reason: nil
    )
}

func confirmReviewCommentResolution(_ args: ConfirmReviewResolutionArgs, vaults: [LoadedVault]) async throws -> StageReviewResolutionResult {
    let resolved = try resolveReviewFile(filePath: args.filePath, vaultHint: args.vault, vaults: vaults)
    var context = try ReviewStateStore.context(
        for: resolved.fileURL,
        vaultRoot: resolved.vault.url,
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    )
    guard args.confirm == true else {
        throw ToolError.forbidden("confirm_review_comment_resolution requires confirm=true after the user reviews the diff.")
    }
    guard let reviewId = context.reviewId else {
        throw ToolError.reviewNotFound(context.vaultURI)
    }
    _ = try await syncReviewComments(ReviewFileArgs(filePath: args.filePath, vault: args.vault), vaults: vaults)
    context = try ReviewStateStore.context(
        for: resolved.fileURL,
        vaultRoot: resolved.vault.url,
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    )

    let result = try await ReviewStateStore.withPendingResolutionsLock(
        context: context,
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    ) { () async throws -> (response: ReviewResolveResponse, pendingCount: Int, comment: ReviewComment) in
        var pending = try readPendingResolutions(context: context, vaults: vaults)
        guard let staged = pending.pending.first(where: { $0.commentId == args.commentId }) else {
            throw ToolError.forbidden("confirm_review_comment_resolution requires a staged resolution for \(args.commentId).")
        }
        let cache = try ReviewStateStore.readCommentsCache(context: context, bundleIdentifier: appBundleIdentifier(vaults: vaults))
        guard let comment = cache.comments.first(where: { $0.id == args.commentId }) else {
            throw ToolError.reviewNotFound("Comment \(args.commentId) was not found in the latest review sync.")
        }
        if let stagedRevision = staged.remoteRevision,
           let currentRevision = comment.remoteRevision,
           stagedRevision != currentRevision {
            throw ToolError.remoteRevisionConflict("Comment \(args.commentId) moved from revision \(stagedRevision) to \(currentRevision). Re-stage after reviewing the latest comment.")
        }
        if let stagedAnchor = staged.anchorSnapshot {
            let currentAnchor = comment.currentAnchor ?? comment.anchor
            if currentAnchor != stagedAnchor ||
                staged.anchorConfidence != comment.anchorConfidence ||
                staged.anchorRemappedVersion != comment.anchorRemappedVersion {
                throw ToolError.remoteRevisionConflict("Comment \(args.commentId) anchor changed since staging. Re-stage after reviewing its current anchor.")
            }
        }
        guard let expectedRevision = args.expectedRevision ?? staged.remoteRevision ?? comment.remoteRevision else {
            throw ToolError.invalidArgument(name: "expected_revision", reason: "is required unless a staged resolution has remote_revision")
        }

        let client = try reviewServiceClient(context: context, vaults: vaults)
        let response = try await client.resolveComment(
            reviewId: reviewId,
            commentId: args.commentId,
            expectedRevision: expectedRevision,
            resolvedBy: "publisher",
            note: args.note ?? staged.note
        )
        pending.pending.removeAll { $0.commentId == args.commentId }
        pending.updatedAt = Date()
        try ReviewStateStore.writePendingResolutions(
            pending,
            context: context,
            bundleIdentifier: appBundleIdentifier(vaults: vaults)
        )
        return (response, pending.pending.count, comment)
    }

    return StageReviewResolutionResult(
        review: ReviewContextResult(context),
        commentId: args.commentId,
        staged: false,
        commentMissingInCache: false,
        pendingResolutionCount: result.pendingCount,
        remoteStatus: result.response.status,
        resolvedBy: result.response.resolvedBy,
        resolvedAt: result.response.resolvedAt,
        remoteRevision: result.response.remoteRevision,
        resolutionNote: result.response.resolutionNote,
        anchorConfidence: result.comment.anchorConfidence,
        anchorRemapReason: result.comment.anchorRemapReason
    )
}

func closeReviewComment(_ args: MutateReviewCommentArgs, vaults: [LoadedVault]) async throws -> ReviewCommentMutationResult {
    try await mutateRemoteComment(args, vaults: vaults) { client, reviewId, expectedRevision in
        let response = try await client.closeComment(
            reviewId: reviewId,
            commentId: args.commentId,
            expectedRevision: expectedRevision,
            closedBy: "publisher",
            note: args.note ?? "Closed without changes."
        )
        return (response.status, response.remoteRevision)
    }
}

func deleteReviewComment(_ args: MutateReviewCommentArgs, vaults: [LoadedVault]) async throws -> ReviewCommentMutationResult {
    try await mutateRemoteComment(args, vaults: vaults) { client, reviewId, expectedRevision in
        let response = try await client.deleteComment(
            reviewId: reviewId,
            commentId: args.commentId,
            expectedRevision: expectedRevision,
            deletedBy: "publisher"
        )
        return (response.status, response.remoteRevision)
    }
}

private func mutateRemoteComment(
    _ args: MutateReviewCommentArgs,
    vaults: [LoadedVault],
    mutation: (ReviewServiceClient, String, Int) async throws -> (status: String, remoteRevision: Int?)
) async throws -> ReviewCommentMutationResult {
    let resolved = try resolveReviewFile(filePath: args.filePath, vaultHint: args.vault, vaults: vaults)
    var context = try ReviewStateStore.context(
        for: resolved.fileURL,
        vaultRoot: resolved.vault.url,
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    )
    guard let reviewId = context.reviewId else {
        throw ToolError.reviewNotFound(context.vaultURI)
    }
    let client = try reviewServiceClient(context: context, vaults: vaults)
    let expectedRevision: Int
    if let provided = args.expectedRevision {
        expectedRevision = provided
    } else {
        let synced = try await client.fetchAllComments(reviewId: reviewId)
        try ReviewStateStore.writeCommentsCache(synced, context: context, bundleIdentifier: appBundleIdentifier(vaults: vaults))
        guard let comment = synced.comments.first(where: { $0.id == args.commentId }),
              let revision = comment.remoteRevision else {
            throw ToolError.reviewNotFound("Comment \(args.commentId) was not found in the latest review sync.")
        }
        expectedRevision = revision
    }

    let mutationResult = try await mutation(client, reviewId, expectedRevision)
    try await ReviewStateStore.withPendingResolutionsLock(
        context: context,
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    ) {
        var pending = try readPendingResolutions(context: context, vaults: vaults)
        pending.pending.removeAll { $0.commentId == args.commentId }
        pending.updatedAt = Date()
        try ReviewStateStore.writePendingResolutions(
            pending,
            context: context,
            bundleIdentifier: appBundleIdentifier(vaults: vaults)
        )
    }
    let cache = try await client.fetchAllComments(reviewId: reviewId)
    try ReviewStateStore.writeCommentsCache(cache, context: context, bundleIdentifier: appBundleIdentifier(vaults: vaults))
    context = try ReviewStateStore.updateReviewRecord(
        for: resolved.fileURL,
        vaultRoot: resolved.vault.url,
        bundleIdentifier: appBundleIdentifier(vaults: vaults),
        syncedAt: cache.syncedAt
    )
    return ReviewCommentMutationResult(
        review: ReviewContextResult(context),
        commentId: args.commentId,
        status: mutationResult.status,
        remoteRevision: mutationResult.remoteRevision,
        syncedAt: cache.syncedAt
    )
}

func publishReviewVersion(_ args: ReviewFileArgs, vaults: [LoadedVault]) async throws -> PublishReviewVersionResult {
    let resolved = try resolveReviewFile(filePath: args.filePath, vaultHint: args.vault, vaults: vaults)
    let context = try ReviewStateStore.context(
        for: resolved.fileURL,
        vaultRoot: resolved.vault.url,
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    )
    guard let reviewId = context.reviewId else {
        throw ToolError.reviewNotFound(context.vaultURI)
    }
    let markdown: String
    do {
        markdown = try String(contentsOf: resolved.fileURL, encoding: .utf8)
    } catch {
        throw ToolError.fileUnreadable(resolved.fileURL.path)
    }
    let client = try reviewServiceClient(context: context, vaults: vaults)
    let response = try await client.publishVersion(
        reviewId: reviewId,
        markdown: markdown,
        title: resolved.fileURL.lastPathComponent
    )
    let updated = try ReviewStateStore.updateReviewRecord(
        for: resolved.fileURL,
        vaultRoot: resolved.vault.url,
        bundleIdentifier: appBundleIdentifier(vaults: vaults),
        latestVersion: response.version,
        targetContentHash: ReviewSnapshotRenderer.render(markdown: markdown, title: resolved.fileURL.lastPathComponent).contentHash,
        syncedAt: Date()
    )
    return PublishReviewVersionResult(
        review: ReviewContextResult(updated),
        published: true,
        version: response.version,
        snapshotUrl: response.snapshotUrl,
        contentHash: updated.targetContentHash,
        remappedComments: response.remappedComments,
        reason: nil
    )
}

func getReviewForks(_ args: ReviewFileArgs, vaults: [LoadedVault]) async throws -> ReviewForksResult {
    let review = try await getReviewForFile(args, vaults: vaults)
    guard let reviewId = review.reviewId else {
        throw ToolError.reviewNotFound(review.vaultURI)
    }
    let context = try ReviewStateStore.context(
        for: URL(fileURLWithPath: review.targetAbsolutePath),
        vaultRoot: URL(fileURLWithPath: review.vaultRoot),
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    )
    let client = try reviewServiceClient(context: context, vaults: vaults)
    let forks = try await client.fetchForks(reviewId: reviewId)
    return ReviewForksResult(review: review, forks: forks)
}

func getReviewFork(_ args: ReviewForkArgs, vaults: [LoadedVault]) async throws -> ReviewForkResult {
    let review = try await getReviewForFile(
        ReviewFileArgs(filePath: args.filePath, vault: args.vault),
        vaults: vaults
    )
    guard let reviewId = review.reviewId else {
        throw ToolError.reviewNotFound(review.vaultURI)
    }
    let context = try ReviewStateStore.context(
        for: URL(fileURLWithPath: review.targetAbsolutePath),
        vaultRoot: URL(fileURLWithPath: review.vaultRoot),
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    )
    let client = try reviewServiceClient(context: context, vaults: vaults)
    let fork = try await client.fetchFork(reviewId: reviewId, forkId: args.forkId)
    return ReviewForkResult(review: review, fork: fork, markdownSource: fork.markdownSource)
}

private func appBundleIdentifier(vaults: [LoadedVault]) -> String {
    vaults.first?.bundleIdentifier ?? "com.sabotage.clearly"
}

private func reviewServiceClient(context: ReviewContextPayload, vaults: [LoadedVault]) throws -> ReviewServiceClient {
    let record = try ReviewStateStore.reviewRecord(
        context: context,
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    )
    let configuration = try ReviewServiceConfiguration.load(record: record)
    return ReviewServiceClient(configuration: configuration)
}

private func resolveReviewFile(filePath: String?, vaultHint: String?, vaults: [LoadedVault]) throws -> (vault: LoadedVault, fileURL: URL) {
    let rawPath: String
    if let filePath, !filePath.isEmpty {
        rawPath = filePath
    } else {
        let state = try ReviewStateStore.readCurrentDocument(bundleIdentifier: appBundleIdentifier(vaults: vaults))
        rawPath = "vault://\(state.vaultId)/\(state.targetRelativePath)"
    }

    if rawPath.hasPrefix("vault://") {
        let parsed = try ReviewFilePath.parseVaultURI(rawPath)
        let matches = vaults.filter { vault in
            let identity = try? ReviewStateStore.ensureVaultIdentity(vaultRoot: vault.url)
            return identity?.vaultId == parsed.vaultId
        }
        guard let vault = matches.first else {
            throw ToolError.reviewTargetMissing(rawPath)
        }
        let fileURL = try PathGuard.resolve(relativePath: parsed.relativePath, in: vault.url)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ToolError.reviewTargetMissing(rawPath)
        }
        return (vault, fileURL)
    }

    if rawPath.hasPrefix("/") {
        let fileURL = URL(fileURLWithPath: rawPath).standardizedFileURL
        let matches = vaults.filter { vault in
            let root = vault.url.standardizedFileURL.path
            return fileURL.path == root || fileURL.path.hasPrefix(root + "/")
        }
        guard let vault = matches.max(by: { $0.url.path.count < $1.url.path.count }) else {
            throw ToolError.pathOutsideVault(rawPath)
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ToolError.reviewTargetMissing(rawPath)
        }
        return (vault, fileURL)
    }

    switch try VaultResolver.resolve(relativePath: rawPath, hint: vaultHint, in: vaults) {
    case .resolved(let vault):
        let fileURL = try PathGuard.resolve(relativePath: rawPath, in: vault.url)
        return (vault, fileURL)
    case .notFound:
        throw ToolError.reviewTargetMissing(rawPath)
    case .ambiguous(let matches):
        throw ToolError.ambiguousVault(relativePath: rawPath, matches: matches.map { $0.url.path })
    }
}

private func pendingResolutionCount(context: ReviewContextPayload, vaults: [LoadedVault]) throws -> Int {
    try readPendingResolutions(context: context, vaults: vaults).pending.count
}

private func readPendingResolutions(context: ReviewContextPayload, vaults: [LoadedVault]) throws -> PendingReviewResolutions {
    try ReviewStateStore.readPendingResolutions(
        context: context,
        bundleIdentifier: appBundleIdentifier(vaults: vaults)
    )
}

private extension ReviewContextResult {
    init(_ payload: ReviewContextPayload) {
        self.init(
            schemaVersion: payload.schemaVersion,
            generatedAt: payload.generatedAt,
            freshness: payload.freshness,
            vaultId: payload.vaultId,
            vaultRoot: payload.vaultRoot,
            fileId: payload.fileId,
            targetRelativePath: payload.targetRelativePath,
            targetAbsolutePath: payload.targetAbsolutePath,
            targetContentHash: payload.targetContentHash,
            vaultURI: payload.vaultURI,
            reviewId: payload.reviewId,
            reviewUrl: payload.reviewUrl,
            commentsCachePath: payload.commentsCachePath,
            syncedAt: payload.syncedAt,
            hasLinkedReview: payload.reviewId != nil
        )
    }
}
