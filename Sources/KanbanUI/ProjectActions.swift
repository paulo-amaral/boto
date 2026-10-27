import AppKit
import KanbanCore
import SwiftUI

/// The project menu (root folder, archive, favorites, delete). The root folder is the closest thing a Boto
/// project has to an address.
enum ProjectMenu {
    static func entries(for project: Project, onRename: (() -> Void)? = nil, onChangeIcon: (() -> Void)? = nil,
                        onChooseRoot: @escaping () -> Void, onDelete: @escaping () -> Void) -> [DropdownEntry] {
        var entries: [DropdownEntry] = []
        if let onRename { entries.append(DropdownEntry(icon: "pencil", title: "Rename...", action: onRename)) }
        if let onChangeIcon { entries.append(DropdownEntry(icon: "square.grid.2x2", title: "Change icon...", action: onChangeIcon)) }
        entries.append(DropdownEntry(
            icon: "folder",
            title: project.rootFolderPath == nil ? "Set root folder..." : "Edit root folder...",
            action: onChooseRoot
        ))
        if let root = project.rootFolderURL {
            entries.append(DropdownEntry(icon: "magnifyingglass", title: "Reveal root folder") {
                NSWorkspace.shared.activateFileViewerSelecting([root])
            })
            entries.append(DropdownEntry(icon: "xmark", title: "Clear root folder") { project.setRootFolder(nil) })
        }
        entries.append(DropdownEntry(
            icon: project.isArchived ? "arrow.uturn.backward" : "archivebox",
            title: project.isArchived ? "Restore project" : "Archive project"
        ) { project.setArchived(!project.isArchived) })
        entries.append(DropdownEntry(
            icon: project.isFavorite ? "star.fill" : "star",
            title: project.isFavorite ? "Remove from favorites" : "Add to favorites"
        ) { project.setFavorite(!project.isFavorite) })
        entries.append(.divider)
        entries.append(DropdownEntry(icon: "trash", title: "Delete project...", destructive: true, action: onDelete))
        return entries
    }
}

/// The same entries as a native context menu (right-click in the sidebar).
struct ProjectActions: View {
    let entries: [DropdownEntry]

    var body: some View {
        // macOS menus show only the title of a `Label` unless the label style asks for the icon too.
        ForEach(entries) { entry in
            if entry.isDivider {
                Divider()
            } else {
                Button(role: entry.destructive ? .destructive : nil, action: entry.action) {
                    Label(entry.title, systemImage: entry.icon)
                }
            }
        }
        .labelStyle(.titleAndIcon)
    }
}
