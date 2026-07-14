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
        ejector: MockDiskEjector = MockDiskEjector(),
        version: CLIAppVersion? = CLIAppVersion(marketingVersion: "9.8.7", buildNumber: "654")
    ) -> CLIRunner {
        CLIRunner(
            volumeMonitor: volumeMonitor,
            processScanner: scanner,
            processTerminator: terminator,
            diskEjector: ejector,
            versionProvider: { version }
        )
    }

    private func jsonObject(_ output: String) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: Data(output.utf8))
        return try #require(value as? [String: Any])
    }

    private func jsonData(_ output: String) throws -> [String: Any] {
        let object = try jsonObject(output)
        return try #require(object["data"] as? [String: Any])
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

    @Test("동일한 이름의 볼륨이 여러 개면 정확한 이름 조회도 모호성 에러")
    func duplicateExactNameRequiresDisambiguation() async {
        let volumeMonitor = MockVolumeMonitor()
        await volumeMonitor.setVolumes([
            makeVolume(deviceIdentifier: "disk4s1", mountPath: "/Volumes/TestDrive"),
            makeVolume(deviceIdentifier: "disk5s1", mountPath: "/Volumes/TestDrive Clone"),
        ])

        let result = await makeRunner(volumeMonitor: volumeMonitor).run(.scan(volumeQuery: "TestDrive"))

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("Volume query is ambiguous"))
        #expect(result.stderr.contains("disk4s1"))
        #expect(result.stderr.contains("disk5s1"))
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
            selection: .unfiltered,
            gracePeriod: 0,
            explicitlyIncludesAll: true
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

    @Test("terminate-and-eject 명령은 종료 실패가 있어도 eject 성공 시 비정상 종료 코드 반환")
    func terminateAndEjectReportsTerminationFailures() async {
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
            )
        ]

        let terminator = MockProcessTerminator()
        terminator.stubbedResults = [
            100: .terminated,
            200: .failed("Permission denied"),
        ]

        let ejector = MockDiskEjector()
        let result = await makeRunner(
            volumeMonitor: volumeMonitor,
            scanner: scanner,
            terminator: terminator,
            ejector: ejector
        ).run(.terminateAndEject(
            volumeQuery: "TestDrive",
            selection: .unfiltered,
            gracePeriod: 0,
            explicitlyIncludesAll: true
        ))

        #expect(result.exitCode == 1)
        #expect(result.stdout.contains("Ejected TestDrive."))
        #expect(result.stderr.contains("PID 200 failed"))
        #expect(ejector.ejectCalled)
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

    @Test("version 명령은 주입된 marketing/build 버전을 출력")
    func versionOutput() async {
        let result = await makeRunner(volumeMonitor: MockVolumeMonitor()).run(.version)

        #expect(result == .success("SSD_Remover 9.8.7 (build 654)"))
    }

    @Test("global help는 간결하고 command help는 기본값과 안전 규칙을 설명")
    func helpOutputDocumentsContract() async {
        let runner = makeRunner(volumeMonitor: MockVolumeMonitor())
        let global = await runner.run(.help)
        let terminate = await runner.run(.help(topic: .terminate))

        #expect(global.stdout.contains("<command> --help"))
        #expect(global.stdout.contains("version"))
        #expect(global.stdout.contains("--json"))
        #expect(!global.stdout.contains("filters form an intersection"))

        #expect(terminate.stdout.contains("default: 3 seconds"))
        #expect(terminate.stdout.contains("filters form an intersection"))
        #expect(terminate.stdout.contains("--all is required"))
        #expect(terminate.stdout.contains("--dry-run"))
        #expect(terminate.stdout.contains("sudo"))
        #expect(terminate.stdout.contains("Exit codes"))
    }

    @Test("scan 사람용 출력은 locked file을 중복 제거하고 제어 문자를 escape")
    func scanDisplaysLockedFilesSafely() async {
        let volumeMonitor = MockVolumeMonitor()
        await volumeMonitor.setVolumes([makeVolume()])

        let scanner = MockProcessScanner()
        scanner.stubbedResult = [
            ProcessGroup(
                category: .user,
                processes: [
                    makeProcess(
                        pid: 100,
                        command: "editor",
                        lockedFiles: [
                            "/Volumes/TestDrive/문서 | final.txt",
                            "/Volumes/TestDrive/line\nbreak.txt",
                            "/Volumes/TestDrive/문서 | final.txt",
                        ]
                    ),
                    makeProcess(pid: 200, command: "idle", lockedFiles: []),
                ]
            )
        ]

        let result = await makeRunner(
            volumeMonitor: volumeMonitor,
            scanner: scanner
        ).run(.scan(volumeQuery: "TestDrive"))

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("Locked file: \"/Volumes/TestDrive/line\\nbreak.txt\""))
        #expect(result.stdout.components(separatedBy: "문서 | final.txt").count == 2)
        #expect(result.stdout.contains("Locked files: none"))
        #expect(!result.stdout.contains("line\nbreak.txt"))
    }

    @Test("필터 없는 종료는 all 없이는 대상만 보여주고 side effect를 막음")
    func unfilteredTerminationRequiresExplicitAll() async {
        let volumeMonitor = MockVolumeMonitor()
        await volumeMonitor.setVolumes([makeVolume()])

        let scanner = MockProcessScanner()
        scanner.stubbedResult = [
            ProcessGroup(category: .user, processes: [makeProcess(pid: 100, command: "vim")]),
            ProcessGroup(category: .system, processes: [makeProcess(pid: 200, command: "daemon", user: "root", uid: 0)]),
            ProcessGroup(category: .spotlight, processes: [makeProcess(pid: 300, command: "mds", user: "root", uid: 0)]),
        ]
        let terminator = MockProcessTerminator()

        let result = await makeRunner(
            volumeMonitor: volumeMonitor,
            scanner: scanner,
            terminator: terminator
        ).run(.terminate(
            volumeQuery: "TestDrive",
            selection: .unfiltered,
            gracePeriod: 0
        ))

        #expect(result.exitCode == 64)
        #expect(result.stderr.contains("--all"))
        #expect(result.stderr.contains("PID 100"))
        #expect(result.stderr.contains("PID 200"))
        #expect(result.stderr.contains("PID 300"))
        #expect(terminator.terminatedProcesses.isEmpty)
    }

    @Test("dry-run은 전체 대상을 보여주고 종료나 eject를 실행하지 않음")
    func dryRunHasNoSideEffects() async {
        let volumeMonitor = MockVolumeMonitor()
        await volumeMonitor.setVolumes([makeVolume()])

        let scanner = MockProcessScanner()
        scanner.stubbedResult = [
            ProcessGroup(category: .user, processes: [makeProcess(pid: 100, command: "vim")])
        ]
        let terminator = MockProcessTerminator()
        let ejector = MockDiskEjector()

        let result = await makeRunner(
            volumeMonitor: volumeMonitor,
            scanner: scanner,
            terminator: terminator,
            ejector: ejector
        ).run(.terminateAndEject(
            volumeQuery: "TestDrive",
            selection: .unfiltered,
            gracePeriod: 0,
            dryRun: true
        ))

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("Dry run"))
        #expect(result.stdout.contains("PID 100"))
        #expect(terminator.terminatedProcesses.isEmpty)
        #expect(ejector.ejectCalled == false)
    }

    @Test("list JSON은 schema와 전체 volume 필드를 제공")
    func listJSONSchema() async throws {
        let volumeMonitor = MockVolumeMonitor()
        await volumeMonitor.setVolumes([makeVolume(name: "Backup | \"SSD\"")])

        let result = await makeRunner(volumeMonitor: volumeMonitor).run(
            .listVolumes(outputFormat: .json)
        )
        let object = try jsonObject(result.stdout)
        let data = try jsonData(result.stdout)
        let volumes = try #require(data["volumes"] as? [[String: Any]])
        let volume = try #require(volumes.first)

        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["success"] as? Bool == true)
        #expect(object["command"] as? String == "list")
        #expect(volume["name"] as? String == "Backup | \"SSD\"")
        #expect(volume["fileSystem"] as? String == "APFS")
        #expect(volume["totalCapacity"] as? Int64 == 1_000_000_000_000)
    }

    @Test("scan JSON은 category와 안전한 lockedFiles를 보존")
    func scanJSONSchemaAndEscaping() async throws {
        let volumeMonitor = MockVolumeMonitor()
        await volumeMonitor.setVolumes([makeVolume()])
        let scanner = MockProcessScanner()
        scanner.stubbedResult = [
            ProcessGroup(
                category: .user,
                processes: [makeProcess(
                    pid: 100,
                    command: "editor | \"beta\"",
                    lockedFiles: ["/Volumes/TestDrive/b", "/Volumes/TestDrive/a\nline", "/Volumes/TestDrive/b"]
                )]
            )
        ]

        let result = await makeRunner(
            volumeMonitor: volumeMonitor,
            scanner: scanner
        ).run(.scan(volumeQuery: "disk4s1", outputFormat: .json))
        let data = try jsonData(result.stdout)
        let groups = try #require(data["groups"] as? [[String: Any]])
        let group = try #require(groups.first)
        let processes = try #require(group["processes"] as? [[String: Any]])
        let process = try #require(processes.first)

        #expect(group["category"] as? String == "user")
        #expect(process["pid"] as? Int == 100)
        #expect(process["command"] as? String == "editor | \"beta\"")
        #expect(process["lockedFiles"] as? [String] == [
            "/Volumes/TestDrive/a\nline",
            "/Volumes/TestDrive/b",
        ])
    }

    @Test("모든 파괴적 운영 명령은 JSON 결과를 반환")
    func destructiveCommandsReturnJSON() async throws {
        let volumeMonitor = MockVolumeMonitor()
        await volumeMonitor.setVolumes([makeVolume()])
        let scanner = MockProcessScanner()
        scanner.stubbedResult = [
            ProcessGroup(category: .user, processes: [makeProcess(pid: 100, command: "vim")])
        ]

        let terminateResult = await makeRunner(
            volumeMonitor: volumeMonitor,
            scanner: scanner
        ).run(.terminate(
            volumeQuery: "TestDrive",
            selection: CLIProcessSelection(pids: [100]),
            gracePeriod: 0,
            outputFormat: .json
        ))
        let terminateObject = try jsonObject(terminateResult.stdout)
        #expect(terminateObject["command"] as? String == "terminate")
        #expect(terminateObject["success"] as? Bool == true)

        let ejectResult = await makeRunner(volumeMonitor: volumeMonitor).run(
            .eject(volumeQuery: "TestDrive", outputFormat: .json)
        )
        let ejectData = try jsonData(ejectResult.stdout)
        #expect(ejectData["ejected"] as? Bool == true)

        let combinedResult = await makeRunner(
            volumeMonitor: volumeMonitor,
            scanner: scanner
        ).run(.terminateAndEject(
            volumeQuery: "TestDrive",
            selection: .unfiltered,
            gracePeriod: 0,
            explicitlyIncludesAll: true,
            outputFormat: .json
        ))
        let combinedData = try jsonData(combinedResult.stdout)
        #expect(combinedData["ejected"] as? Bool == true)
        #expect(combinedData["terminationResults"] as? [[String: Any]] != nil)
    }

    @Test("JSON preflight 오류는 stdout 없이 구조화된 stderr로 반환")
    func jsonErrorsAreStructuredOnStderr() async throws {
        let result = await makeRunner(volumeMonitor: MockVolumeMonitor()).run(
            .scan(volumeQuery: "missing", outputFormat: .json)
        )
        let object = try jsonObject(result.stderr)
        let error = try #require(object["error"] as? [String: Any])

        #expect(result.exitCode == 1)
        #expect(result.stdout.isEmpty)
        #expect(object["success"] as? Bool == false)
        #expect(error["code"] as? String == "volume_lookup_failed")
    }
}
