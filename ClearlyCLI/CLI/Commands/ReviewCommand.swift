import ArgumentParser
import ClearlyCore
import Foundation

struct ReviewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review",
        abstract: "Inspect and sync Clearly review state for local Markdown files.",
        discussion: """
        Wraps the same review workflow used by MCP so Clearly and scripts can
        fetch comments, inspect local review context, and publish new versions
        without speaking MCP JSON-RPC directly.

        Review service calls require CLEARLY_REVIEW_API_BASE_URL plus either
        CLEARLY_REVIEW_PUBLISHER_TOKEN or a linked Keychain account in the
        local review manifest.
        """,
        subcommands: [
            ReviewCurrentCommand.self,
            ReviewContextCommand.self,
            ReviewCreateCommand.self,
            ReviewCommentsCommand.self,
            ReviewSyncCommand.self,
            ReviewStageCommand.self,
            ReviewConfirmCommand.self,
            ReviewCloseCommand.self,
            ReviewDeleteCommand.self,
            ReviewPublishCommand.self,
            ReviewForksCommand.self,
            ReviewForkCommand.self,
        ]
    )
}

struct ReviewStageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stage",
        abstract: "Stage a local pending resolution for a review comment."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Review comment id to stage.")
    var commentId: String

    @Argument(help: "Absolute path, vault-relative path, or vault:// URI. Omit to use the current Clearly document.")
    var filePath: String?

    @Option(help: "Resolution note.")
    var note: String?

    @Option(help: "Last-known remote revision for conflict-safe confirmation.")
    var remoteRevision: Int?

    @Option(name: .customLong("in-vault"), help: "Optional vault disambiguator for relative file paths.")
    var inVault: String?

    func run() async throws {
        try await runReviewCommand(globals: globals) { vaults in
            try await stageReviewCommentResolution(
                StageReviewResolutionArgs(
                    filePath: filePath,
                    commentId: commentId,
                    note: note,
                    remoteRevision: remoteRevision,
                    vault: inVault
                ),
                vaults: vaults
            )
        }
    }
}

struct ReviewConfirmCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "confirm",
        abstract: "Confirm a staged review comment resolution remotely."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Review comment id to confirm resolved.")
    var commentId: String

    @Argument(help: "Absolute path, vault-relative path, or vault:// URI. Omit to use the current Clearly document.")
    var filePath: String?

    @Option(help: "Resolution note.")
    var note: String?

    @Option(help: "Expected remote revision. Required unless the staged resolution has one.")
    var expectedRevision: Int?

    @Flag(help: "Required safety confirmation.")
    var confirm: Bool = false

    @Option(name: .customLong("in-vault"), help: "Optional vault disambiguator for relative file paths.")
    var inVault: String?

    func run() async throws {
        try await runReviewCommand(globals: globals) { vaults in
            try await confirmReviewCommentResolution(
                ConfirmReviewResolutionArgs(
                    filePath: filePath,
                    commentId: commentId,
                    note: note,
                    expectedRevision: expectedRevision,
                    confirm: confirm,
                    vault: inVault
                ),
                vaults: vaults
            )
        }
    }
}

struct ReviewCloseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "close",
        abstract: "Close a review comment without marking it addressed."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Review comment id to close.")
    var commentId: String

    @Argument(help: "Absolute path, vault-relative path, or vault:// URI. Omit to use the current Clearly document.")
    var filePath: String?

    @Option(help: "Close note.")
    var note: String?

    @Option(help: "Expected remote revision. If omitted, Clearly syncs and uses the latest revision.")
    var expectedRevision: Int?

    @Option(name: .customLong("in-vault"), help: "Optional vault disambiguator for relative file paths.")
    var inVault: String?

    func run() async throws {
        try await runReviewCommand(globals: globals) { vaults in
            try await closeReviewComment(
                MutateReviewCommentArgs(
                    filePath: filePath,
                    commentId: commentId,
                    note: note,
                    expectedRevision: expectedRevision,
                    vault: inVault
                ),
                vaults: vaults
            )
        }
    }
}

struct ReviewDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Soft-delete a review comment."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Review comment id to delete.")
    var commentId: String

    @Argument(help: "Absolute path, vault-relative path, or vault:// URI. Omit to use the current Clearly document.")
    var filePath: String?

    @Option(help: "Expected remote revision. If omitted, Clearly syncs and uses the latest revision.")
    var expectedRevision: Int?

    @Option(name: .customLong("in-vault"), help: "Optional vault disambiguator for relative file paths.")
    var inVault: String?

    func run() async throws {
        try await runReviewCommand(globals: globals) { vaults in
            try await deleteReviewComment(
                MutateReviewCommentArgs(
                    filePath: filePath,
                    commentId: commentId,
                    note: nil,
                    expectedRevision: expectedRevision,
                    vault: inVault
                ),
                vaults: vaults
            )
        }
    }
}

