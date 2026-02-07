import Foundation
@testable import SSD_Remover

final class MockProcessTerminator: ProcessTerminating, @unchecked Sendable {
    var stubbedResult: TerminationResult = .terminated
    var stubbedResults: [Int32: TerminationResult] = [:]
    private(set) var terminatedProcesses: [BlockingProcess] = []

    func terminate(process: BlockingProcess, gracePeriod: TimeInterval) async -> TerminationResult {
        terminatedProcesses.append(process)
        return stubbedResults[process.pid] ?? stubbedResult
    }

    func terminateAll(processes: [BlockingProcess], gracePeriod: TimeInterval) async -> [Int32: TerminationResult] {
        var results: [Int32: TerminationResult] = [:]
        for p in processes {
            terminatedProcesses.append(p)
            results[p.pid] = stubbedResults[p.pid] ?? stubbedResult
        }
        return results
    }
}
