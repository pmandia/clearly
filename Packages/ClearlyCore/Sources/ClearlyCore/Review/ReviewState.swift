import CryptoKit
import Foundation

public enum ReviewStateError: Error, Equatable {
    case applicationSupportUnavailable
    case fileOutsideVault(file: String, vault: String)
    case missingReviewTarget(String)
    case invalidVaultURI(String)
    case staleCurrentDocument
    case schemaVersionUnsupported(resource: String, found: Int, supported: Int)
    case localStateLockUnavailable(String)
}

public struct ReviewVaultIdentity: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let vaultId: String
    public let createdAt: Date

    public init(schemaVersion: Int = 1, vaultId: String, createdAt: Date = Date()) {
        self.schemaVersion = schemaVersion
        self.vaultId = vaultId
        self.createdAt = createdAt
    }
}

public struct ReviewManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var vaultId: String
    public var reviews: [ReviewRecord]

    public init(schemaVersion: Int = 1, vaultId: String, reviews: [ReviewRecord] = []) {
        self.schemaVersion = schemaVersion
        self.vaultId = vaultId
        self.reviews = reviews
    }
}

public struct ReviewRecord: Codable, Equatable, Sendable {
    public var reviewId: String?
    public var fileId: String
    public var targetRelativePath: String
    public var targetAbsolutePath: String
    public var targetContentHash: String
    public var publisherId: String?
    public var keychainAccount: String?
    public var reviewUrl: String?
    public var latestVersion: Int?
    public var commentsCachePath: String
    public var syncedAt: Date?

    public init(
        reviewId: String? = nil,
        fileId: String = "file_\(UUID().uuidString.lowercased())",
        targetRelativePath: String,
        targetAbsolutePath: String,
        targetContentHash: String,
        publisherId: String? = nil,
        keychainAccount: String? = nil,
        reviewUrl: String? = nil,
        latestVersion: Int? = nil,
        commentsCachePath: String,
        syncedAt: Date? = nil
    ) {
        self.reviewId = reviewId
        self.fileId = fileId
        self.targetRelativePath = targetRelativePath
        self.targetAbsolutePath = targetAbsolutePath
        self.targetContentHash = targetContentHash
        self.publisherId = publisherId
        self.keychainAccount = keychainAccount
        self.reviewUrl = reviewUrl
        self.latestVersion = latestVersion
        self.commentsCachePath = commentsCachePath
        self.syncedAt = syncedAt
    }
}

public struct ReviewContextPayload: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let freshness: String
    public let vaultId: String
    public let vaultRoot: String
    public let fileId: String
    public let targetRelativePath: String
    public let targetAbsolutePath: String
    public let targetContentHash: String
    public let vaultURI: String
    public let reviewId: String?
    public let reviewUrl: String?
    public let commentsCachePath: String
    public let syncedAt: Date?
}

public struct ReviewCommentsCache: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var reviewId: String?
    public var remoteRevision: String?
    public var syncedAt: Date?
    public var freshness: String
    public var comments: [ReviewComment]

    public init(
        schemaVersion: Int = 1,
        reviewId: String? = nil,
        remoteRevision: String? = nil,
        syncedAt: Date? = nil,
        freshness: String = "cache",
        comments: [ReviewComment] = []
    ) {
        self.schemaVersion = schemaVersion
        self.reviewId = reviewId
        self.remoteRevision = remoteRevision
        self.syncedAt = syncedAt
        self.freshness = freshness
        self.comments = comments
    }
}