struct ReviewCurrentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "current",
        abstract: "Return the document currently focused in Clearly."
    )

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        try await runReviewCommand(globals: globals) { vaults in
            try await getCurrentDocument(vaults: vaults)
        }
    }
}

struct ReviewContextCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "context",
        abstract: "Return local review context for a file."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Absolute path, vault-relative path, or vault:// URI. Omit to use the current Clearly document.")
    var filePath: String?

    @Option(name: .customLong("in-vault"), help: "Optional vault disambiguator for relative file paths.")
    var inVault: String?

    func run() async throws {
        try await runReviewCommand(globals: globals) { vaults in
            try await getReviewForFile(
                ReviewFileArgs(filePath: filePath, vault: inVault),
                vaults: vaults
            )
        }
    }
}

struct ReviewCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create and link a hosted review for a local Markdown file."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Absolute path, vault-relative path, or vault:// URI. Omit to use the current Clearly document.")
    var filePath: String?

    @Option(name: .customLong("in-vault"), help: "Optional vault disambiguator for relative file paths.")
    var inVault: String?

    func run() async throws {
        try await runReviewCommand(globals: globals) { vaults in
            try await createReview(
                ReviewFileArgs(filePath: filePath, vault: inVault),
                vaults: vaults
            )
        }
    }
}

struct ReviewCommentsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "comments",
        abstract: "Return review comments for a file."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Absolute path, vault-relative path, or vault:// URI. Omit to use the current Clearly document.")
    var filePath: String?

    @Option(help: "Filter by status, e.g. open, closed, or resolved.")
    var status: String?

    @Option(help: "latest syncs first; cache reads comments-cache.json only.")
    var freshness: String?

    @Option(name: .customLong("in-vault"), help: "Optional vault disambiguator for relative file paths.")
    var inVault: String?

    func run() async throws {
        try await runReviewCommand(globals: globals) { vaults in
            try await getReviewComments(
                ReviewCommentsArgs(
                    filePath: filePath,
                    status: status,
                    freshness: freshness,
                    vault: inVault
                ),
                vaults: vaults
            )
        }
    }
}

struct ReviewSyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Fetch latest remote review comments and update local cache."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Absolute path, vault-relative path, or vault:// URI. Omit to use the current Clearly document.")
    var filePath: String?

    @Option(name: .customLong("in-vault"), help: "Optional vault disambiguator for relative file paths.")
    var inVault: String?

    func run() async throws {
        try await runReviewCommand(globals: globals) { vaults in
            try await syncReviewComments(
                ReviewFileArgs(filePath: filePath, vault: inVault),
                vaults: vaults
            )
        }
    }
}

struct ReviewPublishCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Publish the current Markdown file as a new review version."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Absolute path, vault-relative path, or vault:// URI. Omit to use the current Clearly document.")
    var filePath: String?

    @Option(name: .customLong("in-vault"), help: "Optional vault disambiguator for relative file paths.")
    var inVault: String?

    func run() async throws {
        try await runReviewCommand(globals: globals) { vaults in
            try await publishReviewVersion(
                ReviewFileArgs(filePath: filePath, vault: inVault),
                vaults: vaults
            )
        }
    }
}

struct ReviewForksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "forks",
        abstract: "Return reviewer fork summaries for a file."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Absolute path, vault-relative path, or vault:// URI. Omit to use the current Clearly document.")
    var filePath: String?

    @Option(name: .customLong("in-vault"), help: "Optional vault disambiguator for relative file paths.")
    var inVault: String?

    func run() async throws {
        try await runReviewCommand(globals: globals) { vaults in
            try await getReviewForks(
                ReviewFileArgs(filePath: filePath, vault: inVault),
                vaults: vaults
            )
        }
    }
}

struct ReviewForkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fork",
        abstract: "Return one reviewer fork with Markdown source and diff metadata."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Fork id returned by review forks.")
    var forkId: String

    @Argument(help: "Absolute path, vault-relative path, or vault:// URI. Omit to use the current Clearly document.")
    var filePath: String?

    @Option(name: .customLong("in-vault"), help: "Optional vault disambiguator for relative file paths.")
    var inVault: String?

    func run() async throws {
        try await runReviewCommand(globals: globals) { vaults in
            try await getReviewFork(
                ReviewForkArgs(filePath: filePath, forkId: forkId, vault: inVault),
                vaults: vaults
            )
        }
    }
}

private func runReviewCommand<T: Encodable>(
    globals: GlobalOptions,
    body: ([LoadedVault]) async throws -> T
) async throws {
    let vaults: [LoadedVault]
    do {
        vaults = try IndexSet.openIndexes(globals)
    } catch {
        Emitter.emitError(
            "no_vaults",
            message: "Unable to open any vault index: \(error.localizedDescription)",
            extra: ["bundle_id": globals.bundleID]
        )
        throw ExitCode(Exit.general)
    }

    do {
        let result = try await body(vaults)
        try Emitter.emit(result, format: globals.format)
    } catch let error as ToolError {
        let code = Emitter.emitToolError(error)
        throw ExitCode(code)
    }
}
