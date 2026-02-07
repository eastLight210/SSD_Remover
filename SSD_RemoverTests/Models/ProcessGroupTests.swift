import Testing
@testable import SSD_Remover

@Suite("ProcessGroup Tests")
struct ProcessGroupTests {

    @Test("id는 category와 동일하다")
    func identifiable() {
        let group = ProcessGroup(category: .spotlight, processes: [])
        #expect(group.id == .spotlight)
    }

    @Test("기본 isSelected는 true")
    func defaultIsSelected() {
        let group = ProcessGroup(category: .user, processes: [])
        #expect(group.isSelected == true)
    }

    @Test("isSelected를 false로 생성할 수 있다")
    func isSelectedFalse() {
        let group = ProcessGroup(category: .system, processes: [], isSelected: false)
        #expect(group.isSelected == false)
    }

    @Test("Equatable 준수")
    func equatable() {
        let process = BlockingProcess(pid: 1, command: "mds", user: "root", uid: 0, lockedFiles: [])
        let a = ProcessGroup(category: .spotlight, processes: [process])
        let b = ProcessGroup(category: .spotlight, processes: [process])
        #expect(a == b)
    }

    @Test("processes를 포함한다")
    func containsProcesses() {
        let p1 = BlockingProcess(pid: 1, command: "mds", user: "root", uid: 0, lockedFiles: [])
        let p2 = BlockingProcess(pid: 2, command: "mds_stores", user: "root", uid: 0, lockedFiles: [])
        let group = ProcessGroup(category: .spotlight, processes: [p1, p2])
        #expect(group.processes.count == 2)
    }
}

@Suite("ProcessCategory Tests")
struct ProcessCategoryTests {

    @Test("CaseIterable - 3개 케이스가 있다")
    func caseIterable() {
        #expect(ProcessCategory.allCases.count == 3)
        #expect(ProcessCategory.allCases.contains(.spotlight))
        #expect(ProcessCategory.allCases.contains(.system))
        #expect(ProcessCategory.allCases.contains(.user))
    }
}
