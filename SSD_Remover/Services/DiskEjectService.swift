import Foundation

actor DiskEjectService: DiskEjecting {
    private let shell: ShellExecuting

    init(shell: ShellExecuting) {
        self.shell = shell
    }

    func eject(volume: ExternalVolume) async -> EjectResult {
        do {
            _ = try await shell.execute(
                command: Constants.diskutilPath,
                arguments: ["eject", volume.parentWholeDisk]
            )
            return .success
        } catch let error as ShellError {
            switch error {
            case .executionFailed(_, let stderr):
                return .failed(stderr)
            case .launchFailed(let message):
                return .failed(message)
            case .timedOut, .cancelled:
                return .failed(error.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