public struct ReviewComment: Codable, Equatable, Sendable {
    public var id: String
    public var reviewId: String?
    public var version: Int
    public var parentCommentId: String?
    public var status: String
    public var author: String
    public var authorId: String
    public var body: String
    public var selectedText: String?
    public var suggestedReplacement: String?
    public var suggestionMode: String
    public var anchor: ReviewAnchor
    public var currentAnchor: ReviewAnchor?
    public var anchorConfidence: ReviewAnchorConfidence?
    public var anchorRemapReason: String?
    public var anchorRemappedVersion: Int?
    public var orphaned: Bool
    public var remoteRevision: Int?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var resolvedBy: String?
    public var resolvedAt: Date?
    public var resolutionNote: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case commentId
        case reviewId
        case version
        case parentCommentId
        case status
        case author
        case authorId
        case authorDisplayName
        case body
        case selectedText
        case suggestedReplacement
        case suggestionMode
        case anchor
        case currentAnchor
        case anchorConfidence
        case anchorRemapReason
        case anchorRemappedVersion
        case orphaned
        case remoteRevision
        case createdAt
        case updatedAt
        case resolvedBy
        case resolvedAt
        case resolutionNote
    }

    public init(
        id: String,
        reviewId: String? = nil,
        version: Int,
        parentCommentId: String? = nil,
        status: String = "open",
        author: String,
        authorId: String,
        body: String,
        selectedText: String? = nil,
        suggestedReplacement: String? = nil,
        suggestionMode: String = "advisory",
        anchor: ReviewAnchor,
        currentAnchor: ReviewAnchor? = nil,
        anchorConfidence: ReviewAnchorConfidence? = nil,
        anchorRemapReason: String? = nil,
        anchorRemappedVersion: Int? = nil,
        orphaned: Bool = false,
        remoteRevision: Int? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        resolvedBy: String? = nil,
        resolvedAt: Date? = nil,
        resolutionNote: String? = nil
    ) {
        self.id = id
        self.reviewId = reviewId
        self.version = version
        self.parentCommentId = parentCommentId
        self.status = status
        self.author = author
        self.authorId = authorId
        self.body = body
        self.selectedText = selectedText
        self.suggestedReplacement = suggestedReplacement
        self.suggestionMode = suggestionMode
        self.anchor = anchor
        self.currentAnchor = currentAnchor
        self.anchorConfidence = anchorConfidence
        self.anchorRemapReason = anchorRemapReason
        self.anchorRemappedVersion = anchorRemappedVersion
        self.orphaned = orphaned
        self.remoteRevision = remoteRevision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolvedBy = resolvedBy
        self.resolvedAt = resolvedAt
        self.resolutionNote = resolutionNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .commentId)
        self.reviewId = try container.decodeIfPresent(String.self, forKey: .reviewId)
        self.version = try container.decode(Int.self, forKey: .version)
        self.parentCommentId = try container.decodeIfPresent(String.self, forKey: .parentCommentId)
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? "open"
        self.author = try container.decodeIfPresent(String.self, forKey: .author)
            ?? container.decodeIfPresent(String.self, forKey: .authorDisplayName)
            ?? ""
        self.authorId = try container.decodeIfPresent(String.self, forKey: .authorId) ?? ""
        self.body = try container.decode(String.self, forKey: .body)
        self.selectedText = try container.decodeIfPresent(String.self, forKey: .selectedText)
        self.suggestedReplacement = try container.decodeIfPresent(String.self, forKey: .suggestedReplacement)
        self.suggestionMode = try container.decodeIfPresent(String.self, forKey: .suggestionMode) ?? "advisory"
        self.anchor = try container.decode(ReviewAnchor.self, forKey: .anchor)
        self.currentAnchor = try container.decodeIfPresent(ReviewAnchor.self, forKey: .currentAnchor)
        self.anchorConfidence = try container.decodeIfPresent(ReviewAnchorConfidence.self, forKey: .anchorConfidence)
        self.anchorRemapReason = try container.decodeIfPresent(String.self, forKey: .anchorRemapReason)
        self.anchorRemappedVersion = try container.decodeIfPresent(Int.self, forKey: .anchorRemappedVersion)
        self.orphaned = try container.decodeIfPresent(Bool.self, forKey: .orphaned) ?? (self.anchorConfidence == .orphan)
        self.remoteRevision = try container.decodeIfPresent(Int.self, forKey: .remoteRevision)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        self.resolvedBy = try container.decodeIfPresent(String.self, forKey: .resolvedBy)
        self.resolvedAt = try container.decodeIfPresent(Date.self, forKey: .resolvedAt)
        self.resolutionNote = try container.decodeIfPresent(String.self, forKey: .resolutionNote)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(id, forKey: .commentId)
        try container.encodeIfPresent(reviewId, forKey: .reviewId)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(parentCommentId, forKey: .parentCommentId)
        try container.encode(status, forKey: .status)
        try container.encode(author, forKey: .author)
        try container.encode(author, forKey: .authorDisplayName)
        try container.encode(authorId, forKey: .authorId)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(selectedText, forKey: .selectedText)
        try container.encodeIfPresent(suggestedReplacement, forKey: .suggestedReplacement)
        try container.encode(suggestionMode, forKey: .suggestionMode)
        try container.encode(anchor, forKey: .anchor)
        try container.encodeIfPresent(currentAnchor, forKey: .currentAnchor)
        try container.encodeIfPresent(anchorConfidence, forKey: .anchorConfidence)
        try container.encodeIfPresent(anchorRemapReason, forKey: .anchorRemapReason)
        try container.encodeIfPresent(anchorRemappedVersion, forKey: .anchorRemappedVersion)
        try container.encode(orphaned, forKey: .orphaned)
        try container.encodeIfPresent(remoteRevision, forKey: .remoteRevision)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(resolvedBy, forKey: .resolvedBy)
        try container.encodeIfPresent(resolvedAt, forKey: .resolvedAt)
        try container.encodeIfPresent(resolutionNote, forKey: .resolutionNote)
    }
}

