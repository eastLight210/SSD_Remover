import Foundation

struct TerminateAndEjectOutcome: Sendable {
    let terminationResults: [Int32: TerminationResult]
    let ejectResult: EjectResult
}

struct TerminateAndEjectService: Sendable {
    typealias ProgressHandler = @MainActor @Sendable (_ completed: Int, _ total: Int) async -> Void
    typealias PhaseHandler = @MainActor @Sendable () async -> Void

    private let processTerminator: ProcessTerminating
    private let diskEjector: DiskEjecting

    init(
        processTerminator: ProcessTerminating,
        diskEjector: DiskEjecting
    ) {
        self.processTerminator = processTerminator
        self.diskEjector = diskEjector
    }

    func execute(
        volume: ExternalVolume,
        processes: [BlockingProcess],
        gracePeriod: TimeInterval,
        onProgress: ProgressHandler? = nil,
        onBeforeEject: PhaseHandler? = nil
    ) async -> TerminateAndEjectOutcome {
        var results: [Int32: TerminationResult] = [:]
        let total = processes.count

        if total > 0 {
            await onProgress?(0, total)
        }

        var completed = 0
        for process in processes {
            results[process.pid] = await processTerminator.terminate(
                process: process,
                gracePeriod: gracePeriod
            )
            completed += 1
            await onProgress?(completed, total)
        }

        await onBeforeEject?()
        let ejectResult = await diskEjector.eject(volume: volume)

        return TerminateAndEjectOutcome(
            terminationResults: results,
            ejectResult: ejectResult
        )
    }
}
