import Testing
import Foundation
@testable import SSD_Remover

@Suite("CLICommandParser Tests")
struct CLICommandParserTests {
    private let parser = CLICommandParser()

    @Test("인자가 없으면 help 명령으로 해석")
    func emptyArgumentsReturnsHelp() throws {
        let command = try parser.parse(arguments: [])

        #expect(command == .help)
    }

    @Test("scan 명령은 볼륨 쿼리를 파싱")
    func parsesScanCommand() throws {
        let command = try parser.parse(arguments: ["scan", "TestDrive"])

        #expect(command == .scan(volumeQuery: "TestDrive"))
    }

    @Test("terminate-and-eject 명령은 선택 필터와 grace period를 파싱")
    func parsesTerminateAndEjectCommand() throws {
        let command = try parser.parse(arguments: [
            "terminate-and-eject",
            "TestDrive",
            "--group", "user",
            "--group", "spotlight",
            "--pid", "200",
            "--grace-period", "1.5",
        ])

        #expect(command == .terminateAndEject(
            volumeQuery: "TestDrive",
            selection: CLIProcessSelection(
                categories: [.spotlight, .user],
                pids: [200]
            ),
            gracePeriod: 1.5
        ))
    }

    @Test("알 수 없는 그룹 값은 파싱 에러")
    func invalidGroupThrows() {
        #expect(throws: CLIParseError.invalidGroup("unknown")) {
            try parser.parse(arguments: ["terminate", "TestDrive", "--group", "unknown"])
        }
    }

    @Test("지원하지 않는 명령은 파싱 에러")
    func unknownCommandThrows() {
        #expect(throws: CLIParseError.unknownCommand("destroy")) {
            try parser.parse(arguments: ["destroy", "TestDrive"])
        }
    }
}
