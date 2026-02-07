import Testing
import Foundation
@testable import SSD_Remover

@Suite("PrivilegedExecutor Tests")
struct PrivilegedExecutorTests {

    @Test("escapeForAppleScript - 쌍따옴표 이스케이핑")
    func escapesDoubleQuotes() {
        let escaped = PrivilegedExecutor.escapeForAppleScript("echo \"hello\"")
        #expect(escaped == "echo \\\"hello\\\"")
    }

    @Test("escapeForAppleScript - 백슬래시 이스케이핑")
    func escapesBackslashes() {
        let escaped = PrivilegedExecutor.escapeForAppleScript("path\\with\\backslash")
        #expect(escaped == "path\\\\with\\\\backslash")
    }

    @Test("escapeForAppleScript - 이스케이핑 불필요한 문자열")
    func noEscapingNeeded() {
        let escaped = PrivilegedExecutor.escapeForAppleScript("/bin/kill -15 1234")
        #expect(escaped == "/bin/kill -15 1234")
    }

    @Test("escapeForAppleScript - 백슬래시와 쌍따옴표 혼합")
    func mixedEscaping() {
        let escaped = PrivilegedExecutor.escapeForAppleScript("echo \"path\\file\"")
        #expect(escaped == "echo \\\"path\\\\file\\\"")
    }
}
