import Darwin
import Foundation
import os

protocol CLICommandExecuting: Sendable {
    func run(arguments: [String]) async -> CLIExecutionResult
}

struct LiveCLICommandExecutor: CLICommandExecuting {
    func run(arguments: [String]) async -> CLIExecutionResult {
        let parser = CLICommandParser()

        do {
            let command = try parser.parse(arguments: arguments)
            let shell = ShellExecutor()
            let runner = CLIRunner(
                volumeMonitor: VolumeMonitorService(shellExecutor: shell),
                processScanner: ProcessScannerService(shell: shell),
                processTerminator: ProcessTerminatorService(
                    shell: shell,
                    privilegedShell: PrivilegedExecutor(),
                    context: .headlessCLI(effectiveUserID: geteuid())
                ),
                diskEjector: DiskEjectService(shell: shell)
            )
            return await runner.run(command)
        } catch let error as CLIParseError {
            if arguments.contains("--json") {
                return .failure(
                    CLIJSONOutput.error(
                        command: Self.commandName(in: arguments),
                        code: "usage_error",
                        message: error.localizedDescription,
                        usage: CLICommandParser.usageText
                    ),
                    exitCode: 64
                )
            }
            return .failure(
                "\(error.localizedDescription)\n\n\(CLICommandParser.usageText)",
                exitCode: 64
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func commandName(in arguments: [String]) -> String {
        guard let command = arguments.first else {
            return "help"
        }

        switch command {
        case "ls":
            return "list"
        case "--version", "-v":
            return "version"
        case "--help", "-h":
            return "help"
        default:
            return command
        }
    }
}

struct CLIExecutionResultEmitter {
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle

    init(
        stdoutHandle: FileHandle = .standardOutput,
        stderrHandle: FileHandle = .standardError
    ) {
        self.stdoutHandle = stdoutHandle
        self.stderrHandle = stderrHandle
    }

    func emit(_ result: CLIExecutionResult) {
        write(result.stdout, to: stdoutHandle)
        write(result.stderr, to: stderrHandle)
    }

    private func write(_ output: String, to handle: FileHandle) {
        guard !output.isEmpty else {
            return
        }

        let line = output.hasSuffix("\n") ? output : output + "\n"
        try? handle.write(contentsOf: Data(line.utf8))
    }
}

private final class BlockingCLIExecutionBox: Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let state = OSAllocatedUnfairLock(initialState: CLIExecutionResult?.none)

    func store(_ result: CLIExecutionResult) {
        state.withLock { $0 = result }
        semaphore.signal()
    }

    func waitForResult() -> CLIExecutionResult {
        semaphore.wait()
        return state.withLock { $0 } ?? .failure("CLI execution failed before producing a result.")
    }
}

struct BlockingCLICommandExecutor<Executor: CLICommandExecuting>: Sendable {
    private let executor: Executor

    init(executor: Executor) {
        self.executor = executor
    }

    func run(arguments: [String]) -> CLIExecutionResult {
        let box = BlockingCLIExecutionBox()

        Task.detached(priority: .userInitiated) {
            let result = await executor.run(arguments: arguments)
            box.store(result)
        }

        return box.waitForResult()
    }
}

struct CLIExecutionResultFinalizer {
    private let emitter: CLIExecutionResultEmitter
    private let exitHandler: @Sendable (Int32) -> Never

    init(
        emitter: CLIExecutionResultEmitter = CLIExecutionResultEmitter(),
        exitHandler: @escaping @Sendable (Int32) -> Never = { Darwin.exit($0) }
    ) {
        self.emitter = emitter
        self.exitHandler = exitHandler
    }

    func finalize(_ result: CLIExecutionResult) -> Never {
        emitter.emit(result)
        exitHandler(Int32(result.exitCode))
    }
}

@MainActor
struct SSDRemoverAppBootstrap {
    let launchMode: AppLaunchMode
    let viewModel: AppViewModel?

    init(
        arguments: [String],
        makeViewModel: @escaping @MainActor () -> AppViewModel = {
            AppViewModel(volumeMonitorService: VolumeMonitorService())
        }
    ) {
        let launchMode = AppLaunchMode.detect(arguments: arguments)
        self.launchMode = launchMode

        switch launchMode {
        case .menuBar:
            self.viewModel = makeViewModel()
        case .cli:
            self.viewModel = nil
        }
    }
}

enum AppProcessEnvironment {
    static let launchArguments = Array(CommandLine.arguments.dropFirst())
}
