import KanbanCore
import KanbanUI
import SwiftData
import SwiftUI

@main
struct BotoApp: App {
    /// One container for every window. Two `.modelContainer(for:)` modifiers would open two separate stores.
    private let container: ModelContainer
    private let backup = BackupMonitor()

    init() {
        // A bare SwiftPM executable has no Info.plist, so macOS starts it as a background
        // process with no window. Becoming a regular app makes `swift run` behave like Xcode.
        Theme.registerFonts()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Boto's own store, not SwiftData's default `Application Support/default.store`: every unsandboxed app that
        // uses the default shares that file, and another app with a different model can migrate it and drop Boto's tables.
        let storeURL: URL
        do {
            storeURL = try BotoPaths.storeURL()
            try StoreCompatibility.check(store: storeURL)
            container = try ModelContainer(for: Schema(KanbanSchema.models), configurations: ModelConfiguration(url: storeURL))
        } catch let newer as StoreCompatibility.NewerStore {
            // Say why instead of crashing: nothing was opened or changed, and the person only has to update Boto.
            let alert = NSAlert()
            alert.messageText = "Boto cannot open this database"
            alert.informativeText = newer.localizedDescription
            alert.runModal()
            exit(1)
        } catch {
            fatalError("Could not open the Boto database: \(error)")
        }
        Self.startBackups(of: storeURL, reportingTo: backup)
    }

    /// Once at launch and every six hours after, so an app left open for days still backs up each day.
    /// `runDaily` does nothing when today's copy exists, and a failure is shown in the window.
    private static func startBackups(of store: URL, reportingTo monitor: BackupMonitor) {
        Task.detached(priority: .utility) {
            while !Task.isCancelled {
                let problem: String?
                do {
                    _ = try DatabaseBackup.runDaily(store: store, folder: try BotoPaths.backupsFolder())
                    problem = nil
                } catch {
                    problem = error.localizedDescription
                }
                await MainActor.run { monitor.problem = problem }
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ProjectsView(backup: backup)
                .preferredColorScheme(.dark)
                .frame(minWidth: 640, minHeight: 440)
        }
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Boto Help") { NotificationCenter.default.post(name: Notification.Name("boto.showHelp"), object: nil) }
            }
        }

        WindowGroup("Card", for: CardWindowID.self) { $id in
            if let id { CardWindowView(cardId: id.cardId).preferredColorScheme(.dark) }
        }
        .modelContainer(container)
        .defaultSize(width: 900, height: 680)
        .windowResizability(.contentMinSize)
    }
}
