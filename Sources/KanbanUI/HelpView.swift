import AppKit
import KanbanCore
import SwiftUI

/// Describes only what Boto does today; update it together with each new feature.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    /// Where boto-mcp sits in the app that is running. A bare `swift run` has no bundle, so the usual place is shown.
    private static var mcpPath: String {
        let bundle = Bundle.main.bundlePath
        return (bundle.hasSuffix(".app") ? bundle : "/Applications/Boto.app") + "/Contents/MacOS/boto-mcp"
    }

    private let topics: [(title: String, lines: [String])] = [
        ("Projects", [
            "Create a project with the + in the sidebar or with ⌘N. Right-click a project to rename it, set its root folder or delete it.",
            "Change icon, in the project menu, picks the project's icon from about 1,900 Lucide icons, with search; Automatic hands the choice back to Boto.",
            "Duplicate project, in the project menu, makes a copy with the same boards, lists, labels, checklists and cards, and opens it. Hours, activity, the Kaizen log and Apple Calendar links stay with the original, so the copy starts without history. It is also a way to reuse a project as a template.",
            "The project menu (the ... in the board header, or right-click in the sidebar) has Edit root folder, Archive project, Add to favorites and Delete project. Each project gets its own icon automatically, and it cannot be changed; the collapsed sidebar shows that icon. Favorites are listed first. Archived projects are hidden, and left out of search, until you click the archive icon next to PROJECTS.",
            "The root folder is usually the client folder or your Obsidian vault. Boto keeps a link to it and never copies your files. Set, change or reveal it from the ... menu in the board header.",
            "Collapse the sidebar with the button at its top; it keeps one tile per project. In a window narrower than 700 points the kanban columns become one vertical list, with each list under the previous one. In a window narrower than 900 points the sidebar collapses by itself, the buttons in the board header lose their text, and lists get narrower. Rename a project or a list by double-clicking its name.",
        ]),
        ("Cards", [
            "A card opens in its own window, so you can drag it aside (by its title bar) and keep the board in view while you edit. Clicking the same card again brings its window forward.",
            "Importance (High, Medium, Low) is set from the Importance button in the card and shows as a coloured ! on the card. Group by importance, in the board header, lays the board out in lanes by importance with your lists as columns. Dropping a card in a cell moves it to that list and gives it that importance.",
            "Apple Calendar: in a card's Dates, tick Add to Apple Calendar to put the due date in a calendar named Boto. Optionally set a time and an alert; without a time the event lasts all day and alerts at 9:00. Completing or archiving the card removes its event. Boto's ... menu has Add dated cards to Apple Calendar for every open card with a date. The sync is one way: edits made in Calendar are overwritten.",
            "The round box beside a card's title marks it complete; completed cards show a green check on the board.",
            "You can drag the window by any empty part of it, not only by the title bar.",
            "Click a card to open it. The main column has the title, description, checklists, references and the activity feed with a comment box (⌘↩ sends). The side panel sets the list, labels, due date and colour.",
            "Activity records when a card is created, moved to another list, archived or restored, when its due date or labels change, and your comments. Edits to the title and description are not logged.",
            "Drag a card to reorder it or to move it to another list. Add a card with the + on a list.",
            "The card colour tints the whole card. Click a label's dot to change that label's colour.",
            "Command-click cards to select several. Then use the bar at the bottom to move them to a list, set a colour or delete them. Esc or Clear ends the selection.",
            "Archive hides a card or a list without deleting it: use Archive in the card, Archive list in the list's ... menu, or the selection bar. Show archived, in the board's ... menu, brings them back into view so you can Restore them. Archived items are left out of search.",
            "In a list's ... menu, Paste cards from text creates one card per line and removes bullets, numbers and checkboxes.",
        ]),
        ("References", [
            "In a card, add files, folders or notes, or drop them on the References box.",
            "A markdown file inside an Obsidian vault is stored as a note and opens in Obsidian. Other items open with the default app.",
            "If a file moves, Boto follows it. If it cannot be found, the item shows as Missing.",
            "Add GitHub issue or PR links a GitHub item to the card and shows its state (open, closed, merged, draft). The refresh button re-reads it. Boto only reads from GitHub.",
            "For private repositories, open GitHub in the sidebar and save a fine-grained token with read-only access to Issues and Pull requests. It is kept in the macOS Keychain.",
        ]),
        ("Import", [
            "Import in the sidebar creates a new project from a Trello board (an exported JSON file) or from the issues of a GitHub repository. Nothing is changed in Trello or GitHub.",
            "Trello: lists, cards, labels, due dates, descriptions and checklists come across. Archived lists and cards are skipped unless you tick Include archived; then they arrive archived.",
            "GitHub: each issue becomes a card linked to the issue, in an Open list and, if you include them, a Closed list. Pull requests are skipped, and the import stops at 1000 issues.",
        ]),
        ("Email", [
            "Drag a message from Apple Mail onto a list to make a card from it: the subject is the title, and the sender, date and start of the text go in the description. Drag it onto a card to add it to that card instead.",
            "Either way the card gets a From email attachment that opens the message in Mail. Mail can only open messages it has downloaded.",
            "The card appears at once with the subject and the link. The sender, date and start of the text fill in a few seconds later, when Mail hands over the message file (it can take up to 20 seconds, and sometimes never does; the card is still complete without it). Dropping also works on the importance lanes.",
            "If a drop does not work, the list shows exactly what Mail offered, so the problem can be fixed.",
        ]),
        ("Flow", [
            "Each list has a stage: Not started, In progress or Done. By default the first list is Not started, the last is Done and the others are In progress. Change it in a list's ... menu, under Flow settings. A card's cycle time runs from entering an In progress list to entering a Done list; cards imported from Trello or GitHub have no history, so they are left out of the numbers.",
            "The number in a list header counts its cards. With a WIP limit set (Flow settings) it reads 2/3 and turns red when you go over. The limit is soft: Boto never stops you, it only shows it. A short limit, 1 to 3 items in progress, is the usual advice for personal Kanban.",
            "A list can also hold a policy, one line that says when a card may leave it. It shows under the list name.",
            "Block, in a card, marks it as waiting on something, with a reason. Blocked cards show a red Blocked tag and are listed in Flow.",
            "Flow, in the board header, shows work in progress, cards finished, median cycle time, the number of days within which 85% of your cards finish, throughput per week, a cumulative flow chart and the oldest work in progress. These are the measures of the Kanban Guide.",
            "Kaizen, at the top of Flow, keeps small experiments in four steps: the problem you saw, the one change you will try, what you expect, and a review date. When the date arrives it shows Review due; write what happened and choose Adopted, Adjusted or Dropped. Dropped experiments keep their lesson. Try one at a time.",
            "Numbers start to mean something after a handful of finished cards.",
        ]),
        ("Hours", [
            "Hours, in the board header, opens the project's timesheet: one row per task (a card), one column per day of the week, with totals for each task, each day and the week. Use the arrows to change week and This week to come back. Add task puts a card that has no time yet on the sheet. The No card row is for work on the project itself.",
            "Click a cell to see what makes up that day. Change a duration or description in place, delete an entry with the trash icon, or add one at the bottom with the time and what you worked on. Time can be typed as 1:30, 1.5, 90m or 2h30. Setting a duration to 0 deletes the entry.",
            "Export CSV writes the week as a spreadsheet: one line per task with the hours of each day as decimals, and a total line.",
            "Report, at the top of the window, shows the time between any two dates (or this or last week or month) by day and by card, lists every entry, and exports one CSV line per entry.",
            "In a card, Time keeps a timer and lets you add time by hand. Only one timer runs at a time, so starting another stops the first. A timer that runs past midnight counts for the day it started. The card shows its total with an hourglass, or a timer icon while running.",
        ]),
        ("AI assistants", [
            "Boto includes boto-mcp, a small server that lets an AI assistant such as Claude read your boards. It runs on your Mac, and only when the assistant starts it.",
            "In Claude Code, run: claude mcp add boto -- \"\(HelpView.mcpPath)\". In another assistant, add that path as a stdio server in its MCP settings.",
            "It only reads by default. To let the assistant create and change cards, add the argument --allow-writes. No tool deletes anything, and a card on the Apple Calendar can only be completed or archived inside Boto.",
            "What the assistant reads is sent to the company that runs its model. Do not connect it to boards you cannot share.",
        ]),
        ("Backups", [
            "Boto copies its database once a day into a Backups folder beside it, when it opens and every six hours after. The last 7 copies are kept.",
            "To restore: quit Boto, copy the backup you want over Boto.store, delete Boto.store-wal and Boto.store-shm if they exist, and open Boto again. Backups hold all your data, so keep that folder as private as the database itself.",
        ]),
        ("Find", [
            "Filter narrows the board by label, list and due date. A badge shows how many filters are active.",
            "Search (⌘K) looks through project names and card titles, descriptions and labels.",
        ]),
    ]

    private let shortcuts: [(keys: String, action: String)] = [
        ("⌘ K", "Search projects and cards"),
        ("⌘ N", "New project"),
        ("C", "Create a list in the current project"),
        ("⌃ ⌘ S", "Show or hide the sidebar"),
        ("G then B", "Go to projects (open the sidebar)"),
        ("/", "Show this help"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Help").font(Theme.font(17, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(22)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(topics, id: \.title) { topic in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(topic.title.uppercased()).font(Theme.font(10, weight: .semibold)).foregroundStyle(Theme.muted)
                            ForEach(topic.lines, id: \.self) { line in
                                Text(line).font(Theme.font(13)).fixedSize(horizontal: false, vertical: true)
                            }
                            if topic.title == "Backups" {
                                Button("Show backups in Finder") {
                                    if let folder = try? BotoPaths.backupsFolder() { NSWorkspace.shared.open(folder) }
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("KEYBOARD SHORTCUTS").font(Theme.font(10, weight: .semibold)).foregroundStyle(Theme.muted)
                        ForEach(shortcuts, id: \.keys) { shortcut in
                            HStack {
                                Text(shortcut.action).font(Theme.font(13))
                                Spacer()
                                Text(shortcut.keys)
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.card))
                            }
                        }
                        Text("Single-key shortcuts are ignored while you are typing.")
                            .font(Theme.font(11)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
        .frame(width: 520, height: 600)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}
