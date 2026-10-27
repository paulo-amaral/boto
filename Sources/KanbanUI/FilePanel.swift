import AppKit
import UniformTypeIdentifiers

enum FilePanel {
    static func choose(files: Bool, directories: Bool, multiple: Bool, types: [UTType] = []) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = files
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = multiple
        if !types.isEmpty { panel.allowedContentTypes = types }
        return panel.runModal() == .OK ? panel.urls : []
    }
}