public struct PendingReviewResolutions: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var reviewId: String?
    public var updatedAt: Date
    public var pending: [PendingReviewResolution]

    public init(schemaVersion: Int = 1, reviewId: String? = nil, updatedAt: Date = Date(), pending: [PendingReviewResolution] = []) {
        self.schemaVersion = schemaVersion
        self.reviewId = reviewId
        self.updatedAt = updatedAt
        self.pending = pending
    }
}

public struct PendingReviewResolution: Codable, Equatable, Sendable {
    public var commentId: String
    public var remoteRevision: Int?
    public var note: String
    public var stagedBy: String
    public var stagedAt: Date
    public var anchorSnapshot: ReviewAnchor?
    public var anchorConfidence: ReviewAnchorConfidence?
    public var anchorRemappedVersion: Int?

    public init(
        commentId: String,
        remoteRevision: Int? = nil,
        note: String,
        stagedBy: String,
        stagedAt: Date = Date(),
        anchorSnapshot: ReviewAnchor? = nil,
        anchorConfidence: ReviewAnchorConfidence? = nil,
        anchorRemappedVersion: Int? = nil
    ) {
        self.commentId = commentId
        self.remoteRevision = remoteRevision
        self.note = note
        self.stagedBy = stagedBy
        self.stagedAt = stagedAt
        self.anchorSnapshot = anchorSnapshot
        self.anchorConfidence = anchorConfidence
        self.anchorRemappedVersion = anchorRemappedVersion
    }
}

public struct CurrentReviewDocumentState: Codable, Equatable, Sendable {
    public let appInstanceId: String
    public let updatedAt: Date
    public let vaultId: String
    public let vaultRoot: String
    public let fileId: String
    public let targetRelativePath: String
    public let targetAbsolutePath: String
    public let documentTitle: String

    public var isFresh: Bool {
        Date().timeIntervalSince(updatedAt) < 30
    }
}

public enum ReviewStateStore {
    public static let schemaVersion = 1
    public static let anchorNormalizerVersion = 1

