import Foundation

struct BlockingProcess: Identifiable, Equatable, Hashable, Sendable {
    let pid: Int32
    let command: String
    let user: String
    let uid: Int32
    let lockedFiles: [String]

    var id: Int32 { pid }

    var isRoot: Bool { uid == 0 }
}
