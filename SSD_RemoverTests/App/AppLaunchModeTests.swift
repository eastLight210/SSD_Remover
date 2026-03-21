import Testing
@testable import SSD_Remover

@Suite("AppLaunchMode Tests")
struct AppLaunchModeTests {
    @Test("시스템 인자만 있으면 메뉴바 모드")
    func systemArgumentsOnlyRemainMenuBar() {
        let mode = AppLaunchMode.detect(arguments: [
            "-psn_0_12345",
            "-NSDocumentRevisionsDebugMode", "YES",
            "-ApplePersistenceIgnoreState", "YES",
        ])

        #expect(mode == .menuBar)
    }

    @Test("실스템 인자 뒤의 값은 건너뛰고 실제 CLI 인자만 유지")
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

    @Test("실제 CLI 플래그는 유지")
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
