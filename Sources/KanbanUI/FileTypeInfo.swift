import AppKit
import KanbanCore
import UniformTypeIdentifiers

/// What an attachment is, for its icon and its label: a file shows the icon and the name the Finder gives its type.
enum FileTypeInfo {
    static func name(for reference: Reference) -> String {
        switch reference.kind {
        case .folder: "Folder"
        case .obsidianNote: "Obsidian note"
        case .githubIssue: "GitHub issue"
        case .githubPullRequest: "GitHub pull request"
        case .email: "Email"
        case .file: fileTypeName(forPath: reference.displayPath)
        }
    }

    /// "PDF document", "Microsoft Excel spreadsheet"; a type the system does not know is "ZZZ file".
    static func fileTypeName(forPath path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension
        guard !ext.isEmpty else { return "File" }
        if let description = UTType(filenameExtension: ext)?.localizedDescription, !description.isEmpty {
            return description.prefix(1).uppercased() + description.dropFirst()
        }
        return "\(ext.uppercased()) file"
    }

    /// The Finder icon of the file itself when it is there (a custom folder icon, an app), otherwise the icon of its
    /// type, so a missing file still looks like what it was. Nil for things that are not files.
    static func image(for reference: Reference, resolved: URL?) -> NSImage? {
        switch reference.kind {
        case .file, .folder, .obsidianNote:
            if let resolved, FileManager.default.fileExists(atPath: resolved.path) { return NSWorkspace.shared.icon(forFile: resolved.path) }
            let ext = URL(fileURLWithPath: reference.displayPath).pathExtension
            let type: UTType = reference.kind == .folder ? .folder : (UTType(filenameExtension: ext) ?? (reference.kind == .obsidianNote ? .plainText : .data))
            return NSWorkspace.shared.icon(for: type)
        case .githubIssue, .githubPullRequest, .email:
            return nil
        }
    }

    static func symbol(for kind: ReferenceKind) -> String {
        switch kind {
        case .file: "doc"
        case .folder: "folder"
        case .obsidianNote: "note.text"
        case .githubIssue: "smallcircle.filled.circle"
        case .githubPullRequest: "arrow.triangle.pull"
        case .email: "envelope"
        }
    }
}
