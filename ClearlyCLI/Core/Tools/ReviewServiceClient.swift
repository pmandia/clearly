import Foundation
import ClearlyCore

#if canImport(Security)
import Security
#endif

struct ReviewServiceRemappedComment: Codable, Equatable {
    let commentId: String
    let confidence: String
    let reason: String?
    let anchor: ReviewAnchor?
    let remappedVersion: Int?
}

struct ReviewPublishVersionResponse: Codable, Equatable {
    let reviewId: String
    let version: Int
    let snapshotUrl: String
    let createdAt: Date?
    let remappedComments: [ReviewServiceRemappedComment]
}

struct ReviewCreateResponse: Codable, Equatable {
    let reviewId: String
    let reviewUrl: String
    let publicReviewToken: String
    let accessToken: String
    let keychainAccount: String
    let publisherId: String
    let version: Int
    let snapshotUrl: String
    let createdAt: Date?
}

struct ReviewResolveResponse: Codable, Equatable {
    let status: String
    let resolvedBy: String
    let resolvedAt: Date?
    let resolutionNote: String?
    let remoteRevision: Int
}

struct ReviewDeleteResponse: Codable, Equatable {
    let deleted: Bool
    let status: String
    let remoteRevision: Int
}

struct ReviewForkSummary: Codable, Equatable {
    let forkId: String
    let version: Int
    let authorDisplayName: String
    let createdAt: Date?
    let diffSummary: ReviewForkDiffSummary?
}

struct ReviewForkDiffSummary: Codable, Equatable {
    let additions: Int
    let deletions: Int
    let changedSections: [String]
}

struct ReviewForkDetail: Codable, Equatable {
    let forkId: String
    let reviewId: String
    let version: Int
    let authorId: String
    let authorDisplayName: String
    let createdAt: Date?
    let markdownSource: String?
    let markdownUrl: String
    let markdownUrlExpiresAt: Date?
    let diff: ReviewForkDiff
}

struct ReviewForkDiff: Codable, Equatable {
    let schemaVersion: Int
    let baseVersion: Int
    let algorithm: String
    let hunks: [ReviewForkDiffHunk]
}

struct ReviewForkDiffHunk: Codable, Equatable {
    let oldStart: Int
    let oldLines: Int
    let newStart: Int
    let newLines: Int
    let lines: [ReviewForkDiffLine]
}

struct ReviewForkDiffLine: Codable, Equatable {
    let type: String
    let text: String
}

private struct ReviewCommentsPage: Decodable {
    let reviewId: String
    let revision: String?
    let comments: [ReviewComment]
    let nextCursor: String?
}

private struct ReviewForksPage: Decodable {
    let reviewId: String
    let forks: [ReviewForkSummary]
    let nextCursor: String?
}

private struct ReviewResolveRequest: Encodable {
    let expectedRevision: Int
    let resolvedBy: String
    let resolutionNote: String
}

private struct ReviewCloseRequest: Encodable {
    let expectedRevision: Int
    let closedBy: String
    let resolutionNote: String
}

private struct ReviewDeleteRequest: Encodable {
    let expectedRevision: Int
    let deletedBy: String
}

struct ReviewServiceConfiguration {
    let baseURL: URL
    let publisherToken: String

    static func load(record: ReviewRecord?) throws -> ReviewServiceConfiguration {
        guard let rawBaseURL = ProcessInfo.processInfo.environment["CLEARLY_REVIEW_API_BASE_URL"],
              !rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let baseURL = URL(string: rawBaseURL) else {
            throw ToolError.serviceUnavailable("Set CLEARLY_REVIEW_API_BASE_URL to the hosted Clearly Review API base URL.")
        }
        let token = try ReviewCredentialStore.publisherToken(record: record)
        return ReviewServiceConfiguration(baseURL: baseURL, publisherToken: token)
    }
}

enum ReviewCredentialStore {
    static func publisherToken(record: ReviewRecord?) throws -> String {
        if let envToken = ProcessInfo.processInfo.environment["CLEARLY_REVIEW_PUBLISHER_TOKEN"],
           !envToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envToken
        }

        guard let account = record?.keychainAccount, !account.isEmpty else {
            throw ToolError.unauthenticated("No publisher token is available. Set CLEARLY_REVIEW_PUBLISHER_TOKEN or link a review with a Keychain account.")
        }

