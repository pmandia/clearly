import Foundation
import ClearlyCore
import MCP

enum ToolRegistry {
    static let writeToolNames: Set<String> = [
        "create_note",
        "update_note",
        "move_note",
        "create_review",
        "stage_review_comment_resolution",
        "confirm_review_comment_resolution",
        "close_review_comment",
        "delete_review_comment",
        "publish_review_version"
    ]

    static func listTools(vaults: [LoadedVault], readOnly: Bool = false) -> [Tool] {
        let vaultPaths = vaults.map { $0.url.path }
        let vaultDescription = vaultPaths.joined(separator: ", ")

        let readAnnotations = Tool.Annotations(
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )

        let writeAnnotations = Tool.Annotations(
            readOnlyHint: false,
            destructiveHint: true,
            idempotentHint: false,
            openWorldHint: false
        )

        let reviewFileProperties: [String: Value] = [
            "file_path": .object([
                "type": .string("string"),
                "description": .string("Absolute path, vault-relative path, or vault://<vaultId>/<relativePath>. Omit to use Clearly's current document if fresh.")
            ]),
            "vault": .object([
                "type": .string("string"),
                "description": .string("Optional vault name/path disambiguator for relative file_path.")
            ])
        ]

        let reviewContextOutput: Value = .object([
            "type": .string("object"),
            "properties": .object([
                "review": .object(["type": .string("object")]),
                "schema_version": .object(["type": .string("integer")]),
                "generated_at": .object(["type": .string("string")]),
                "vault_id": .object(["type": .string("string")]),
                "file_id": .object(["type": .string("string")]),
                "target_relative_path": .object(["type": .string("string")]),
                "target_absolute_path": .object(["type": .string("string")]),
                "vault_uri": .object(["type": .string("string")]),
                "has_linked_review": .object(["type": .string("boolean")])
            ])
        ])

        let tools = [
            Tool(
                name: "get_current_document",
                description: "Return the active document from the running Clearly app. Requires Clearly's current-document heartbeat to be fresh; otherwise pass file_path to review tools explicitly.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([:])
                ]),
                annotations: readAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app_instance_id": .object(["type": .string("string")]),
                        "updated_at": .object(["type": .string("string")]),
                        "vault_id": .object(["type": .string("string")]),
                        "vault_root": .object(["type": .string("string")]),
                        "file_id": .object(["type": .string("string")]),
                        "target_relative_path": .object(["type": .string("string")]),
                        "target_absolute_path": .object(["type": .string("string")]),
                        "document_title": .object(["type": .string("string")])
                    ])
                ])
            ),
            Tool(
                name: "get_review_for_file",
                description: "Resolve local Clearly ReviewState for a document. Accepts absolute path, vault-relative path, or vault:// URI. Does not hit the hosted review service.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object(reviewFileProperties)
                ]),
                annotations: readAnnotations,
                outputSchema: reviewContextOutput
            ),
            Tool(
                name: "sync_review_comments",
                description: "Fetch latest comments for a linked hosted review, page through the API, and update the local comments cache. Requires CLEARLY_REVIEW_API_BASE_URL plus a publisher token from Keychain or CLEARLY_REVIEW_PUBLISHER_TOKEN.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object(reviewFileProperties)
                ]),
                annotations: readAnnotations,
                outputSchema: .object(["type": .string("object")])
            ),
            Tool(
                name: "create_review",
                description: "Create a hosted Clearly review for the current local Markdown file, publish the initial sanitized snapshot, store the returned publisher token in Keychain, and link the local ReviewState record. Requires CLEARLY_REVIEW_API_BASE_URL and CLEARLY_REVIEW_PUBLISHER_TOKEN for the initial create.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object(reviewFileProperties)
                ]),
                annotations: writeAnnotations,
                outputSchema: .object(["type": .string("object")])
            ),
            Tool(
                name: "get_review_comments",
                description: "Get review comments for a document. Defaults to freshness='latest' (sync first); pass freshness='cache' to read the local comments cache only.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object(reviewFileProperties.merging([
                        "status": .object(["type": .string("string"), "description": .string("Optional status filter such as open, closed, or resolved.")]),
                        "freshness": .object(["type": .string("string"), "enum": .array([.string("latest"), .string("cache")]), "description": .string("Default latest. Use cache to avoid network.")
                        ])
                    ]) { _, new in new })
                ]),
                annotations: readAnnotations,
                outputSchema: .object(["type": .string("object")])
            ),
            Tool(
                name: "stage_review_comment_resolution",
                description: "Stage a local pending resolution for a review comment after editing. This is local-only and does not mark the remote comment resolved.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object(reviewFileProperties.merging([
                        "comment_id": .object(["type": .string("string")]),
                        "note": .object(["type": .string("string")]),
                        "remote_revision": .object(["type": .string("integer")])
                    ]) { _, new in new }),
                    "required": .array([.string("comment_id")])
                ]),
                annotations: writeAnnotations,
                outputSchema: .object(["type": .string("object")])
            ),
            Tool(
                name: "confirm_review_comment_resolution",
                description: "Confirm a staged resolution after the user reviews/accepts edits. Requires confirm=true and expected_revision unless a staged resolution already has remote_revision.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object(reviewFileProperties.merging([
                        "comment_id": .object(["type": .string("string")]),
                        "note": .object(["type": .string("string")]),
                        "expected_revision": .object(["type": .string("integer")]),
                        "confirm": .object(["type": .string("boolean")])
                    ]) { _, new in new }),
                    "required": .array([.string("comment_id"), .string("confirm")])
                ]),
                annotations: writeAnnotations,
                outputSchema: .object(["type": .string("object")])
            ),
            Tool(
                name: "close_review_comment",
                description: "Close a review comment as intentionally not addressed. Closed comments are excluded from open-comment context.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object(reviewFileProperties.merging([
                        "comment_id": .object(["type": .string("string")]),
                        "note": .object(["type": .string("string")]),
                        "expected_revision": .object(["type": .string("integer")])
                    ]) { _, new in new }),
                    "required": .array([.string("comment_id")])
                ]),
                annotations: writeAnnotations,
                outputSchema: .object(["type": .string("object")])
            ),
            Tool(
                name: "delete_review_comment",
                description: "Soft-delete a review comment from normal review reads. Use only when the user explicitly asks to remove a comment.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object(reviewFileProperties.merging([
                        "comment_id": .object(["type": .string("string")]),
                        "expected_revision": .object(["type": .string("integer")])
                    ]) { _, new in new }),
                    "required": .array([.string("comment_id")])
                ]),
                annotations: writeAnnotations,
                outputSchema: .object(["type": .string("object")])
            ),
            Tool(
                name: "publish_review_version",
                description: "Render the current on-disk Markdown into a sanitized, source-mapped snapshot and publish it as a new hosted review version. Requires a configured review service and publisher token.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object(reviewFileProperties)
                ]),
                annotations: writeAnnotations,
                outputSchema: .object(["type": .string("object")])
            ),
            Tool(
                name: "get_review_forks",
                description: "List reviewer Markdown forks for a linked hosted review from the configured review service.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object(reviewFileProperties)
                ]),
                annotations: readAnnotations,
                outputSchema: .object(["type": .string("object")])
            ),
            Tool(
                name: "get_review_fork",
                description: "Fetch one reviewer Markdown fork, including its diff metadata and full Markdown source, for local review/import.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object(reviewFileProperties.merging([
                        "fork_id": .object(["type": .string("string")])
                    ]) { _, new in new }),
                    "required": .array([.string("fork_id")])
                ]),
                annotations: readAnnotations,
                outputSchema: .object(["type": .string("object")])
            ),
            Tool(
                name: "semantic_search",
                description: "Conceptual search across notes via on-device embeddings (Apple's NLContextualEmbedding). Use when the user's question doesn't share keywords with the relevant notes — e.g. asking about 'productivity' when the note actually says 'flow state' or 'concentrated work'. Searches \(vaults.count) vault(s): \(vaultDescription). For exact phrases, proper nouns, or filename-style targets, prefer search_notes (FTS5) instead.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Natural-language query. Free-form; no special syntax. Be descriptive — semantic ranking benefits from full sentences over single keywords.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "minimum": .int(1),
                            "description": .string("Max results to return. Default 10, capped at 50.")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault name or path substring. When set, only matching vaults are searched.")
                        ])
                    ]),
                    "required": .array([.string("query")])
                ]),
                annotations: readAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query":          .object(["type": .string("string")]),
                        "total_count":    .object(["type": .string("integer"), "description": .string("Number of notes scored across the selected vaults.")]),
                        "returned_count": .object(["type": .string("integer"), "description": .string("Number of hits in the results array after applying limit.")]),
                        "results":        .object(["type": .string("array"), "items": .object(["type": .string("object")]), "description": .string("Ranked top-N. Each item has 'vault', 'vault_path', 'relative_path', 'filename', 'score' (cosine similarity, -1…1, higher is closer), 'snippet'.")])
                    ]),
                    "required": .array([.string("query"), .string("total_count"), .string("returned_count"), .string("results")])
                ])
            ),
            Tool(
                name: "find_related",
                description: "Find notes semantically related to a given note. Reuses on-device embeddings to score every other note's chunks against the source's mean vector, returns the top matches with cosine similarity. Use when you have one note and want \"more like this\" — e.g. surface adjacent thinking, related projects, or earlier passes at the same idea. English-only via Apple's NLContextualEmbedding.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "relative_path": .object([
                            "type": .string("string"),
                            "description": .string("Vault-relative path of the source note, e.g. 'Notes/local-first.md'.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "minimum": .int(1),
                            "description": .string("Max results to return. Default 10, capped at 50.")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault name or path substring. When set, only matching vaults are searched. The source note must still resolve unambiguously among loaded vaults.")
                        ])
                    ]),
                    "required": .array([.string("relative_path")])
                ]),
                annotations: readAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "vault":           .object(["type": .string("string"), "description": .string("Vault that owns the source note.")]),
                        "source":          .object(["type": .string("string"), "description": .string("Vault-relative path of the source note.")]),
                        "total_count":     .object(["type": .string("integer"), "description": .string("Number of distinct files scored across the selected vaults.")]),
                        "returned_count":  .object(["type": .string("integer"), "description": .string("Number of hits in the results array after applying limit.")]),
                        "results":         .object(["type": .string("array"), "items": .object(["type": .string("object")]), "description": .string("Ranked top-N. Each item has 'vault', 'vault_path', 'relative_path', 'filename', 'score' (cosine similarity, -1…1, higher is closer).")])
                    ]),
                    "required": .array([.string("vault"), .string("source"), .string("total_count"), .string("returned_count"), .string("results")])
                ])
            ),
            Tool(
                name: "search_notes",
                description: "Full-text search across all notes in Clearly. Searches \(vaults.count) vault(s): \(vaultDescription). Returns relevance-ranked results with context snippets. Uses BM25 ranking and stemming. Supports `tag:foo` (AND-combined, case-insensitive) and `path:notes/sub` operators inside the query string to narrow by tag or vault-relative path prefix. Results include the vault path and relative file path — use standard file access to read full content.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Search query. Supports quoted phrases for exact match. Operators: `tag:work` filters to files carrying that tag (repeat for AND); `path:journal/2026/` filters by vault-relative path prefix. Filter-only queries (e.g. `tag:idea`) are valid and return every matching file.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "minimum": .int(1),
                            "description": .string("Max results to return. Default 20, capped at 100.")
                        ])
                    ]),
                    "required": .array([.string("query")])
                ]),
                annotations: readAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query":          .object(["type": .string("string")]),
                        "total_count":    .object(["type": .string("integer"), "description": .string("Unclamped total match count across all vaults.")]),
                        "returned_count": .object(["type": .string("integer"), "description": .string("Number of hits included in the results array after applying limit.")]),
                        "results":        .object(["type": .string("array"), "items": .object(["type": .string("object")])])
                    ]),
                    "required": .array([.string("query"), .string("total_count"), .string("returned_count"), .string("results")])
                ])
            ),
            Tool(
                name: "get_backlinks",
                description: "Get all notes that link to a given note via [[wiki-links]], plus unlinked text mentions (places the note is referenced by name but not yet linked). Searches across all loaded vaults by default; pass 'vault' to scope.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "relative_path": .object([
                            "type": .string("string"),
                            "description": .string("Vault-relative path (e.g. 'folder/My Note.md') or bare filename (e.g. 'My Note') of the target note.")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault name or path. When set, only this vault is searched.")
                        ])
                    ]),
                    "required": .array([.string("relative_path")])
                ]),
                annotations: readAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "vault":         .object(["type": .string("string")]),
                        "relative_path": .object(["type": .string("string"), "description": .string("Resolved vault-relative path of the target note.")]),
                        "linked":        .object(["type": .string("array"), "items": .object(["type": .string("object")]), "description": .string("Wiki-link references from other notes.")]),
                        "unlinked":      .object(["type": .string("array"), "items": .object(["type": .string("object")]), "description": .string("Text mentions of the note's filename not wrapped in [[...]].")])
                    ]),
                    "required": .array([.string("vault"), .string("relative_path"), .string("linked"), .string("unlinked")])
                ])
            ),
            Tool(
                name: "get_tags",
                description: "Without arguments: list all tags across all vaults with file counts (mode='all'). With a tag argument: list all files with that tag (mode='by_tag'). Tags come from both inline #hashtags and YAML frontmatter.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "tag": .object([
                            "type": .string("string"),
                            "description": .string("Optional specific tag (without '#' prefix) to look up. Omit to list all tags.")
                        ])
                    ])
                ]),
                annotations: readAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "mode":     .object(["type": .string("string"), "enum": .array([.string("all"), .string("by_tag")])]),
                        "tag":      .object(["type": .string("string"), "description": .string("Echoes the input tag when mode='by_tag'; absent (not emitted) otherwise.")]),
                        "all_tags": .object(["type": .string("array"), "items": .object(["type": .string("object")]), "description": .string("Populated only when mode='all'. Each entry has 'tag' and 'count'.")]),
                        "files":    .object(["type": .string("array"), "items": .object(["type": .string("object")]), "description": .string("Populated only when mode='by_tag'. Each entry has 'vault', 'vault_path', 'relative_path'.")])
                    ]),
                    "required": .array([.string("mode")])
                ])
            ),
            Tool(
                name: "read_note",
                description: "Read the full content of a note in a vault, optionally restricted to a line range. Returns content plus metadata (content hash, size, modification time, parsed frontmatter, headings, tags).",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "relative_path": .object([
                            "type": .string("string"),
                            "description": .string("Vault-relative path, e.g. 'Daily/2026-04-16.md'. Must not start with '/' or contain '..'.")
                        ]),
                        "start_line": .object([
                            "type": .string("integer"),
                            "minimum": .int(1),
                            "description": .string("Optional. 1-based line number to start reading from. Omit to read from the beginning.")
                        ]),
                        "end_line": .object([
                            "type": .string("integer"),
                            "minimum": .int(1),
                            "description": .string("Optional. 1-based line number to stop at (inclusive). Omit to read to end of file.")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault name disambiguator. Required only when multiple vaults are loaded and 'relative_path' is ambiguous.")
                        ])
                    ]),
                    "required": .array([.string("relative_path")])
                ]),
                annotations: readAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "vault":          .object(["type": .string("string")]),
                        "relative_path":  .object(["type": .string("string")]),
                        "content":        .object(["type": .string("string")]),
                        "content_hash":   .object(["type": .string("string")]),
                        "size_bytes":     .object(["type": .string("integer")]),
                        "modified_at":    .object(["type": .string("string"), "format": .string("date-time")]),
                        "frontmatter":    .object(["type": .string("object"), "additionalProperties": .object(["type": .string("string")])]),
                        "headings":       .object(["type": .string("array"), "items": .object(["type": .string("object")])]),
                        "tags":           .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                        "line_range":     .object(["type": .string("object"), "description": .string("Present when start_line / end_line were specified.")])
                    ]),
                    "required": .array([.string("vault"), .string("relative_path"), .string("content"), .string("content_hash")])
                ])
            ),
            Tool(
                name: "list_notes",
                description: "List notes in loaded vault(s). Uses a fresh filesystem walk (always current) rather than the index. Optionally restricted to a subpath prefix.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "under": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault-relative directory prefix, e.g. 'Daily/'. Only notes whose path starts with this prefix are returned.")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault name. When omitted, notes across all loaded vaults are returned.")
                        ])
                    ])
                ]),
                annotations: readAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "notes": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("object")])
                        ])
                    ]),
                    "required": .array([.string("notes")])
                ])
            ),
            Tool(
                name: "get_headings",
                description: "Return the heading outline (H1–H6) of a note, including heading text, level, and 1-based line number. Sourced from the index.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "relative_path": .object([
                            "type": .string("string"),
                            "description": .string("Vault-relative path, e.g. 'Strategy/pricing.md'.")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault name disambiguator.")
                        ])
                    ]),
                    "required": .array([.string("relative_path")])
                ]),
                annotations: readAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "vault":         .object(["type": .string("string")]),
                        "relative_path": .object(["type": .string("string")]),
                        "headings":      .object(["type": .string("array"), "items": .object(["type": .string("object")])])
                    ]),
                    "required": .array([.string("vault"), .string("relative_path"), .string("headings")])
                ])
            ),
            Tool(
                name: "get_frontmatter",
                description: "Return the parsed YAML frontmatter of a note as a flat key-value map. Returns an empty map when the note has no frontmatter block.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "relative_path": .object([
                            "type": .string("string"),
                            "description": .string("Vault-relative path, e.g. 'Projects/2026-plan.md'.")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault name disambiguator.")
                        ])
                    ]),
                    "required": .array([.string("relative_path")])
                ]),
                annotations: readAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "vault":           .object(["type": .string("string")]),
                        "relative_path":   .object(["type": .string("string")]),
                        "frontmatter":     .object(["type": .string("object"), "additionalProperties": .object(["type": .string("string")])]),
                        "has_frontmatter": .object(["type": .string("boolean")])
                    ]),
                    "required": .array([.string("vault"), .string("relative_path"), .string("frontmatter"), .string("has_frontmatter")])
                ])
            ),
            Tool(
                name: "create_note",
                description: "Create a new markdown note at the specified vault-relative path. Parent directories are created automatically. Fails with a conflict error if the note already exists — use update_note to modify existing notes.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "relative_path": .object([
                            "type": .string("string"),
                            "description": .string("Vault-relative path for the new note, e.g. 'Daily/2026-04-17.md'. Must not start with '/' or contain '..'. Parent folders are created automatically.")
                        ]),
                        "content": .object([
                            "type": .string("string"),
                            "description": .string("Full markdown content, including optional YAML frontmatter delimited by '---'.")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional. Name of the vault to write to. Required only when multiple vaults are loaded.")
                        ])
                    ]),
                    "required": .array([.string("relative_path"), .string("content")])
                ]),
                annotations: writeAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "vault":         .object(["type": .string("string")]),
                        "relative_path": .object(["type": .string("string")]),
                        "content_hash":  .object(["type": .string("string")]),
                        "size_bytes":    .object(["type": .string("integer")]),
                        "created_at":    .object(["type": .string("string"), "format": .string("date-time")])
                    ]),
                    "required": .array([.string("vault"), .string("relative_path"), .string("content_hash"), .string("size_bytes"), .string("created_at")])
                ])
            ),
            Tool(
                name: "move_note",
                description: "Rename or move a note within a vault, rewriting every inbound [[wiki-link]] in other notes to point at the new path. Preserves heading anchors and aliases on rewritten links. Index `id` is preserved across the move, so backlink relationships survive without re-resolution. Fails with note_exists if the destination already exists.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "from_path": .object([
                            "type": .string("string"),
                            "description": .string("Vault-relative path of the source note, e.g. 'Inbox/draft.md'.")
                        ]),
                        "to_path": .object([
                            "type": .string("string"),
                            "description": .string("Vault-relative destination path, e.g. 'Notes/published.md'. Parent folders are created automatically.")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault name; required only when 'from_path' is ambiguous across multiple loaded vaults.")
                        ])
                    ]),
                    "required": .array([.string("from_path"), .string("to_path")])
                ]),
                annotations: writeAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "vault":           .object(["type": .string("string")]),
                        "from":            .object(["type": .string("string")]),
                        "to":              .object(["type": .string("string")]),
                        "links_rewritten": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("object")]),
                            "description": .string("Per-file count of [[wiki-link]] rewrites. Each entry has 'relative_path' and 'count'.")
                        ])
                    ]),
                    "required": .array([.string("vault"), .string("from"), .string("to"), .string("links_rewritten")])
                ])
            ),
            Tool(
                name: "update_note",
                description: "Update an existing note. Mode 'replace' overwrites the entire file. Mode 'append' adds content to the end (with a leading newline if the file does not end in one). Mode 'prepend' inserts content after YAML frontmatter if present, or at the beginning of the file. Pass `expected_content_hash` (the value `read_note` returned) to opt into optimistic concurrency: the call is rejected with `stale_content` if the file changed since you last read it.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "relative_path": .object([
                            "type": .string("string"),
                            "description": .string("Vault-relative path of an existing note.")
                        ]),
                        "content": .object([
                            "type": .string("string"),
                            "description": .string("Markdown content to write.")
                        ]),
                        "mode": .object([
                            "type": .string("string"),
                            "enum": .array([.string("replace"), .string("append"), .string("prepend")]),
                            "description": .string("Write mode. 'replace' overwrites the full note. 'append' adds content to the end. 'prepend' adds content to the start (after any YAML frontmatter block, if present).")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault name; required only when 'relative_path' is ambiguous across multiple loaded vaults.")
                        ]),
                        "expected_content_hash": .object([
                            "type": .string("string"),
                            "description": .string("Optional. SHA-256 hex digest of the on-disk content the agent last observed (typically from `read_note`). If provided and the on-disk hash differs at write time, the call is rejected with error `stale_content` so the agent can re-read and retry without clobbering a concurrent edit.")
                        ])
                    ]),
                    "required": .array([.string("relative_path"), .string("content"), .string("mode")])
                ]),
                annotations: writeAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "vault":         .object(["type": .string("string")]),
                        "relative_path": .object(["type": .string("string")]),
                        "mode":          .object(["type": .string("string")]),
                        "content_hash":  .object(["type": .string("string")]),
                        "size_bytes":    .object(["type": .string("integer")]),
                        "modified_at":   .object(["type": .string("string"), "format": .string("date-time")])
                    ]),
                    "required": .array([.string("vault"), .string("relative_path"), .string("mode"), .string("content_hash"), .string("size_bytes"), .string("modified_at")])
                ])
            )
        ]
        return readOnly ? tools.filter { !writeToolNames.contains($0.name) } : tools
    }
}
