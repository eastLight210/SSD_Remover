import Testing
@testable import SSD_Remover

@Suite("AppLaunchMode Tests")
struct AppLaunchModeTests {
    @Test("터미널에서 인자 없이 실행하면 CLI help 모드")
    func emptyArgumentsRemainCLI() {
        let mode = AppLaunchMode.detect(arguments: [])

        #expect(mode == .cli(arguments: []))
    }

    @Test("시스템 인자만 있윸면 메뉴바 모드")
    func systemArgumentsOnlyRemainMenuBar() {
        let mode = AppLaunchMode.detect(arguments: [
            "-psn_0_12345",
            "-NSDocumentRevisionsDebugMode", "YES",
            "-ApplePersistenceIgnoreState", "YES",
        ])

        #expect(mode == .menuBar)
    }

    @Test("시스템 인자 뒤의 값은 건너뛰고 실제 CLI 인자만 유지")
    func systemArgumentValuesDoNotLeakIntoCLIArguments() {
        let mode = AppLaunchMode.detect(arguments: [
            "-psn_0_12345",
            "-NSDocumentRevisionsDebugMode", "YES",
            "-ApplePersistenceIgnoreState", "YES",
            "scan",
            "TestDrive",
        ])

        #expect(mode == .cli(arguments: ["scan", "TestDrive"]))
    }

    @Test("실제 CLI 플래그는 은지")
    func actualCLIFlagsRemain() {
        let mode = AppLaunchMode.detect(arguments: [
            "-ApplePersistenceIgnoreState", "YES",
            "terminate",
            "TestDrive",
            "--grace-period",
            "0",
        ])

        #expect(mode == .cli(arguments: ["terminate", "TestDrive", "--grace-period", "0"]))
    }
}