        #if canImport(Security)
        return try readKeychainPassword(account: account)
        #else
        throw ToolError.unauthenticated("Keychain is unavailable in this build and CLEARLY_REVIEW_PUBLISHER_TOKEN is not set.")
        #endif
    }

    static func storePublisherToken(_ token: String, account: String) throws {
        #if canImport(Security)
        try writeKeychainPassword(token, account: account)
        #else
        _ = token
        _ = account
        #endif
    }

    #if canImport(Security)
    private static func readKeychainPassword(account: String) throws -> String {
        let services = ["Clearly Review", "com.sabotage.clearly.review"]
        for service in services {
            var item: CFTypeRef?
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status != errSecItemNotFound else { continue }
            guard status == errSecSuccess else {
                throw ToolError.unauthenticated("Could not read publisher token from Keychain account \(account) (status \(status)).")
            }
            guard let data = item as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
                throw ToolError.unauthenticated("Publisher token in Keychain account \(account) is empty or not UTF-8.")
            }
            return token
        }

        throw ToolError.unauthenticated("No publisher token found in Keychain account \(account).")
    }

    private static func writeKeychainPassword(_ token: String, account: String) throws {
        let service = "Clearly Review"
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw ToolError.unauthenticated("Could not update publisher token in Keychain account \(account) (status \(updateStatus)).")
        }

        var createQuery = query
        createQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(createQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw ToolError.unauthenticated("Could not store publisher token in Keychain account \(account) (status \(addStatus)).")
        }
    }
    #endif
}

final class ReviewServiceClient {
    private let configuration: ReviewServiceConfiguration
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(configuration: ReviewServiceConfiguration) {
        self.configuration = configuration
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func createReview(
        markdown: String,
        title: String,
        targetRelativePath: String,
        vaultId: String
    ) async throws -> ReviewCreateResponse {
        guard markdown.utf8.count <= 2_000_000 else {
            throw ToolError.payloadTooLarge("Markdown source exceeds the 2 MB review publish cap.")
        }

        let snapshot = ReviewSnapshotRenderer.render(markdown: markdown, title: title)
        guard snapshot.html.utf8.count <= 5_000_000 else {
            throw ToolError.payloadTooLarge("Rendered snapshot exceeds the 5 MB review publish cap.")
        }

        let sourceMapData = try encoder.encode(snapshot.sourceMap)
        let fields = [
            "title": title,
            "targetRelativePath": targetRelativePath,
            "vaultId": vaultId,
            "contentHash": snapshot.contentHash,
            "anchorNormalizerVersion": "\(snapshot.anchorNormalizerVersion)"
        ]
        let files = [
            MultipartFile(name: "snapshotHtml", filename: "snapshot.html", contentType: "text/html", data: Data(snapshot.html.utf8)),
            MultipartFile(name: "markdownSource", filename: "source.md", contentType: "text/markdown", data: Data(markdown.utf8)),
            MultipartFile(name: "sourceMapJson", filename: "source-map.json", contentType: "application/json", data: sourceMapData)
        ]

        let response: ReviewCreateResponse = try await multipartRequest(
            method: "POST",
            path: ["api", "reviews"],
            fields: fields,
            files: files
        )
        try ReviewCredentialStore.storePublisherToken(response.accessToken, account: response.keychainAccount)
        return normalized(response)
    }

    func fetchAllComments(reviewId: String) async throws -> ReviewCommentsCache {
        var comments: [ReviewComment] = []
        var cursor: String?
        var latestRevision: String?

        repeat {
            var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: "250")]
            if let cursor {
                query.append(URLQueryItem(name: "cursor", value: cursor))
            }
            let page: ReviewCommentsPage = try await request(
                method: "GET",
                path: ["api", "reviews", reviewId, "comments"],
                query: query
            )
            latestRevision = page.revision ?? latestRevision
            comments.append(contentsOf: page.comments)
            cursor = page.nextCursor
        } while cursor != nil

