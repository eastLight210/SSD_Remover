import Foundation

enum EjectResult: Equatable, Sendable {
    case success
    case failed(String)
}

protocol DiskEjecting: Sendable {
    func eject(volume: ExternalVolume) async -> EjectResult
}
