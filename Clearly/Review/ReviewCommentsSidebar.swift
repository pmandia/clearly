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
            Text("REVIEW")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(1.5)
            Spacer()

            if let reviewURL {
                Button {
                    NSWorkspace.shared.open(reviewURL)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Open review link")
            }

            Button {
                state.syncCurrent()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(state.isBusy || state.context?.reviewId == nil)
            .help("Sync review comments")

            Button {
                state.publishCurrentVersion()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(state.isBusy || state.context?.reviewId == nil)
            .help("Publish new review version")

            Menu {
                Button("Copy Review Link") {
                    copyReviewLink()
                }
                Button("Copy Review Prompt") {
                    copyReviewPrompt()
                }
                Button("Copy Review Context Path") {
                    copyReviewContextPath()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Review copy actions")

            Button {
                state.reload(fileURL: activeFileURL, vaultRoot: activeVaultRoot)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Reload cached comments")

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
                Text("No hosted review linked.")
                    .font(.headline)
                Text(context.vaultURI)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Button {
                    state.createReview()
                } label: {
                    Label("Share", systemImage: "person.2.badge.plus")
                }
                .disabled(state.isBusy)
                Button {
                    copyReviewPrompt()
                } label: {
                    Label("Prompt", systemImage: "text.quote")
                }
                Button {
                    copyReviewContextPath()
                } label: {
                    Label("Context", systemImage: "doc.badge.gearshape")
                }
            }
            .buttonStyle(.bordered)

            if state.isBusy || state.lastActionMessage != nil {
                actionStatus
            }
        }
        .padding(16)
    }

    private var linkedReviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            reviewSummary
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            separator
            if state.isBusy || state.lastActionMessage != nil {
                actionStatus
                separator
            }
            Picker("Comment Filter", selection: $state.filter) {
                ForEach(ReviewCommentsFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if state.filteredComments.isEmpty {
                emptyComments
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(state.filteredComments, id: \.id) { comment in
                            ReviewCommentRow(
                                comment: comment,
                                isPendingResolution: state.pendingCommentIds.contains(comment.id)
                            )
                            Divider().padding(.horizontal, 12)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
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
        let openCount = comments.filter { $0.status != "resolved" }.count
        let resolvedCount = comments.filter { $0.status == "resolved" }.count
        let pendingCount = state.pendingResolutions.pending.count

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(openCount) open")
                    .font(.headline)
                Text("\(resolvedCount) resolved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if pendingCount > 0 {
                    Text("\(pendingCount) pending")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
                Spacer()
            }
            Text(syncLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let context = state.context {
                Text(context.vaultURI)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    private var emptyComments: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No \(state.filter.label.lowercased()) comments.")
                .font(.headline)
            Text(syncLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var reviewURL: URL? {
        guard let raw = state.context?.reviewUrl else { return nil }
        return URL(string: raw)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(comment.author.isEmpty ? "Reviewer" : comment.author)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(statusLabel)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
                if isPendingResolution {
                    Text("pending")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
                Spacer(minLength: 0)
                Text("v\(comment.version)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(comment.body)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let selectedText = comment.selectedText, !selectedText.isEmpty {
                Text(selectedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(8)
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

            HStack(spacing: 6) {
                Text(anchorLabel)
                Text(effectiveConfidence.rawValue)
                if comment.orphaned {
                    Text("unplaced")
                        .foregroundStyle(.orange)
                }
                Text(comment.id)
                    .truncationMode(.middle)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var statusLabel: String {
        comment.status.isEmpty ? "open" : comment.status
    }

    private var statusColor: Color {
        comment.status == "resolved" ? .secondary : .accentColor
    }

    private var anchorLabel: String {
        switch effectiveAnchor.blockType {
        case .paragraph: return "paragraph"
        case .heading: return "heading"
        case .listItem: return "list"
        case .quote: return "quote"
        case .code: return "code"
        case .table: return "table"
        case .math: return "math"
        case .mermaid: return "mermaid"
        case .image: return "image"
        case .frontmatter: return "frontmatter"
        case .multiBlock: return "multi-block"
        }
    }

    private var effectiveAnchor: ReviewAnchor {
        comment.currentAnchor ?? comment.anchor
    }

    private var effectiveConfidence: ReviewAnchorConfidence {
        comment.anchorConfidence ?? effectiveAnchor.confidence
    }
}
