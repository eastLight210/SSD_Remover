import Testing
import Foundation
@testable import SSD_Remover

@Suite("ExternalVolume Tests")
struct ExternalVolumeTests {

    @Test("기본 초기화")
    func basicInitialization() {
        let url = URL(fileURLWithPath: "/Volumes/MyDrive")
        let volume = ExternalVolume(
            id: url,
            name: "MyDrive",
            deviceIdentifier: "disk4s1",
            fileSystem: "APFS",
            totalCapacity: 1_000_000_000_000,
            availableCapacity: 500_000_000_000,
            mountPoint: url
        )

        #expect(volume.name == "MyDrive")
        #expect(volume.deviceIdentifier == "disk4s1")
        #expect(volume.fileSystem == "APFS")
        #expect(volume.totalCapacity == 1_000_000_000_000)
        #expect(volume.availableCapacity == 500_000_000_000)
        #expect(volume.mountPoint == url)
    }

    @Test("Identifiable - id는 mountPoint URL")
    func identifiableConformance() {
        let url = URL(fileURLWithPath: "/Volumes/TestDrive")
        let volume = ExternalVolume(
            id: url,
            name: "TestDrive",
            deviceIdentifier: "disk2s1",
            fileSystem: "ExFAT",
            totalCapacity: 500_000_000_000,
            availableCapacity: 250_000_000_000,
            mountPoint: url
        )

        #expect(volume.id == url)
    }

    @Test("Equatable - 같은 id를 가진 볼륨은 동일")
    func equatableConformance() {
        let url = URL(fileURLWithPath: "/Volumes/SameDrive")
        let vol1 = ExternalVolume(
            id: url, name: "SameDrive", deviceIdentifier: "disk3s1",
            fileSystem: "APFS", totalCapacity: 100, availableCapacity: 50, mountPoint: url
        )
        let vol2 = ExternalVolume(
            id: url, name: "SameDrive", deviceIdentifier: "disk3s1",
            fileSystem: "APFS", totalCapacity: 100, availableCapacity: 50, mountPoint: url
        )

        #expect(vol1 == vol2)
    }

    @Test("formattedCapacity - GB 단위")
    func formattedCapacityGB() {
        let url = URL(fileURLWithPath: "/Volumes/Drive")
        let volume = ExternalVolume(
            id: url, name: "Drive", deviceIdentifier: "disk2s1",
            fileSystem: "APFS",
            totalCapacity: 500_000_000_000,
            availableCapacity: 250_000_000_000,
            mountPoint: url
        )

        let formatted = volume.formattedCapacity
        #expect(formatted.contains("500"))
        #expect(formatted.contains("250"))
    }

    @Test("formattedCapacity - TB 단위")
    func formattedCapacityTB() {
        let url = URL(fileURLWithPath: "/Volumes/BigDrive")
        let volume = ExternalVolume(
            id: url, name: "BigDrive", deviceIdentifier: "disk5s1",
            fileSystem: "APFS",
            totalCapacity: 2_000_000_000_000,
            availableCapacity: 1_500_000_000_000,
            mountPoint: url
        )

        let formatted = volume.formattedCapacity
        #expect(formatted.contains("2"))
        #expect(formatted.contains("1.5") || formatted.contains("1,5"))
    }

    @Test("Hashable - Set에 저장 가능")
    func hashableConformance() {
        let url1 = URL(fileURLWithPath: "/Volumes/Drive1")
        let url2 = URL(fileURLWithPath: "/Volumes/Drive2")
        let vol1 = ExternalVolume(
            id: url1, name: "Drive1", deviceIdentifier: "disk2s1",
            fileSystem: "APFS", totalCapacity: 100, availableCapacity: 50, mountPoint: url1
        )
        let vol2 = ExternalVolume(
            id: url2, name: "Drive2", deviceIdentifier: "disk3s1",
            fileSystem: "ExFAT", totalCapacity: 200, availableCapacity: 100, mountPoint: url2
        )

        var set = Set<ExternalVolume>()
        set.insert(vol1)
        set.insert(vol2)
        set.insert(vol1) // duplicate

        #expect(set.count == 2)
    }
}
