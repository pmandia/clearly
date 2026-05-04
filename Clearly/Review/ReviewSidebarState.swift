import Foundation
import ClearlyCore

enum ReviewCommentsFilter: String, CaseIterable, Identifiable {
    case open
    case resolved
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: return "Open"
        case .resolved: return "Resolved"
        case .all: return "All"
        }
    }
}

@Observable
@MainActor
final class ReviewSidebarState {
    var isVisible = false
    var filter: ReviewCommentsFilter = .open
    var context: ReviewContextPayload?
    var cache: ReviewCommentsCache?
    var pendingResolutions = PendingReviewResolutions()
    var isBusy = false
    var lastActionMessage: String?
    var lastError: String?
    private(set) var activeFileURL: URL?
    private(set) var activeVaultRoot: URL?

    var pendingCommentIds: Set<String> {
        Set(pendingResolutions.pending.map(\.commentId))
    }

    var filteredComments: [ReviewComment] {
        let comments = cache?.comments ?? []
        let filtered: [ReviewComment]
        switch filter {
        case .open:
            filtered = comments.filter { $0.status != "resolved" }
        case .resolved:
            filtered = comments.filter { $0.status == "resolved" }
        case .all:
            filtered = comments
        }
        return filtered.sorted { lhs, rhs in
            let lhsDate = lhs.updatedAt ?? lhs.createdAt ?? .distantPast
            let rhsDate = rhs.updatedAt ?? rhs.createdAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.id < rhs.id
        }
    }

    func toggle(fileURL: URL?, vaultRoot: URL?) {
        isVisible.toggle()
        if isVisible {
            reload(fileURL: fileURL, vaultRoot: vaultRoot)
        }
    }

    func show(fileURL: URL?, vaultRoot: URL?) {
        isVisible = true
        reload(fileURL: fileURL, vaultRoot: vaultRoot)
    }

    func hide() {
        isVisible = false
    }

    func reloadCurrent() {
        reload(fileURL: activeFileURL, vaultRoot: activeVaultRoot)
    }

    func reloadIfVisible(fileURL: URL?, vaultRoot: URL?) {
        guard isVisible else { return }
        reload(fileURL: fileURL, vaultRoot: vaultRoot)
    }

    func reload(fileURL: URL?, vaultRoot: URL?) {
        activeFileURL = fileURL
        activeVaultRoot = vaultRoot

        guard let fileURL, let vaultRoot else {
            context = nil
            cache = nil
            pendingResolutions = PendingReviewResolutions()
            lastError = nil
            return
        }

        do {
            let context = try ReviewStateStore.context(for: fileURL, vaultRoot: vaultRoot)
            self.context = context
            self.cache = try ReviewStateStore.readCommentsCache(context: context)
            self.pendingResolutions = try ReviewStateStore.readPendingResolutions(context: context)
            self.lastError = nil
        } catch {
            self.context = nil
            self.cache = nil
            self.pendingResolutions = PendingReviewResolutions()
            self.lastError = String(describing: error)
        }
    }

    func syncCurrent() {
        runRemoteAction("sync")
    }

    func createReview() {
        runRemoteAction("create")
    }

    func publishCurrentVersion() {
        runRemoteAction("publish")
    }

    private func runRemoteAction(_ action: String) {
        guard let activeFileURL, let activeVaultRoot else { return }
        isBusy = true
        lastActionMessage = nil
        lastError = nil

        Task {
            let result = await ReviewCLIActionRunner.runReviewAction(
                action,
                fileURL: activeFileURL,
                vaultRoot: activeVaultRoot,
                bundleIdentifier: Bundle.main.bundleIdentifier
            )
            await MainActor.run {
                isBusy = false
                if result.succeeded {
                    switch action {
                    case "create":
                        lastActionMessage = "Created hosted review."
                    case "publish":
                        lastActionMessage = "Published new review version."
                    default:
                        lastActionMessage = "Synced review comments."
                    }
                    reload(fileURL: activeFileURL, vaultRoot: activeVaultRoot)
                } else {
                    lastError = result.displayMessage
                }
            }
        }
    }
}
