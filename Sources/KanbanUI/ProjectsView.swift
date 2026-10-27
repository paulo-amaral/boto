import AppKit
import KanbanCore
import SwiftData
import SwiftUI

public struct ProjectsView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.createdAt)
    private var projects: [Project]
    @AppStorage("selectedProjectId") private var selectedId = ""
    @AppStorage("sidebarCollapsed") private var collapsed = false
    @AppStorage("showArchivedProjects") private var showArchivedProjects = false
    @State private var renaming: Project?
    @State private var deleting: Project?
    @State private var paletteOpen = false
    @State private var showHelp = false
    @State private var showGitHub = false
    @State private var showImport = false
    @State private var showDeleted = false
    @State private var changingIcon: Project?
    @Environment(\.openWindow) private var openWindow
    @State private var fileVault = SystemSecurity.FileVaultState.unknown
    @State private var fileVaultNoticeDismissed = false
    @State private var windowWidth: CGFloat = 1200
    @State private var sidebarForcedOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let backup: BackupMonitor?
    @State private var backupNoticeDismissed = false

    public init(backup: BackupMonitor? = nil) { self.backup = backup }

    private var groups: ProjectGroups { ProjectGroups(projects) }

    private var compact: Bool { windowWidth < Theme.compactBreakpoint }

    /// In a narrow window the sidebar folds away by itself; its button can still pull it open for a moment.
    private var isCollapsed: Bool { compact ? !sidebarForcedOpen : collapsed }

    private func toggleSidebar() {
        if compact { sidebarForcedOpen.toggle() } else { collapsed.toggle() }
    }

    private func openSidebar() {
        if compact { sidebarForcedOpen = true } else { collapsed = false }
    }

    private var selected: Project? {
        let choices = groups.selectable(showArchived: showArchivedProjects)
        return choices.first { $0.publicId == selectedId } ?? choices.first
    }

    public var body: some View {
        VStack(spacing: 0) {
            if fileVault == .off && !fileVaultNoticeDismissed { fileVaultNotice }
            if let problem = backup?.problem, !backupNoticeDismissed {
                NoticeBar(text: "The daily backup failed: \(problem)", dismiss: { backupNoticeDismissed = true })
            }
            HStack(spacing: 0) {
                sidebar
                detail
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.card))
                    .padding(.vertical, 8)
                    .padding(.trailing, 8)
            }
        }
        .background(Theme.background)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { windowWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { windowWidth = proxy.size.width }
        })
        .environment(\.isCompactWindow, compact)
        .environment(\.stacksBoard, windowWidth < Theme.stackBreakpoint)
        .onChange(of: compact) { sidebarForcedOpen = false }
        .overlay { if paletteOpen { palette } }
        .background(shortcutButtons)
        .background(MovableByBackground())
        .onAppear { ShortcutMonitor.install() }
        .onReceive(NotificationCenter.default.publisher(for: .botoNewList)) { _ in addList() }
        .onReceive(NotificationCenter.default.publisher(for: .botoShowHelp)) { _ in showHelp = true }
        .onReceive(NotificationCenter.default.publisher(for: .botoGoToProjects)) { _ in openSidebar() }
        .task { if projects.isEmpty { create(named: "My project") } }
        // Covers new, imported and pre-existing projects alike.
        .task(id: projects.count) { ProjectIcons.assignMissing(to: projects) }
        .task { fileVault = await Task.detached { SystemSecurity.fileVaultState() }.value }
        .modifier(ProjectSheets(
            showHelp: $showHelp, showGitHub: $showGitHub, showImport: $showImport, showDeleted: $showDeleted, changingIcon: $changingIcon,
            renaming: $renaming, deleting: $deleting, selectedId: $selectedId
        ))
    }

    private var shortcutButtons: some View {
        Group {
            Button("Search") { paletteOpen.toggle() }.keyboardShortcut("k", modifiers: .command)
            Button("New project") { renaming = create(named: "New project") }.keyboardShortcut("n", modifiers: .command)
            Button("Toggle sidebar") { toggleSidebar() }.keyboardShortcut("s", modifiers: [.command, .control])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    // MARK: Sidebar

    /// Collapsible: 256 pt with names, or a narrow rail with initials.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !isCollapsed {
                    Text("Boto").font(Theme.font(16, weight: .bold)).foregroundStyle(Theme.text).padding(.leading, 8)
                    Spacer()
                }
                Button { toggleSidebar() } label: {
                    Image(systemName: "sidebar.left").frame(maxWidth: isCollapsed ? .infinity : 32, minHeight: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
                .help(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
            }
            .frame(height: 45)

            Rectangle().fill(Theme.divider).frame(height: 1).padding(.horizontal, 4)

            sidebarButton("magnifyingglass", "Search", shortcut: "⌘K", help: "Search (⌘K)") { paletteOpen = true }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !groups.favorites.isEmpty {
                        sectionHeader("FAVORITES")
                        ForEach(groups.favorites) { row(for: $0) }
                    }
                    projectsHeader
                    ForEach(groups.active) { row(for: $0) }
                    if showArchivedProjects && !groups.archived.isEmpty {
                        sectionHeader("ARCHIVED")
                        ForEach(groups.archived) { row(for: $0) }
                    }
                }
            }
            .scrollIndicators(.hidden)

            sidebarButton("square.and.arrow.down", "Import", help: "Import from Trello or GitHub") { showImport = true }
            sidebarButton("arrow.uturn.backward.circle", "Recently deleted", help: "Restore deleted projects, lists and cards") { showDeleted = true }
            sidebarButton("chevron.left.forwardslash.chevron.right", "GitHub", help: "GitHub settings") { showGitHub = true }
            sidebarButton("questionmark.circle", "Help", shortcut: "/", help: "Help (/)") { showHelp = true }
        }
        .padding(12)
        .frame(width: isCollapsed ? 64 : 256)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isCollapsed)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.list)
    }

    private func sidebarButton(_ icon: String, _ title: String, shortcut: String? = nil, help: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(maxWidth: isCollapsed ? .infinity : nil)
                if !isCollapsed {
                    Text(title).font(Theme.font(13))
                    Spacer()
                    if let shortcut { Text(shortcut).font(Theme.font(11)).foregroundStyle(Theme.muted) }
                }
            }
            .padding(.horizontal, isCollapsed ? 0 : 10)
            .padding(.vertical, 7)
            .rowHighlight()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.mutedStrong)
        .help(help)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        if !isCollapsed {
            Text(title).font(Theme.font(10, weight: .semibold)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
        }
    }

    private var projectsHeader: some View {
        HStack {
            if !isCollapsed {
                Text("PROJECTS").font(Theme.font(10, weight: .semibold)).foregroundStyle(Theme.muted)
                Spacer()
            }
            if !groups.archived.isEmpty {
                Button { showArchivedProjects.toggle() } label: {
                    Image(systemName: showArchivedProjects ? "archivebox.fill" : "archivebox")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.mutedStrong)
                .help(showArchivedProjects ? "Hide archived projects" : "Show archived projects")
            }
            Button { renaming = create(named: "New project") } label: {
                Image(systemName: "plus").frame(maxWidth: isCollapsed ? .infinity : nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.mutedStrong)
            .help("New project")
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private func row(for project: Project) -> some View {
        let isSelected = project.publicId == selected?.publicId
        return HStack(spacing: 8) {
            if isCollapsed {
                ProjectIconView(icon: project.icon, size: 17)
                    .frame(maxWidth: .infinity, minHeight: 28)
            } else {
                ProjectIconView(icon: project.icon)
                    .foregroundStyle(Theme.muted)
                Text(project.name).font(Theme.font(13)).lineLimit(1)
                Spacer()
                if project.isFavorite { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Theme.muted) }
            }
        }
        .padding(.horizontal, isCollapsed ? 0 : 10)
        .padding(.vertical, 7)
        .foregroundStyle(Theme.text)
        .opacity(project.isArchived ? 0.55 : 1)
        .rowHighlight(selected: isSelected)
        .help(project.name)
        .contentShape(Rectangle())
        .onTapGesture { selectedId = project.publicId }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default) { selectedId = project.publicId }
        .contextMenu {
            ProjectActions(entries: ProjectMenu.entries(
                for: project,
                onRename: { renaming = project },
                onChangeIcon: { changingIcon = project },
                onChooseRoot: { chooseRoot(for: project) },
                onDelete: { deleting = project }
            ))
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let project = selected, let board = project.activeBoards.first {
            BoardView(
                board: board,
                onChooseRoot: { chooseRoot(for: project) },
                onDelete: { deleting = project }
            )
                .id(board.publicId)
        } else {
            VStack(spacing: 12) {
                Text("No project yet").foregroundStyle(Theme.muted)
                Button("New project") { renaming = create(named: "New project") }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var fileVaultNotice: some View {
        NoticeBar(
            text: "FileVault is off. Boto does not encrypt its own data, so your projects are stored unencrypted on this disk.",
            actionTitle: "Open Settings",
            action: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") { NSWorkspace.shared.open(url) }
            },
            dismiss: { fileVaultNoticeDismissed = true }
        )
    }

    private var palette: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { paletteOpen = false }
            CommandPalette(projects: projects, onSelect: select, onClose: { paletteOpen = false })
                .padding(.top, 120)
        }
    }

    // MARK: Actions

    private func select(_ result: SearchResult) {
        paletteOpen = false
        switch result {
        case .project(let project):
            selectedId = project.publicId
        case .card(let card):
            if let project = card.list?.board?.project { selectedId = project.publicId }
            openWindow(value: CardWindowID(cardId: card.publicId))
        }
    }

    private func addList() {
        guard let board = selected?.activeBoards.first else { return }
        board.lists.append(BoardList(name: "New list", index: board.orderedLists.count))
    }

    @discardableResult
    private func create(named name: String) -> Project {
        let project = Project(name: name)
        context.insert(project)
        project.addBoard(name: name)
        selectedId = project.publicId
        return project
    }

    private func chooseRoot(for project: Project) {
        if let url = FilePanel.choose(files: false, directories: true, multiple: false).first {
            project.setRootFolder(url)
        }
    }
}

/// An amber bar across the top of the window, for problems the user should know about and can dismiss.
private struct NoticeBar: View {
    let text: String
    var actionTitle: String?
    var action: () -> Void = {}
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(Theme.font(12)).lineLimit(2)
            Spacer()
            if let actionTitle { Button(actionTitle, action: action) }
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .foregroundStyle(Color.black)
        .background(Color(hex: "#f59e0b"))
    }
}

