import Observation

/// Holds the outcome of the latest daily backup, so a failure shows in the window instead of staying silent.
/// `problem` is nil while backups work. It is only written on the main actor.
@Observable
public final class BackupMonitor: @unchecked Sendable {
    public var problem: String?

    public init() {}
}
