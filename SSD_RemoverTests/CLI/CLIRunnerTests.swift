import Testing
import Foundation
@testable import SSD_Remover

@Suite("CLIRunner Tests")
struct CLIRunnerTests {
    private func makeVolume(
        name: String = "TestDrive",
        deviceIdentifier: String = "disk4s1",
        mountPath: String = "/Volumes/TestDrive"
    ) -> ExternalVolume {
        let url = URL(fileURLWithPath: mountPath)
        return ExternalVolume(
            id: url,
            name: name,
            deviceIdentifier: deviceIdentifier,
            fileSystem: "APFS",
            totalCapacity: 1_000_000_000_000,
            availableCapacity: 500_000_000_000,
            mountPoint: url
        )
    }

    private func makeProcess(
        pid: Int32,
        command: String,
        user: String = "kim",
        uid: Int32 = 501,
        lockedFiles: [String] = ["/Volumes/TestDrive/file.txt"]
    ) -> BlockingProcess {
        BlockingProcess(
            pid: pid,
            command: command,
            user: user,
            uid: uid,
            lockedFiles: lockedFiles
        )
    }

    private func makeRunner(
        volumeMonitor: MockVolumeMonitor,
        scanner: MockProcessScanner = MockProcessScanner(),
        terminator: MockProcessTerminator = MockProcessTerminator(),
        ejector: MockDiskEjector = MockDiskEjector()
    ) -> CLIRunner {
        CLIRunner(
            volumeMonitor: volumeMonitor,
            processScanner: scanner,
            processTerminator: terminator,
            diskEjector: ejector
        )
    }

    @Test("list 명령은 외장 볼륨 목록을 출력")
    func listVolumes() async {
        let volumeMonitor = MockVolumeMonitor()
        await volumeMonitor.setVolumes([
            makeVolume(name: "Backup SSD", deviceIdentifier: "disk5s1", mountPath: "/Volumes/Backup SSD"),
            makeVolume()
        ])

        let result = await makeRunner(volumeMonitor: volumeMonitor).run(.listVolumes)

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("Backup SSD"))
        #expect(result.stdout.contains("/Volumes/TestDrive"))
        #expect(await volumeMonitor.refreshCallCount == 1)
    }

    @Test("scan 명령은 Spotlight 경고와 프로세스 목록을 출력")
    func scanProcesses() async {
        let volumeMonitor = MockVolumeMonitor()
        await volumeMonitor.setVolumes([makeVolume()])

        let scanner = MockProcessScanner()
        scanner.stubbedResult = [
            ProcessGroup(
                category: .spotlight,
                processes: [makeProcess(pid: 369, command: "mds", user: "root", uid: 0)]
            ),
            ProcessGroup(
                category: .user,
                processes: [makeProcess(pid: 100, command: "vim")]
            ),
        ]

        let result = await makeRunner(volumeMonitor: volumeMonitor, scanner: scanner).run(.scan(volumeQuery: "TestDrive"))

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("Spotlight warning"))
        #expect(result.stdout.contains("mds"))
        #expect(result.stdout.contains("vim"))
    }

    @Test("terminate 명령은 그룹과 PID 필터를 함께 적용")
    func terminateProcessesWithFilters() async {
        let volumeMonitor = MockVolumeMonitor()
        await volumeMonitor.setVolumes([makeVolume()])

        let scanner = MockProcessScanner()
        scanner.stubbedResult = [
            ProcessGroup(
                category: .user,
                processes: [
                    makeProcess(pid: 100, command: "vim"),
                    makeProcess(pid: 200, command: "code"),
                ]
            ),
            ProcessGroup(
                category: .system,
                processes: [makeProcess(pid: 300, command: "launchd", user: "root", uid: 0)]
            ),
        ]

        let terminator = MockProcessTerminator()
        let result = await makeRunner(
            volumeMonitor: volumeMonitor,
            scanner: scanner,
            terminator: terminator
        ).run(.terminate(
            volumeQuery: "disk4s1",
            selection: CLIProcessSelection(categories: [.user], pids: [200]),
            gracePeriod: 0
        ))

        #expect(result.exitCode == 0)
        #expect(terminator.terminatedProcesses.map(\.pid) == [200])
        #expect(result.stdout.contains("PID 200"))
        #expect(!result.stdout.contains("PID 100"))
    }

    @Test("terminate-and-eject 명령은 차단 프로세스가 없어도 제거를 시도")
    func terminateAndEjectWithoutProcesses() async {
        let volumeMonitor = MockVolumeMonitor()
        await volumeMonitor.setVolumes([makeVolume()])

        let scanner = MockProcessScanner()
        scanner.stubbedResult = []

        let terminator = MockProcessTerminator()
        let ejector = MockDiskEjector()

        let result = await makeRunner(
            volumeMonitor: volumeMonitor,
            scanner: scanner,
            terminator: terminator,
            ejector: ejector
        ).run(.terminateAndEject(
            volumeQuery: "TestDrive",
            selection: .all,
            gracePeriod: 0
        ))

        #expect(result.exitCode == 0)
        #expect(terminator.terminatedProcesses.isEmpty)
        #expect(ejector.ejectCalled)
        #expect(result.stdout.contains("No blocking processes found"))
    }

    @Test("terminate-and-eject 명령은 선택 필터가 비어 있으면 실패")
    func terminateAndEjectWithUnmatchedSelectionFails() async {
        let volumeMonitor = MockVolumeMonitor()
        await volumeMonitor.setVolumes([makeVolume()])

        let scanner = MockProcessScanner()
        scanner.stubbedResult = [
            ProcessGroup(
                category: .user,
                processes: [makeProcess(pid: 100, command: "vim")]
            )
        ]

        let ejector = MockDiskEjector()
        let result = await makeRunner(
            volumeMonitor: volumeMonitor,
            scanner: scanner,
            ejector: ejector
        ).run(.terminateAndEject(
            volumeQuery: "TestDrive",
            selection: CLIProcessSelection(categories: [.spotlight]),
            gracePeriod: 0
        ))

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("No matching processes"))
        #expect(ejector.ejectCalled == false)
    }

    @Test("eject 명령은 디스크 제거 서비스를 호출")
    func ejectVolume() async {
        let volumeMonitor = MockVolumeMonitor()
        let volume = makeVolume()
        await volumeMonitor.setVolumes([volume])

        let ejector = MockDiskEjector()
        let result = await makeRunner(volumeMonitor: volumeMonitor, ejector: ejector).run(.eject(volumeQuery: "/Volumes/TestDrive"))

        #expect(result.exitCode == 0)
        #expect(ejector.ejectCalled)
        #expect(ejector.ejectedVolume == volume)
    }
}
