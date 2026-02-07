import Foundation

enum TerminationResult: Equatable, Sendable {
    case terminated
    case alreadyExited
    case failed(String)
}

protocol ProcessTerminating: Sendable {
    func terminate(process: BlockingProcess, gracePeriod: TimeInterval) async -> TerminationResult
    func terminateAll(processes: [BlockingProcess], gracePeriod: TimeInterval) async -> [Int32: TerminationResult]
}
