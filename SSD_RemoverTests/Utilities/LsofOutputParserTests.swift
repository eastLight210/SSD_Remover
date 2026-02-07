import Testing
@testable import SSD_Remover

@Suite("LsofOutputParser Tests")
struct LsofOutputParserTests {

    @Test("빈 출력은 빈 배열을 반환한다")
    func emptyOutput() {
        let result = LsofOutputParser.parse("")
        #expect(result.isEmpty)
    }

    @Test("단일 프로세스를 파싱한다")
    func singleProcess() {
        let output = """
        p1234
        cmds
        u0
        Lroot
        n/Volumes/SSD/file.txt
        """
        let result = LsofOutputParser.parse(output)
        #expect(result.count == 1)
        #expect(result[0].pid == 1234)
        #expect(result[0].command == "mds")
        #expect(result[0].uid == 0)
        #expect(result[0].user == "root")
        #expect(result[0].lockedFiles == ["/Volumes/SSD/file.txt"])
    }

    @Test("복수 프로세스를 파싱한다")
    func multipleProcesses() {
        let output = """
        p100
        cmds
        u0
        Lroot
        n/Volumes/SSD/a.txt
        p200
        cvim
        u501
        Luser
        n/Volumes/SSD/b.txt
        """
        let result = LsofOutputParser.parse(output)
        #expect(result.count == 2)
        #expect(result[0].pid == 100)
        #expect(result[0].command == "mds")
        #expect(result[1].pid == 200)
        #expect(result[1].command == "vim")
        #expect(result[1].user == "user")
    }

    @Test("복수 파일을 가진 프로세스를 파싱한다")
    func multipleFiles() {
        let output = """
        p300
        cvim
        u501
        Luser
        n/Volumes/SSD/a.txt
        n/Volumes/SSD/b.txt
        n/Volumes/SSD/c.txt
        """
        let result = LsofOutputParser.parse(output)
        #expect(result.count == 1)
        #expect(result[0].lockedFiles.count == 3)
        #expect(result[0].lockedFiles[0] == "/Volumes/SSD/a.txt")
        #expect(result[0].lockedFiles[1] == "/Volumes/SSD/b.txt")
        #expect(result[0].lockedFiles[2] == "/Volumes/SSD/c.txt")
    }

    @Test("f 필드(file descriptor)를 무시한다")
    func ignoresFileDescriptorField() {
        let output = """
        p400
        cmds_stores
        u0
        Lroot
        f5
        n/Volumes/SSD/data.db
        f6
        n/Volumes/SSD/index.db
        """
        let result = LsofOutputParser.parse(output)
        #expect(result.count == 1)
        #expect(result[0].lockedFiles.count == 2)
        #expect(result[0].command == "mds_stores")
    }

    @Test("실제 lsof -F pcuLn 형식의 출력을 파싱한다")
    func realLsofFormat() {
        let output = "p1234\ncmds_stores\nu0\nLroot\nf4\nn/Volumes/MySSD/.Spotlight-V100/store.db\nf7\nn/Volumes/MySSD/.Spotlight-V100/index\np5678\ncfinder\nu501\nLkimdonghyeok\nf12\nn/Volumes/MySSD/Documents/report.pdf"

        let result = LsofOutputParser.parse(output)
        #expect(result.count == 2)
        #expect(result[0].pid == 1234)
        #expect(result[0].command == "mds_stores")
        #expect(result[0].isRoot == true)
        #expect(result[0].lockedFiles.count == 2)
        #expect(result[1].pid == 5678)
        #expect(result[1].command == "finder")
        #expect(result[1].uid == 501)
    }

    @Test("알 수 없는 필드 prefix를 무시한다")
    func ignoresUnknownFields() {
        let output = """
        p500
        ctest
        u100
        Ltest_user
        tREG
        n/Volumes/SSD/test.txt
        """
        let result = LsofOutputParser.parse(output)
        #expect(result.count == 1)
        #expect(result[0].lockedFiles == ["/Volumes/SSD/test.txt"])
    }

    // MARK: - Edge Case Tests

    @Test("pid 필드 없는 레코드는 무시")
    func noPidFieldIgnored() {
        let output = "cvim\nu501\nLuser\nn/Volumes/SSD/file.txt"
        let result = LsofOutputParser.parse(output)
        #expect(result.isEmpty)
    }

    @Test("잘못된 pid 형식은 해당 레코드를 skip")
    func invalidPidFormat() {
        let output = "pabc\ncvim\nu501\nLuser\nn/Volumes/SSD/file.txt"
        let result = LsofOutputParser.parse(output)
        // pabc → Int32("abc") == nil → currentPID = nil → 결과에 추가 안됨
        #expect(result.isEmpty)
    }

    @Test("잘못된 pid 뒤에 유효한 레코드가 오면 필드 초기화됨")
    func invalidPidFollowedByValidRecord() {
        let output = "pabc\ncbadcmd\nu999\nLbaduser\nn/bad/file\np100\ncvim\nu501\nLuser\nn/Volumes/SSD/file.txt"
        let result = LsofOutputParser.parse(output)
        // pabc 레코드는 skip, p100에서 새 레코드 시작 시 필드 초기화
        #expect(result.count == 1)
        #expect(result[0].pid == 100)
        #expect(result[0].command == "vim")
        #expect(result[0].uid == 501)
        #expect(result[0].user == "user")
        #expect(result[0].lockedFiles == ["/Volumes/SSD/file.txt"])
    }

    @Test("파일 필드 없는 프로세스 (lockedFiles 빈 배열)")
    func processWithNoFiles() {
        let output = "p100\ncvim\nu501\nLuser"
        let result = LsofOutputParser.parse(output)
        #expect(result.count == 1)
        #expect(result[0].pid == 100)
        #expect(result[0].lockedFiles.isEmpty)
    }

    @Test("불완전한 마지막 레코드도 포함")
    func incompleteLastRecord() {
        let output = "p100\ncvim\nu501\nLuser\nn/Volumes/SSD/file.txt\np200"
        let result = LsofOutputParser.parse(output)
        #expect(result.count == 2)
        #expect(result[0].pid == 100)
        #expect(result[0].lockedFiles == ["/Volumes/SSD/file.txt"])
        #expect(result[1].pid == 200)
        #expect(result[1].command == "")
        #expect(result[1].lockedFiles.isEmpty)
    }
}
