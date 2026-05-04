import AppKit
import ClearlyCore

enum CopyActions {
    static func copyFilePath(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.path, forType: .string)
    }

    static func copyFileName(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.lastPathComponent, forType: .string)
    }

    static func copyRelativePath(_ url: URL, vaultRoot: URL) {
        let target = url.standardizedFileURL.path
        let root = vaultRoot.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        let relative: String
        if target == root {
            relative = ""
        } else if target.hasPrefix(prefix) {
            relative = String(target.dropFirst(prefix.count))
        } else {
            relative = url.lastPathComponent
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(relative, forType: .string)
    }

    static func copyWikiLink(_ target: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("[[\(target)]]", forType: .string)
    }

    static func copyReviewLink(_ url: URL, vaultRoot: URL) {
        let text: String
        do {
            let context = try ReviewStateStore.context(for: url, vaultRoot: vaultRoot)
            text = ReviewLinkFormatter.absoluteString(context.reviewUrl)
                ?? "No review link exists yet for \(context.vaultURI). Use Create Review Link after the review service is configured."
        } catch {
            text = "Unable to resolve review link for \(url.path): \(error)"
        }
        copyString(text)
    }

    static func copyReviewPrompt(_ url: URL, vaultRoot: URL) {
        let text: String
        do {
            let context = try ReviewStateStore.context(for: url, vaultRoot: vaultRoot)
            text = reviewPrompt(for: context)
        } catch {
            text = "Use the Clearly MCP server to fetch the latest open review comments for:\n\(url.path)\n\nAddress the comments with minimal edits, preserve the author's voice, and summarize what changed.\n\nClearly could not resolve a vault review context: \(error)"
        }
        copyString(text)
    }

    static func copyReviewContextPath(_ url: URL, vaultRoot: URL) {
        let text: String
        do {
            let context = try ReviewStateStore.context(for: url, vaultRoot: vaultRoot)
            let contextURL = try ReviewStateStore.writeContextPayload(context)
            text = contextURL.path
        } catch {
            text = "Unable to write review context for \(url.path): \(error)"
        }
        copyString(text)
    }

    static func copyMarkdown(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func copyHTML(_ text: String) {
        let html = MarkdownRenderer.renderHTML(text)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(html, forType: .html)
        pb.setString(html, forType: .string)
    }

    static func copyRichText(_ text: String) {
        let html = MarkdownRenderer.renderHTML(text)
        guard let data = html.data(using: .utf8),
              let attributed = NSAttributedString(html: data, documentAttributes: nil) else {
            // Fall back to plain HTML if conversion fails
            copyHTML(text)
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        if let rtfData = attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]) {
            pb.setData(rtfData, forType: .rtf)
        }
        pb.setString(attributed.string, forType: .string)
    }

    static func copyPlainText(_ text: String) {
        let html = MarkdownRenderer.renderHTML(text)
        let plain: String
        if let data = html.data(using: .utf8),
           let attributed = NSAttributedString(html: data, documentAttributes: nil) {
            plain = attributed.string
        } else {
            // Fall back: strip HTML tags with regex
            plain = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(plain, forType: .string)
    }

    private static func copyString(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private static func reviewPrompt(for context: ReviewContextPayload) -> String {
        var lines: [String] = [
            "Use the Clearly MCP server to fetch the latest open review comments for:",
            context.vaultURI,
            "",
            "Local fallback path:",
            context.targetAbsolutePath,
            "",
            "Address the comments with minimal edits, preserve the author's voice, and summarize what changed.",
            "Stage proposed comment resolutions, but do not confirm remote resolution until I review the diff."
        ]
        if context.reviewId == nil {
            lines.append("")
            lines.append("No hosted review is linked yet in Clearly ReviewState; if MCP reports review_not_found, create or sync a review for this document first.")
        }
        return lines.joined(separator: "\n")
    }

    /// Reads markdown content from a file URL, using security-scoped access if needed.
    static func readMarkdown(from url: URL) -> String? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Builds an NSMenu with all copy items for a given file URL.
    static func copySubmenu(for url: URL, target: AnyObject) -> NSMenu {
        let sub = NSMenu(title: "Copy")

        let pathItem = NSMenuItem(title: "Copy File Path", action: #selector(CopyMenuActions.copyFilePathAction(_:)), keyEquivalent: "")
        pathItem.representedObject = url
        pathItem.target = target
        sub.addItem(pathItem)

        let nameItem = NSMenuItem(title: "Copy File Name", action: #selector(CopyMenuActions.copyFileNameAction(_:)), keyEquivalent: "")
        nameItem.representedObject = url
        nameItem.target = target
        sub.addItem(nameItem)

        sub.addItem(.separator())

        let mdItem = NSMenuItem(title: "Copy Markdown", action: #selector(CopyMenuActions.copyMarkdownAction(_:)), keyEquivalent: "")
        mdItem.representedObject = url
        mdItem.target = target
        sub.addItem(mdItem)

        let htmlItem = NSMenuItem(title: "Copy HTML", action: #selector(CopyMenuActions.copyHTMLAction(_:)), keyEquivalent: "")
        htmlItem.representedObject = url
        htmlItem.target = target
        sub.addItem(htmlItem)

        let richItem = NSMenuItem(title: "Copy Rich Text", action: #selector(CopyMenuActions.copyRichTextAction(_:)), keyEquivalent: "")
        richItem.representedObject = url
        richItem.target = target
        sub.addItem(richItem)

        let plainItem = NSMenuItem(title: "Copy Plain Text", action: #selector(CopyMenuActions.copyPlainTextAction(_:)), keyEquivalent: "")
        plainItem.representedObject = url
        plainItem.target = target
        sub.addItem(plainItem)

        return sub
    }
}

enum ReviewLinkFormatter {
    static func absoluteString(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        if let url = URL(string: raw), url.scheme != nil {
            return raw
        }
        guard raw.hasPrefix("/"),
              let baseURL = reviewServiceBaseURL() else {
            return raw
        }
        return URL(string: raw, relativeTo: baseURL)?.absoluteURL.absoluteString ?? raw
    }

    static func absoluteURL(_ raw: String?) -> URL? {
        guard let absolute = absoluteString(raw) else { return nil }
        guard let url = URL(string: absolute), url.scheme != nil else { return nil }
        return url
    }

    private static func reviewServiceBaseURL() -> URL? {
        guard let raw = ProcessInfo.processInfo.environment["CLEARLY_REVIEW_API_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        let normalized = raw.hasPrefix("http://") || raw.hasPrefix("https://")
            ? raw
            : "https://\(raw)"
        return URL(string: normalized)
    }
}

/// Objective-C selectors for NSMenu actions.
@objc protocol CopyMenuActions {
    func copyFilePathAction(_ sender: NSMenuItem)
    func copyFileNameAction(_ sender: NSMenuItem)
    func copyReviewLinkAction(_ sender: NSMenuItem)
    func copyReviewPromptAction(_ sender: NSMenuItem)
    func copyReviewContextPathAction(_ sender: NSMenuItem)
    func copyMarkdownAction(_ sender: NSMenuItem)
    func copyHTMLAction(_ sender: NSMenuItem)
    func copyRichTextAction(_ sender: NSMenuItem)
    func copyPlainTextAction(_ sender: NSMenuItem)
}