    public static func appSupportRoot(bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws -> URL {
        let base = try sharedApplicationSupportBase(bundleIdentifier: bundleIdentifier)
        let appDirectory = base.appendingPathComponent(bundleIdentifier ?? "com.sabotage.clearly", isDirectory: true)
        return appDirectory.appendingPathComponent("ReviewState", isDirectory: true)
    }

    public static func currentDocumentURL(bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws -> URL {
        let base = try sharedApplicationSupportBase(bundleIdentifier: bundleIdentifier)
        let appDirectory = base.appendingPathComponent(bundleIdentifier ?? "com.sabotage.clearly", isDirectory: true)
        return appDirectory.appendingPathComponent("current-document.json")
    }

    public static func ensureVaultIdentity(vaultRoot: URL) throws -> ReviewVaultIdentity {
        let metadataDirectory = vaultRoot.appendingPathComponent(".clearly", isDirectory: true)
        let identityURL = metadataDirectory.appendingPathComponent("vault.json")
        let decoder = JSONDecoder.reviewState
        if let data = try? Data(contentsOf: identityURL),
           let identity = try? decoder.decode(ReviewVaultIdentity.self, from: data) {
            try validateSchemaVersion(identity.schemaVersion, resource: identityURL.path)
            return identity
        }

        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        let identity = ReviewVaultIdentity(vaultId: "vlt_\(UUID().uuidString.lowercased())")
        try writeJSON(identity, to: identityURL)
        return identity
    }

    public static func manifestURL(vaultId: String, bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws -> URL {
        try appSupportRoot(bundleIdentifier: bundleIdentifier)
            .appendingPathComponent(vaultId, isDirectory: true)
            .appendingPathComponent("manifest.json")
    }

    public static func loadManifest(vaultId: String, bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws -> ReviewManifest {
        let url = try manifestURL(vaultId: vaultId, bundleIdentifier: bundleIdentifier)
        guard let data = try? Data(contentsOf: url) else {
            return ReviewManifest(vaultId: vaultId)
        }
        let manifest = try JSONDecoder.reviewState.decode(ReviewManifest.self, from: data)
        try validateSchemaVersion(manifest.schemaVersion, resource: url.path)
        return manifest
    }

    public static func saveManifest(_ manifest: ReviewManifest, bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws {
        let url = try manifestURL(vaultId: manifest.vaultId, bundleIdentifier: bundleIdentifier)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeJSON(manifest, to: url)
    }

    public static func context(
        for fileURL: URL,
        vaultRoot: URL,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        createIfMissing: Bool = true
    ) throws -> ReviewContextPayload {
        let relativePath = try vaultRelativePath(fileURL: fileURL, vaultRoot: vaultRoot)
        let identity = try ensureVaultIdentity(vaultRoot: vaultRoot)
        var manifest = try loadManifest(vaultId: identity.vaultId, bundleIdentifier: bundleIdentifier)
        let contentHash = try contentHash(for: fileURL)

        let recordIndex = reconciledRecordIndex(
            relativePath: relativePath,
            contentHash: contentHash,
            manifest: manifest
        )

        let record: ReviewRecord
        if let recordIndex {
            manifest.reviews[recordIndex].targetRelativePath = relativePath
            manifest.reviews[recordIndex].targetAbsolutePath = fileURL.path
            manifest.reviews[recordIndex].targetContentHash = contentHash
            record = manifest.reviews[recordIndex]
            try saveManifest(manifest, bundleIdentifier: bundleIdentifier)
        } else if createIfMissing {
            let reviewDirectory = "pending_\(UUID().uuidString.lowercased())"
            record = ReviewRecord(
                targetRelativePath: relativePath,
                targetAbsolutePath: fileURL.path,
                targetContentHash: contentHash,
                commentsCachePath: "\(reviewDirectory)/comments-cache.json"
            )
            manifest.reviews.append(record)
            try saveManifest(manifest, bundleIdentifier: bundleIdentifier)
        } else {
            throw ReviewStateError.missingReviewTarget(relativePath)
        }

        return ReviewContextPayload(
            schemaVersion: schemaVersion,
            generatedAt: Date(),
            freshness: "cache",
            vaultId: identity.vaultId,
            vaultRoot: vaultRoot.path,
            fileId: record.fileId,
            targetRelativePath: record.targetRelativePath,
            targetAbsolutePath: record.targetAbsolutePath,
            targetContentHash: record.targetContentHash,
            vaultURI: "vault://\(identity.vaultId)/\(record.targetRelativePath)",
            reviewId: record.reviewId,
            reviewUrl: record.reviewUrl,
            commentsCachePath: record.commentsCachePath,
            syncedAt: record.syncedAt
        )
    }

    public static func writeCurrentDocument(
        fileURL: URL,
        vaultRoot: URL,
        documentTitle: String,
        appInstanceId: String,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) throws {
        let context = try context(for: fileURL, vaultRoot: vaultRoot, bundleIdentifier: bundleIdentifier)
        let state = CurrentReviewDocumentState(
            appInstanceId: appInstanceId,
            updatedAt: Date(),
            vaultId: context.vaultId,
            vaultRoot: context.vaultRoot,
            fileId: context.fileId,
            targetRelativePath: context.targetRelativePath,
            targetAbsolutePath: context.targetAbsolutePath,
            documentTitle: documentTitle
        )
        let url = try currentDocumentURL(bundleIdentifier: bundleIdentifier)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeJSON(state, to: url)
    }

    public static func readCurrentDocument(bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws -> CurrentReviewDocumentState {
        let url = try currentDocumentURL(bundleIdentifier: bundleIdentifier)
        let data = try Data(contentsOf: url)
        let state = try JSONDecoder.reviewState.decode(CurrentReviewDocumentState.self, from: data)
        guard state.isFresh else {
            throw ReviewStateError.staleCurrentDocument
        }
        return state
    }

    public static func commentsCacheURL(context: ReviewContextPayload, bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws -> URL {
        try appSupportRoot(bundleIdentifier: bundleIdentifier)
            .appendingPathComponent(context.vaultId, isDirectory: true)
            .appendingPathComponent(context.commentsCachePath)
    }

    public static func readCommentsCache(context: ReviewContextPayload, bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws -> ReviewCommentsCache {
        let url = try commentsCacheURL(context: context, bundleIdentifier: bundleIdentifier)
        guard let data = try? Data(contentsOf: url) else {
            return ReviewCommentsCache(reviewId: context.reviewId, syncedAt: context.syncedAt)
        }
        let cache = try JSONDecoder.reviewState.decode(ReviewCommentsCache.self, from: data)
        try validateSchemaVersion(cache.schemaVersion, resource: url.path)
        return cache
    }

    public static func writeCommentsCache(
        _ cache: ReviewCommentsCache,
        context: ReviewContextPayload,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) throws {
        let url = try commentsCacheURL(context: context, bundleIdentifier: bundleIdentifier)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeJSON(cache, to: url)
    }

    public static func pendingResolutionsURL(
        context: ReviewContextPayload,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) throws -> URL {
        let cacheURL = try commentsCacheURL(context: context, bundleIdentifier: bundleIdentifier)
        return cacheURL.deletingLastPathComponent().appendingPathComponent("pending-resolutions.json")
    }

    public static func readPendingResolutions(
        context: ReviewContextPayload,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) throws -> PendingReviewResolutions {
        let url = try pendingResolutionsURL(context: context, bundleIdentifier: bundleIdentifier)
        guard let data = try? Data(contentsOf: url) else {
            return PendingReviewResolutions(reviewId: context.reviewId)
        }
        let pending = try JSONDecoder.reviewState.decode(PendingReviewResolutions.self, from: data)
        try validateSchemaVersion(pending.schemaVersion, resource: url.path)
        return pending
    }

    public static func writePendingResolutions(
        _ pending: PendingReviewResolutions,
        context: ReviewContextPayload,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) throws {
        let url = try pendingResolutionsURL(context: context, bundleIdentifier: bundleIdentifier)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeJSON(pending, to: url)
    }

    public static func withPendingResolutionsLock<T>(
        context: ReviewContextPayload,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        _ body: () async throws -> T
    ) async throws -> T {
        let lockURL = try pendingResolutionsURL(context: context, bundleIdentifier: bundleIdentifier)
            .deletingLastPathComponent()
            .appendingPathComponent("pending-resolutions.lock", isDirectory: true)
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let deadline = Date().addingTimeInterval(10)
        while true {
            do {
                try FileManager.default.createDirectory(at: lockURL, withIntermediateDirectories: false)
                break
            } catch {
                if removeStaleLockIfNeeded(at: lockURL, olderThan: 30) {
                    continue
                }
                if !FileManager.default.fileExists(atPath: lockURL.path) || Date() >= deadline {
                    throw ReviewStateError.localStateLockUnavailable(lockURL.path)
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        defer { try? FileManager.default.removeItem(at: lockURL) }
        return try await body()
    }

    private static func removeStaleLockIfNeeded(at lockURL: URL, olderThan age: TimeInterval) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: lockURL.path) else {
            return false
        }
        let created = attributes[.creationDate] as? Date
        let modified = attributes[.modificationDate] as? Date
        guard let timestamp = [created, modified].compactMap({ $0 }).min() else {
            return false
        }
        guard Date().timeIntervalSince(timestamp) > age else {
            return false
        }
        do {
            try FileManager.default.removeItem(at: lockURL)
            return true
        } catch {
            return false
        }
    }

    public static func updateReviewRecord(
        for fileURL: URL,
        vaultRoot: URL,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        reviewId: String? = nil,
        publisherId: String? = nil,
        keychainAccount: String? = nil,
        reviewUrl: String? = nil,
        latestVersion: Int? = nil,
        targetContentHash: String? = nil,
        syncedAt: Date? = nil
    ) throws -> ReviewContextPayload {
        let relativePath = try vaultRelativePath(fileURL: fileURL, vaultRoot: vaultRoot)
        let identity = try ensureVaultIdentity(vaultRoot: vaultRoot)
        var manifest = try loadManifest(vaultId: identity.vaultId, bundleIdentifier: bundleIdentifier)
        let currentHash = try contentHash(for: fileURL)
        let recordIndex = reconciledRecordIndex(
            relativePath: relativePath,
            contentHash: targetContentHash ?? currentHash,
            manifest: manifest
        )
        guard let index = recordIndex else {
            throw ReviewStateError.missingReviewTarget(relativePath)
        }

        if let reviewId {
            manifest.reviews[index].reviewId = reviewId
            manifest.reviews[index].commentsCachePath = "\(reviewId)/comments-cache.json"
        }
        if let publisherId {
            manifest.reviews[index].publisherId = publisherId
        }
        if let keychainAccount {
            manifest.reviews[index].keychainAccount = keychainAccount
        }
        if let reviewUrl {
            manifest.reviews[index].reviewUrl = reviewUrl
        }
        if let latestVersion {
            manifest.reviews[index].latestVersion = latestVersion
        }
        manifest.reviews[index].targetRelativePath = relativePath
        manifest.reviews[index].targetAbsolutePath = fileURL.path
        manifest.reviews[index].targetContentHash = targetContentHash ?? currentHash
        if let syncedAt {
            manifest.reviews[index].syncedAt = syncedAt
        }

        try saveManifest(manifest, bundleIdentifier: bundleIdentifier)
        return try context(for: fileURL, vaultRoot: vaultRoot, bundleIdentifier: bundleIdentifier)
    }

    public static func reviewRecord(
        context: ReviewContextPayload,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) throws -> ReviewRecord? {
        let manifest = try loadManifest(vaultId: context.vaultId, bundleIdentifier: bundleIdentifier)
        return manifest.reviews.first { $0.fileId == context.fileId }
            ?? manifest.reviews.first { $0.targetRelativePath == context.targetRelativePath }
    }

    public static func writeContextPayload(_ payload: ReviewContextPayload, bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws -> URL {
        let directory = try appSupportRoot(bundleIdentifier: bundleIdentifier)
            .appendingPathComponent(payload.vaultId, isDirectory: true)
            .appendingPathComponent(payload.fileId, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("review-context.json")
        try writeJSON(payload, to: url)
        return url
    }

    public static func vaultRelativePath(fileURL: URL, vaultRoot: URL) throws -> String {
        let target = fileURL.standardizedFileURL.path
        let root = vaultRoot.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard target.hasPrefix(prefix) else {
            throw ReviewStateError.fileOutsideVault(file: target, vault: root)
        }
        return String(target.dropFirst(prefix.count))
    }

    public static func contentHash(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func reconciledRecordIndex(relativePath: String, contentHash: String, manifest: ReviewManifest) -> Int? {
        if let index = manifest.reviews.firstIndex(where: { $0.targetRelativePath == relativePath }) {
            return index
        }
        let hashMatches = manifest.reviews.enumerated().filter { $0.element.targetContentHash == contentHash }
        return hashMatches.count == 1 ? hashMatches[0].offset : nil
    }

    private static func sharedApplicationSupportBase(bundleIdentifier: String?) throws -> URL {
        guard let defaultBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ReviewStateError.applicationSupportUnavailable
        }
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return defaultBase
        }

        let containerBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        if defaultBase.standardizedFileURL.path == containerBase.standardizedFileURL.path {
            return defaultBase
        }
        if FileManager.default.fileExists(atPath: containerBase.path) {
            return containerBase
        }
        if ["com.sabotage.clearly", "com.sabotage.clearly.dev"].contains(bundleIdentifier) {
            try? FileManager.default.createDirectory(at: containerBase, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: containerBase.path) {
                return containerBase
            }
        }
        return defaultBase
    }

    private static func validateSchemaVersion(_ found: Int, resource: String) throws {
        guard found <= schemaVersion else {
            throw ReviewStateError.schemaVersionUnsupported(resource: resource, found: found, supported: schemaVersion)
        }
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder.reviewState
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}

public enum ReviewFilePath {
    public static func parseVaultURI(_ value: String) throws -> (vaultId: String, relativePath: String) {
        guard value.hasPrefix("vault://") else {
            throw ReviewStateError.invalidVaultURI(value)
        }
        let rest = String(value.dropFirst("vault://".count))
        guard let slash = rest.firstIndex(of: "/") else {
            throw ReviewStateError.invalidVaultURI(value)
        }
        let vaultId = String(rest[..<slash])
        let relative = String(rest[rest.index(after: slash)...])
        guard !vaultId.isEmpty, !relative.isEmpty else {
            throw ReviewStateError.invalidVaultURI(value)
        }
        return (vaultId, relative)
    }
}

private extension JSONEncoder {
    static var reviewState: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var reviewState: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