        return ReviewCommentsCache(
            reviewId: reviewId,
            remoteRevision: latestRevision,
            syncedAt: Date(),
            freshness: "latest",
            comments: comments
        )
    }

    func publishVersion(reviewId: String, markdown: String, title: String) async throws -> ReviewPublishVersionResponse {
        guard markdown.utf8.count <= 2_000_000 else {
            throw ToolError.payloadTooLarge("Markdown source exceeds the 2 MB review publish cap.")
        }

        let snapshot = ReviewSnapshotRenderer.render(markdown: markdown, title: title)
        guard snapshot.html.utf8.count <= 5_000_000 else {
            throw ToolError.payloadTooLarge("Rendered snapshot exceeds the 5 MB review publish cap.")
        }

        let sourceMapData = try encoder.encode(snapshot.sourceMap)
        let fields = [
            "contentHash": snapshot.contentHash,
            "anchorNormalizerVersion": "\(snapshot.anchorNormalizerVersion)"
        ]
        let files = [
            MultipartFile(name: "snapshotHtml", filename: "snapshot.html", contentType: "text/html", data: Data(snapshot.html.utf8)),
            MultipartFile(name: "markdownSource", filename: "source.md", contentType: "text/markdown", data: Data(markdown.utf8)),
            MultipartFile(name: "sourceMapJson", filename: "source-map.json", contentType: "application/json", data: sourceMapData)
        ]

        let response: ReviewPublishVersionResponse = try await multipartRequest(
            method: "POST",
            path: ["api", "reviews", reviewId, "versions"],
            fields: fields,
            files: files
        )
        return normalized(response)
    }

    func resolveComment(
        reviewId: String,
        commentId: String,
        expectedRevision: Int,
        resolvedBy: String,
        note: String
    ) async throws -> ReviewResolveResponse {
        try await request(
            method: "POST",
            path: ["api", "reviews", reviewId, "comments", commentId, "resolve"],
            body: ReviewResolveRequest(
                expectedRevision: expectedRevision,
                resolvedBy: resolvedBy,
                resolutionNote: note
            )
        )
    }

    func closeComment(
        reviewId: String,
        commentId: String,
        expectedRevision: Int,
        closedBy: String,
        note: String
    ) async throws -> ReviewResolveResponse {
        try await request(
            method: "POST",
            path: ["api", "reviews", reviewId, "comments", commentId, "close"],
            body: ReviewCloseRequest(
                expectedRevision: expectedRevision,
                closedBy: closedBy,
                resolutionNote: note
            )
        )
    }

    func deleteComment(
        reviewId: String,
        commentId: String,
        expectedRevision: Int,
        deletedBy: String
    ) async throws -> ReviewDeleteResponse {
        try await request(
            method: "DELETE",
            path: ["api", "reviews", reviewId, "comments", commentId],
            body: ReviewDeleteRequest(
                expectedRevision: expectedRevision,
                deletedBy: deletedBy
            )
        )
    }

    func fetchForks(reviewId: String) async throws -> [ReviewForkSummary] {
        var forks: [ReviewForkSummary] = []
        var cursor: String?

        repeat {
            var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: "250")]
            if let cursor {
                query.append(URLQueryItem(name: "cursor", value: cursor))
            }
            let page: ReviewForksPage = try await request(
                method: "GET",
                path: ["api", "reviews", reviewId, "forks"],
                query: query
            )
            forks.append(contentsOf: page.forks)
            cursor = page.nextCursor
        } while cursor != nil

        return forks
    }

    func fetchFork(reviewId: String, forkId: String) async throws -> ReviewForkDetail {
        let detail: ReviewForkDetail = try await request(
            method: "GET",
            path: ["api", "reviews", reviewId, "forks", forkId]
        )
        let normalizedMarkdownURL = absoluteURLString(detail.markdownUrl)
        guard detail.markdownSource == nil else {
            return ReviewForkDetail(
                forkId: detail.forkId,
                reviewId: detail.reviewId,
                version: detail.version,
                authorId: detail.authorId,
                authorDisplayName: detail.authorDisplayName,
                createdAt: detail.createdAt,
                markdownSource: detail.markdownSource,
                markdownUrl: normalizedMarkdownURL,
                markdownUrlExpiresAt: detail.markdownUrlExpiresAt,
                diff: detail.diff
            )
        }
        let markdown = try await fetchMarkdown(urlString: normalizedMarkdownURL)
        return ReviewForkDetail(
            forkId: detail.forkId,
            reviewId: detail.reviewId,
            version: detail.version,
            authorId: detail.authorId,
            authorDisplayName: detail.authorDisplayName,
            createdAt: detail.createdAt,
            markdownSource: markdown,
            markdownUrl: normalizedMarkdownURL,
            markdownUrlExpiresAt: detail.markdownUrlExpiresAt,
            diff: detail.diff
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        method: String,
        path: [String],
        query: [URLQueryItem] = [],
        body: Body
    ) async throws -> Response {
        var request = URLRequest(url: url(path: path, query: query))
        request.httpMethod = method
        request.setValue("Bearer \(configuration.publisherToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func request<Response: Decodable>(
        method: String,
        path: [String],
        query: [URLQueryItem] = []
    ) async throws -> Response {
        var request = URLRequest(url: url(path: path, query: query))
        request.httpMethod = method
        request.setValue("Bearer \(configuration.publisherToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(request)
    }

    private func multipartRequest<Response: Decodable>(
        method: String,
        path: [String],
        fields: [String: String],
        files: [MultipartFile]
    ) async throws -> Response {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(configuration.publisherToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = MultipartBodyEncoder.encode(fields: fields, files: files, boundary: boundary)
        return try await perform(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ToolError.networkUnreachable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ToolError.networkUnreachable("Review service returned a non-HTTP response.")
        }

        guard (200..<300).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, data: data)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ToolError.schemaVersionUnsupported("Could not decode review API response: \(error.localizedDescription)")
        }
    }

    private func fetchMarkdown(urlString: String) async throws -> String {
        guard let url = URL(string: absoluteURLString(urlString)) else {
            throw ToolError.schemaVersionUnsupported("Review API returned an invalid fork Markdown URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/markdown", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ToolError.networkUnreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ToolError.networkUnreachable("Review service returned a non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw mapHTTPError(statusCode: http.statusCode, data: data)
        }
        guard data.count <= 2_000_000 else {
            throw ToolError.payloadTooLarge("Fork Markdown exceeds the 2 MB import cap.")
        }
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw ToolError.schemaVersionUnsupported("Fork Markdown response was not UTF-8.")
        }
        return markdown
    }

    private func url(path: [String], query: [URLQueryItem] = []) -> URL {
        var base = configuration.baseURL
        for component in path {
            base.appendPathComponent(component)
        }
        guard !query.isEmpty, var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base
        }
        components.queryItems = query
        return components.url ?? base
    }

    private func normalized(_ response: ReviewCreateResponse) -> ReviewCreateResponse {
        ReviewCreateResponse(
            reviewId: response.reviewId,
            reviewUrl: absoluteURLString(response.reviewUrl),
            publicReviewToken: response.publicReviewToken,
            accessToken: response.accessToken,
            keychainAccount: response.keychainAccount,
            publisherId: response.publisherId,
            version: response.version,
            snapshotUrl: absoluteURLString(response.snapshotUrl),
            createdAt: response.createdAt
        )
    }

    private func normalized(_ response: ReviewPublishVersionResponse) -> ReviewPublishVersionResponse {
        ReviewPublishVersionResponse(
            reviewId: response.reviewId,
            version: response.version,
            snapshotUrl: absoluteURLString(response.snapshotUrl),
            createdAt: response.createdAt,
            remappedComments: response.remappedComments
        )
    }

    private func absoluteURLString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            return trimmed
        }
        guard trimmed.hasPrefix("/") else {
            return trimmed
        }
        return URL(string: trimmed, relativeTo: configuration.baseURL)?.absoluteURL.absoluteString ?? trimmed
    }

    private func mapHTTPError(statusCode: Int, data: Data) -> ToolError {
        let message = apiErrorMessage(from: data) ?? "HTTP \(statusCode)"
        switch statusCode {
        case 401:
            return .unauthenticated(message)
        case 403:
            return .forbidden(message)
        case 404:
            return .reviewNotFound(message)
        case 409:
            return .remoteRevisionConflict(message)
        case 413:
            return .payloadTooLarge(message)
        case 429:
            return .rateLimited(message)
        case 500...599:
            return .serviceUnavailable(message)
        default:
            return .networkUnreachable(message)
        }
    }

    private func apiErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        return object["message"] as? String
            ?? (object["error"] as? [String: Any])?["message"] as? String
            ?? object["error"] as? String
    }
}

private struct MultipartFile {
    let name: String
    let filename: String
    let contentType: String
    let data: Data
}

private enum MultipartBodyEncoder {
    static func encode(fields: [String: String], files: [MultipartFile], boundary: String) -> Data {
        var body = Data()
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendUTF8("\(value)\r\n")
        }
        for file in files {
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\r\n")
            body.appendUTF8("Content-Type: \(file.contentType)\r\n\r\n")
            body.append(file.data)
            body.appendUTF8("\r\n")
        }
        body.appendUTF8("--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
