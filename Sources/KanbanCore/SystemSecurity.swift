import Foundation

/// Boto does not implement its own cryptography. Protection of data at rest comes from the operating system,
/// so the app checks that it is switched on and says so when it is not.
public enum SystemSecurity {
    public enum FileVaultState: Equatable, Sendable {
        case on, off, unknown
    }

    static func parseFileVault(_ output: String) -> FileVaultState {
        let text = output.lowercased()
        if text.contains("filevault is on") { return .on }
        if text.contains("filevault is off") { return .off }
        return .unknown
    }

    /// Runs `fdesetup status` (no admin rights needed). Blocking: call it off the main thread.
    public static func fileVaultState() -> FileVaultState {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
        process.arguments = ["status"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return .unknown }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parseFileVault(String(decoding: data, as: UTF8.self))
    }
}
