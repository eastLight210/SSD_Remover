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

    private(set) var isRescanning = false
    private(set) var rescanError: String?

    let volume: ExternalVolume
    private let processScanner: ProcessScanning
    private let terminateAndEjectService: TerminateAndEjectService

    init(
        volume: ExternalVolume,
        processGroups: [ProcessGroup],
        processScanner: ProcessScanning,
        processTerminator: ProcessTerminating,
        diskEjector: DiskEjecting
    ) {
        self.volume = volume
        self.processGroups = processGroups
        self.processScanner = processScanner
        self.terminateAndEjectService = TerminateAndEjectService(
            processTerminator: processTerminator,
            diskEjector: diskEjector
        )
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
        failedTerminations = [:]
        phase = targets.isEmpty
            ? .ejecting
            : .terminatingProcesses(completed: 0, total: targets.count)

        let outcome = await terminateAndEjectService.execute(
            volume: volume,
            processes: targets,
            gracePeriod: gracePeriod,
            onProgress: { [self] completed, total in
                phase = .terminatingProcesses(completed: completed, total: total)
            },
            onBeforeEject: { [self] in
                phase = .ejecting
            }
        )

        failedTerminations = outcome.terminationResults.reduce(into: [:]) { partialResult, entry in
            if case .failed(let message) = entry.value {
                partialResult[entry.key] = message
            }
        }

        switch outcome.ejectResult {
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

    /// confirming 상태에서 프로세스 목록 재스캔
    func rescanProcesses() async {
        guard phase == .confirming else { return }
        isRescanning = true
        rescanError = nil
        do {
            processGroups = try await processScanner.scanProcesses(for: volume)
        } catch {
            rescanError = error.localizedDescription
        }
        isRescanning = false
    }
}
