import Foundation

struct ReviewCLIActionResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool {
        exitCode == 0
    }

    var displayMessage: String {
        let trimmedError = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedError.isEmpty {
            return trimmedError
        }
        let trimmedOutput = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedOutput.isEmpty ? "clearly review exited with code \(exitCode)" : trimmedOutput
    }
}

enum ReviewCLIActionRunner {
    static func runReviewAction(
        _ action: String,
        fileURL: URL,
        vaultRoot: URL,
        bundleIdentifier: String?,
        leadingArguments: [String] = [],
        extraOptions: [String] = []
    ) async -> ReviewCLIActionResult {
        let args = [
            "review",
            action,
        ] + leadingArguments + [
            fileURL.path,
            "--vault",
            vaultRoot.path,
            "--bundle-id",
            bundleIdentifier ?? "com.sabotage.clearly",
        ] + extraOptions
        return await run(arguments: args)
    }

    private static func run(arguments: [String]) async -> ReviewCLIActionResult {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            if let bundled = CLIInstaller.bundledBinaryURL() {
                process.executableURL = bundled
                process.arguments = arguments
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["clearly"] + arguments
            }
            process.environment = ProcessInfo.processInfo.environment

            let fileManager = FileManager.default
            let outputDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("clearly-review-cli-\(UUID().uuidString)", isDirectory: true)
            let stdoutURL = outputDirectory.appendingPathComponent("stdout.txt")
            let stderrURL = outputDirectory.appendingPathComponent("stderr.txt")
            var stdoutHandle: FileHandle?
            var stderrHandle: FileHandle?
            defer {
                stdoutHandle?.closeFile()
                stderrHandle?.closeFile()
                try? fileManager.removeItem(at: outputDirectory)
            }

            do {
                try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                try Data().write(to: stdoutURL)
                try Data().write(to: stderrURL)
                stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
                stderrHandle = try FileHandle(forWritingTo: stderrURL)
                process.standardOutput = stdoutHandle
                process.standardError = stderrHandle

                try process.run()
                process.waitUntilExit()
                stdoutHandle?.closeFile()
                stderrHandle?.closeFile()
                stdoutHandle = nil
                stderrHandle = nil

                let stdout = String(data: (try? Data(contentsOf: stdoutURL)) ?? Data(), encoding: .utf8) ?? ""
                let stderr = String(data: (try? Data(contentsOf: stderrURL)) ?? Data(), encoding: .utf8) ?? ""
                return ReviewCLIActionResult(
                    exitCode: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                )
            } catch {
                return ReviewCLIActionResult(
                    exitCode: 1,
                    stdout: "",
                    stderr: error.localizedDescription
                )
            }
        }.value
    }
}
