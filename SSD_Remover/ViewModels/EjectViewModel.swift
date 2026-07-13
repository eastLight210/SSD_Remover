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
    private(set) var selectedProcessIDs: Set<Int32> = []
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
        self.processGroups = processGroups.map { group in
            ProcessGroup(category: group.category, processes: group.processes, isSelected: false)
        }
        self.processScanner = processScanner
        self.terminateAndEjectService = TerminateAndEjectService(
            processTerminator: processTerminator,
            diskEjector: diskEjector
        )
    }

    var selectedProcesses: [BlockingProcess] {
        processGroups
            .flatMap { $0.processes }
            .filter { selectedProcessIDs.contains($0.pid) }
    }

    var allProcesses: [BlockingProcess] {
        processGroups.flatMap { $0.processes }
    }

    var selectedProcessCount: Int {
        selectedProcessIDs.count
    }

    var totalProcessCount: Int {
        allProcesses.count
    }

    var hasSpotlightProcesses: Bool {
        processGroups.contains { $0.category == .spotlight }
    }

    func toggleGroupSelection(category: ProcessCategory) {
        guard let index = processGroups.firstIndex(where: { $0.category == category }) else { return }
        let processIDs = Set(processGroups[index].processes.map(\.pid))
        let shouldSelect = !processIDs.isSubset(of: selectedProcessIDs)

        if shouldSelect {
            selectedProcessIDs.formUnion(processIDs)
        } else {
            selectedProcessIDs.subtract(processIDs)
        }
        processGroups[index].isSelected = shouldSelect
    }

    func isProcessSelected(_ process: BlockingProcess) -> Bool {
        selectedProcessIDs.contains(process.pid)
    }

    func toggleProcessSelection(_ process: BlockingProcess) {
        if selectedProcessIDs.contains(process.pid) {
            selectedProcessIDs.remove(process.pid)
        } else {
            selectedProcessIDs.insert(process.pid)
        }
        synchronizeGroupSelection(for: process.pid)
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
            let groups = try await processScanner.scanProcesses(for: volume)
            processGroups = groups.map { group in
                ProcessGroup(category: group.category, processes: group.processes, isSelected: false)
            }
            selectedProcessIDs.removeAll()
        } catch {
            rescanError = error.localizedDescription
        }
        isRescanning = false
    }

    private func synchronizeGroupSelection(for pid: Int32) {
        guard let index = processGroups.firstIndex(where: { group in
            group.processes.contains { $0.pid == pid }
        }) else { return }

        let groupProcessIDs = Set(processGroups[index].processes.map(\.pid))
        processGroups[index].isSelected = !groupProcessIDs.isEmpty
            && groupProcessIDs.isSubset(of: selectedProcessIDs)
    }
}
