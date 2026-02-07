import Foundation

enum PrivilegedExecutorError: Error, Equatable {
    case scriptError(String)
    case userCancelled
}

actor PrivilegedExecutor: PrivilegedExecuting {
    func executeWithPrivileges(command: String) async throws -> String {
        let escapedCommand = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escapedCommand)\" with administrator privileges"

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorInfo: NSDictionary?
                let script = NSAppleScript(source: source)
                let result = script?.executeAndReturnError(&errorInfo)

                if let error = errorInfo {
                    let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? -1
                    if errorNumber == -128 {
                        continuation.resume(throwing: PrivilegedExecutorError.userCancelled)
                    } else {
                        let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                        continuation.resume(throwing: PrivilegedExecutorError.scriptError(message))
                    }
                } else {
                    let output = result?.stringValue ?? ""
                    continuation.resume(returning: output)
                }
            }
        }
    }
}
