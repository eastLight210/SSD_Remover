import Foundation

actor ProcessScannerService: ProcessScanning {
    private let shell: ShellExecuting

    init(shell: ShellExecuting) {
        self.shell = shell
    }

    func scanProcesses(for volume: ExternalVolume) async throws -> [ProcessGroup] {
        let output: String
        do {
            output = try await shell.execute(
                command: Constants.lsofPath,
                arguments: ["-F", "pcuLn", "+f", "--", volume.mountPoint.path]
            )
        } catch let error as ShellError {
            if case .executionFailed(exitCode: 1, stderr: _) = error {
                return []
            }
            throw error
        }
        let processes = LsofOutputParser.parse(output)
        return ProcessClassifier.classify(processes)
    }
}