/// Sheets and the delete confirmation, split out so `ProjectsView.body` stays quick to type-check.
private struct ProjectSheets: ViewModifier {
    @Binding var showHelp: Bool
    @Binding var showGitHub: Bool
    @Binding var showImport: Bool
    @Binding var showDeleted: Bool
    @Binding var changingIcon: Project?
    @Binding var renaming: Project?
    @Binding var deleting: Project?
    @Binding var selectedId: String

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showHelp) { HelpView() }
            .sheet(isPresented: $showGitHub) { GitHubSettingsSheet() }
            .sheet(isPresented: $showImport) { ImportSheet { selectedId = $0.publicId } }
            .sheet(isPresented: $showDeleted) { RecentlyDeletedView() }
            .sheet(item: $changingIcon) { ProjectIconPicker(project: $0) }
            .sheet(item: $renaming) { RenameProjectSheet(project: $0) }
            .confirmationDialog(
                "Delete \"\(deleting?.name ?? "")\"?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                presenting: deleting
            ) { project in
                Button("Delete project", role: .destructive) { project.deletedAt = Date() }
            } message: { _ in
                Text("The project and its boards disappear from Boto. Your files are not touched. Archive it instead to keep it out of the way.")
            }
    }
}

private struct RenameProjectSheet: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Project name").font(Theme.font(13, weight: .medium))
            TextField("Name", text: $project.name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { dismiss() }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}
