import Foundation

enum EjectPhase: Equatable, Sendable {
    case confirming
    case terminatingProcesses(completed: Int, total: Int)
    case ejecting
    case success
    case failure(String)
}

@MainActor
@Observable
final class EjectViewModel {
    private(set) var phase: EjectPhase = .confirming
    private(set) var processGroups: [ProcessGroup] = []
    private(set) var failedTerminations: [Int32: String] = [:]

    let volume: ExternalVolume
    private let processTerminator: ProcessTerminating
    private let diskEjector: DiskEjecting

    init(
        volume: ExternalVolume,
        processGroups: [ProcessGroup],
        processTerminator: ProcessTerminating,
        diskEjector: DiskEjecting
    ) {
        self.volume = volume
        self.processGroups = processGroups
        self.processTerminator = processTerminator
        self.diskEjector = diskEjector
    }

    var selectedProcesses: [BlockingProcess] {
        processGroups
            .filter { $0.isSelected }
            .flatMap { $0.processes }
    }

    var hasSpotlightProcesses: Bool {
        processGroups.contains { $0.category == .spotlight }
    }

    func toggleGroupSelection(category: ProcessCategory) {
        guard let index = processGroups.firstIndex(where: { $0.category == category }) else { return }
        processGroups[index].isSelected.toggle()
    }

    func terminateAndEject(gracePeriod: TimeInterval = 3.0) async {
        let targets = selectedProcesses
        let total = targets.count
        failedTerminations = [:]

        if total > 0 {
            phase = .terminatingProcesses(completed: 0, total: total)

            var completed = 0
            for process in targets {
                let result = await processTerminator.terminate(process: process, gracePeriod: gracePeriod)
                if case .failed(let message) = result {
                    failedTerminations[process.pid] = message
                }
                completed += 1
                phase = .terminatingProcesses(completed: completed, total: total)
            }
        }

        phase = .ejecting

        let result = await diskEjector.eject(volume: volume)
        switch result {
        case .success:
            phase = .success
        case .failed(let message):
            phase = .failure(message)
        }
    }

    /// failure 상태에서 전체 흐름을 재실행
    func retry(gracePeriod: TimeInterval = 3.0) async {
        await terminateAndEject(gracePeriod: gracePeriod)
    }
}
