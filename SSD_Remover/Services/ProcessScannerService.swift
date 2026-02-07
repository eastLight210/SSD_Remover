import Foundation

actor ProcessScannerService: ProcessScanning {
    private let shell: ShellExecuting

    init(shell: ShellExecuting) {
        self.shell = shell
    }

    func scanProcesses(for volume: ExternalVolume) async throws -> [ProcessGroup] {
        let output = try await shell.execute(
            command: Constants.lsofPath,
            arguments: ["-F", "pcuLn", "+D", volume.mountPoint.path]
        )
        let processes = LsofOutputParser.parse(output)
        return ProcessClassifier.classify(processes)
    }
}
