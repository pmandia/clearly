import AppKit
import SwiftUI
import ClearlyCore

struct ReviewCommentsSidebar: View {
    @Bindable var state: ReviewSidebarState
    let fileURL: URL?
    let vaultRoot: URL?

    @Environment(\.colorScheme) private var colorScheme

    private var activeFileURL: URL? { fileURL ?? state.activeFileURL }
    private var activeVaultRoot: URL? { vaultRoot ?? state.activeVaultRoot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            separator
            content
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 420, maxHeight: .infinity, alignment: .top)
        .background(Theme.outlinePanelBackgroundSwiftUI)
        .onAppear {
            state.reload(fileURL: activeFileURL, vaultRoot: activeVaultRoot)
        }
        .onChange(of: fileURL) { _, newURL in
            state.reloadIfVisible(fileURL: newURL, vaultRoot: activeVaultRoot)
        }
        .onChange(of: vaultRoot) { _, newRoot in
            state.reloadIfVisible(fileURL: activeFileURL, vaultRoot: newRoot)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Review")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()

            Menu {
                Button("Copy Review Link") {
                    copyReviewLink()
                }
                Button("Copy Agent Prompt") {
                    copyReviewPrompt()
                }
                Button("Copy Agent Context Path") {
                    copyReviewContextPath()
                }
                Divider()
                Button("Reload Sidebar") {
                    state.reload(fileURL: activeFileURL, vaultRoot: activeVaultRoot)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("More review actions")

            Button {
                state.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close review")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? Theme.separatorOpacityDark : Theme.separatorOpacity))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let error = state.lastError {
            VStack(alignment: .leading, spacing: 8) {
                Label("Review state unavailable", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(16)
        } else if state.context == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("No document selected.")
                    .font(.headline)
                Text("Open a Markdown file inside a vault.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        } else if let context = state.context, context.reviewId == nil {
            unlinkedReviewContent(context: context)
        } else {
            linkedReviewContent
        }
    }

    private func unlinkedReviewContent(context: ReviewContextPayload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Not shared for review")
                    .font(.headline)
                Text(context.targetRelativePath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                Button {
                    state.createReview()
                } label: {
                    Label("Create Link", systemImage: "link.badge.plus")
                }
                .disabled(state.isBusy)
            }
            .buttonStyle(.borderedProminent)

            if state.isBusy || state.lastActionMessage != nil {
                actionStatus
            }
        }
        .padding(16)
    }

    private var linkedReviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            reviewLinkPanel
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            separator
            if state.isBusy || state.lastActionMessage != nil {
                actionStatus
                separator
            }
            reviewSummary
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, state.cache?.comments.isEmpty == false ? 8 : 0)

            if state.cache?.comments.isEmpty == false {
                Picker("Comment Filter", selection: $state.filter) {
                    ForEach(ReviewCommentsFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            if state.filteredComments.isEmpty {
                emptyComments
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(state.filteredComments, id: \.id) { comment in
                            ReviewCommentRow(
                                comment: comment,
                                isPendingResolution: state.pendingCommentIds.contains(comment.id),
                                onClose: { state.closeComment(comment) },
                                onDelete: { state.deleteComment(comment) }
                            )
                            Divider().padding(.horizontal, 12)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var reviewLinkPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(documentDisplayName)
                    .font(.headline)
                Text("Link ready")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    copyReviewLink()
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)
                .disabled(reviewURL == nil)

                Button {
                    if let reviewURL {
                        NSWorkspace.shared.open(reviewURL)
                    }
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.bordered)
                .disabled(reviewURL == nil)
            }

            HStack(spacing: 8) {
                Button {
                    state.syncCurrent()
                } label: {
                    Label("Fetch Comments", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(state.isBusy || state.context?.reviewId == nil)

                Button {
                    state.publishCurrentVersion()
                } label: {
                    Label("Publish Update", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(state.isBusy || state.context?.reviewId == nil)
            }
            .controlSize(.small)
        }
    }

    private var actionStatus: some View {
        HStack(spacing: 8) {
            if state.isBusy {
                ProgressView()
                    .controlSize(.small)
                Text("Working...")
                    .font(.callout)
            } else if let message = state.lastActionMessage {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.tint)
                Text(message)
                    .font(.callout)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var reviewSummary: some View {
        let comments = state.cache?.comments ?? []
        let openCount = comments.filter { $0.status == "open" || $0.status.isEmpty }.count

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Comments")
                    .font(.headline)
                Spacer()
                Text(actionItemLabel(openCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(syncLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyComments: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.filter.emptyTitle)
                .font(.headline)
            Text(syncLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var reviewURL: URL? {
        ReviewLinkFormatter.absoluteURL(state.context?.reviewUrl)
    }

    private var documentDisplayName: String {
        guard let target = state.context?.targetRelativePath, !target.isEmpty else {
            return "Current document"
        }
        return target.split(separator: "/").last.map(String.init) ?? target
    }

    private func actionItemLabel(_ count: Int) -> String {
        count == 1 ? "1 action item" : "\(count) action items"
    }

    private var syncLabel: String {
        let syncedAt = state.cache?.syncedAt ?? state.context?.syncedAt
        guard let syncedAt else { return "Never synced" }
        return "Synced \(syncedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func copyReviewLink() {
        guard let activeFileURL, let activeVaultRoot else { return }
        CopyActions.copyReviewLink(activeFileURL, vaultRoot: activeVaultRoot)
    }

    private func copyReviewPrompt() {
        guard let activeFileURL, let activeVaultRoot else { return }
        CopyActions.copyReviewPrompt(activeFileURL, vaultRoot: activeVaultRoot)
    }

    private func copyReviewContextPath() {
        guard let activeFileURL, let activeVaultRoot else { return }
        CopyActions.copyReviewContextPath(activeFileURL, vaultRoot: activeVaultRoot)
    }
}

private struct ReviewCommentRow: View {
    let comment: ReviewComment
    let isPendingResolution: Bool
    let onClose: () -> Void
    let onDelete: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(displayAuthor)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                if let visibleStatusLabel {
                    Text(visibleStatusLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusColor)
                }

                if let placementLabel {
                    Text(placementLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if isPendingResolution {
                    Text("pending")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tint)
                }

                Spacer(minLength: 0)

                Text(timestampLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(comment.body)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let selectedText = comment.selectedText, !selectedText.isEmpty {
                Text(selectedText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                    .textSelection(.enabled)
            }

            if let suggestedReplacement = comment.suggestedReplacement, !suggestedReplacement.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Suggested replacement")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(suggestedReplacement)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .textSelection(.enabled)
                }
            }

            if canMutate {
                HStack(spacing: 10) {
                    if statusLabel == "open" {
                        Button("Dismiss") {
                            onClose()
                        }
                        .buttonStyle(.borderless)
                        .help("Keep this comment in history, but remove it from Needs Action.")
                    }

                    Button(confirmDelete ? "Confirm Delete" : "Delete", role: .destructive) {
                        if confirmDelete {
                            onDelete()
                        } else {
                            confirmDelete = true
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Hide this comment from normal review lists.")

                    if confirmDelete {
                        Button("Cancel") {
                            confirmDelete = false
                        }
                        .buttonStyle(.borderless)
                    }

                    Spacer(minLength: 0)
                    Text("v\(comment.version)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 12))
                .disabled(isPendingResolution)
            } else {
                HStack {
                    Spacer(minLength: 0)
                    Text("v\(comment.version)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusLabel: String {
        comment.status.isEmpty ? "open" : comment.status
    }

    private var statusColor: Color {
        switch comment.status {
        case "resolved", "closed":
            return .secondary
        default:
            return .accentColor
        }
    }

    private var visibleStatusLabel: String? {
        switch statusLabel {
        case "open":
            return nil
        case "closed":
            return "Dismissed"
        case "resolved":
            return "Done"
        default:
            return statusLabel.capitalized
        }
    }

    private var canMutate: Bool {
        comment.status != "resolved" && comment.status != "deleted"
    }

    private var displayAuthor: String {
        let trimmed = comment.author.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Reviewer" : trimmed
    }

    private var effectiveAnchor: ReviewAnchor {
        comment.currentAnchor ?? comment.anchor
    }

    private var effectiveConfidence: ReviewAnchorConfidence {
        comment.anchorConfidence ?? effectiveAnchor.confidence
    }

    private var placementLabel: String? {
        if comment.orphaned { return "Unplaced" }
        switch effectiveConfidence {
        case .exact:
            return nil
        case .fuzzy:
            return "Remapped"
        case .section:
            return "Section only"
        case .orphan:
            return "Unplaced"
        }
    }

    private var timestampLabel: String {
        guard let date = comment.updatedAt ?? comment.createdAt else { return "" }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
