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

    @Test("모든 subcommand는 command-scoped help를 지원")
    func parsesCommandScopedHelp() throws {
        let expectations: [(String, CLIHelpTopic)] = [
            ("list", .list),
            ("scan", .scan),
            ("terminate", .terminate),
            ("eject", .eject),
            ("terminate-and-eject", .terminateAndEject),
            ("version", .version),
        ]

        for (commandName, topic) in expectations {
            #expect(try parser.parse(arguments: [commandName, "--help"]) == .help(topic: topic))
        }
    }

    @Test("list와 help 별칭은 후행 인자를 거부")
    func rejectsTrailingArgumentsForListAndHelpAliases() {
        for command in ["list", "ls", "help", "-h", "--help"] {
            #expect(throws: CLIParseError.unexpectedArguments(
                command: command,
                arguments: ["typo"]
            )) {
                try parser.parse(arguments: [command, "typo"])
            }
        }
    }

    @Test("version 명령과 별칭을 파싱")
    func parsesVersionAliases() throws {
        #expect(try parser.parse(arguments: ["version"]) == .version)
        #expect(try parser.parse(arguments: ["--version"]) == .version)
        #expect(try parser.parse(arguments: ["-v"]) == .version)
    }

    @Test("JSON 옵션은 운영 명령의 앞뒤에서 파싱")
    func parsesJSONOutputOption() throws {
        #expect(try parser.parse(arguments: ["list", "--json"]) == .listVolumes(outputFormat: .json))
        #expect(try parser.parse(arguments: ["scan", "--json", "TestDrive"]) == .scan(
            volumeQuery: "TestDrive",
            outputFormat: .json
        ))
        #expect(try parser.parse(arguments: ["eject", "TestDrive", "--json"]) == .eject(
            volumeQuery: "TestDrive",
            outputFormat: .json
        ))
    }

    @Test("scan/eject 명령은 추가 피연산자를 거부")
    func rejectsExtraVolumeQueryOperands() {
        #expect(throws: CLIParseError.unexpectedArguments(command: "scan", arguments: ["SSD"])) {
            try parser.parse(arguments: ["scan", "Backup", "SSD"])
        }

        #expect(throws: CLIParseError.unexpectedArguments(command: "eject", arguments: ["--force"])) {
            try parser.parse(arguments: ["eject", "MyDrive", "--force"])
        }
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

    @Test("종료 명령은 all과 dry-run 의도를 보존")
    func parsesTerminationSafetyOptions() throws {
        let all = try parser.parse(arguments: [
            "terminate", "TestDrive", "--all", "--grace-period", "0", "--json",
        ])
        #expect(all == .terminate(
            volumeQuery: "TestDrive",
            selection: .unfiltered,
            gracePeriod: 0,
            explicitlyIncludesAll: true,
            outputFormat: .json
        ))

        let dryRun = try parser.parse(arguments: [
            "terminate-and-eject", "TestDrive", "--dry-run",
        ])
        #expect(dryRun == .terminateAndEject(
            volumeQuery: "TestDrive",
            selection: .unfiltered,
            gracePeriod: 3,
            dryRun: true
        ))
    }

    @Test("all은 group 또는 pid 필터와 함께 사용할 수 없음")
    func rejectsAllWithFilters() {
        #expect(throws: CLIParseError.conflictingOptions("--all", "--group/--pid")) {
            try parser.parse(arguments: [
                "terminate", "TestDrive", "--all", "--group", "user",
            ])
        }
    }

    @Test("단일 옵션의 중복을 거부")
    func rejectsDuplicateSingletonOptions() {
        #expect(throws: CLIParseError.duplicateOption("--json")) {
            try parser.parse(arguments: ["list", "--json", "--json"])
        }
        #expect(throws: CLIParseError.duplicateOption("--all")) {
            try parser.parse(arguments: ["terminate", "TestDrive", "--all", "--all"])
        }
        #expect(throws: CLIParseError.duplicateOption("--dry-run")) {
            try parser.parse(arguments: ["terminate", "TestDrive", "--dry-run", "--dry-run"])
        }
        #expect(throws: CLIParseError.duplicateOption("--grace-period")) {
            try parser.parse(arguments: [
                "terminate", "TestDrive",
                "--grace-period", "1",
                "--grace-period", "2",
            ])
        }
    }

    @Test("알 수 없는 그룹 값은 파싱 에러")
    func invalidGroupThrows() {
        #expect(throws: CLIParseError.invalidGroup("unknown")) {
            try parser.parse(arguments: ["terminate", "TestDrive", "--group", "unknown"])
        }
    }

    @Test("0 이하 PID 값은 파싱 에러")
    func nonPositivePIDThrows() {
        #expect(throws: CLIParseError.invalidPID("0")) {
            try parser.parse(arguments: ["terminate", "TestDrive", "--pid", "0"])
        }

        #expect(throws: CLIParseError.invalidPID("-1")) {
            try parser.parse(arguments: ["terminate", "TestDrive", "--pid", "-1"])
        }
    }

    @Test("음수 grace period 값은 파싱 에러")
    func negativeGracePeriodThrows() {
        #expect(throws: CLIParseError.invalidGracePeriod("-0.5")) {
            try parser.parse(arguments: ["terminate", "TestDrive", "--grace-period", "-0.5"])
        }
    }

    @Test("유한하지 않은 grace period 값은 파싱 에러")
    func nonFiniteGracePeriodThrows() {
        #expect(throws: CLIParseError.invalidGracePeriod("nan")) {
            try parser.parse(arguments: ["terminate", "TestDrive", "--grace-period", "nan"])
        }

        #expect(throws: CLIParseError.invalidGracePeriod("inf")) {
            try parser.parse(arguments: ["terminate", "TestDrive", "--grace-period", "inf"])
        }
    }

    @Test("지원하지 않는 명령은 파싱 에러")
    func unknownCommandThrows() {
        #expect(throws: CLIParseError.unknownCommand("destroy")) {
            try parser.parse(arguments: ["destroy", "TestDrive"])
        }
    }
}
