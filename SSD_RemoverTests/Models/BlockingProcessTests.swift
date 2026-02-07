import Testing
@testable import SSD_Remover

@Suite("BlockingProcess Tests")
struct BlockingProcessTests {

    @Test("id는 pid와 동일하다")
    func identifiable() {
        let process = BlockingProcess(pid: 1234, command: "mds", user: "root", uid: 0, lockedFiles: [])
        #expect(process.id == 1234)
    }

    @Test("uid가 0이면 isRoot는 true")
    func isRootWhenUidIsZero() {
        let process = BlockingProcess(pid: 100, command: "mds", user: "root", uid: 0, lockedFiles: [])
        #expect(process.isRoot == true)
    }

    @Test("uid가 0이 아니면 isRoot는 false")
    func isNotRootWhenUidIsNonZero() {
        let process = BlockingProcess(pid: 200, command: "vim", user: "user", uid: 501, lockedFiles: [])
        #expect(process.isRoot == false)
    }

    @Test("Equatable 준수")
    func equatable() {
        let a = BlockingProcess(pid: 1, command: "a", user: "u", uid: 0, lockedFiles: ["/f"])
        let b = BlockingProcess(pid: 1, command: "a", user: "u", uid: 0, lockedFiles: ["/f"])
        #expect(a == b)
    }

    @Test("Hashable 준수")
    func hashable() {
        let a = BlockingProcess(pid: 1, command: "a", user: "u", uid: 0, lockedFiles: ["/f"])
        let b = BlockingProcess(pid: 1, command: "a", user: "u", uid: 0, lockedFiles: ["/f"])
        #expect(a.hashValue == b.hashValue)
    }

    @Test("lockedFiles에 여러 파일을 가질 수 있다")
    func multipleLockedFiles() {
        let files = ["/Volumes/SSD/a.txt", "/Volumes/SSD/b.txt"]
        let process = BlockingProcess(pid: 300, command: "vim", user: "user", uid: 501, lockedFiles: files)
        #expect(process.lockedFiles.count == 2)
        #expect(process.lockedFiles == files)
    }
}
