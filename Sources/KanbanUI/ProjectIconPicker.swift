import KanbanCore
import SwiftData
import SwiftUI

/// Pick a project's icon from the Lucide set, with search by name or tag. "Automatic" hands the choice back to Boto.
struct ProjectIconPicker: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }) private var projects: [Project]
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 6)]

    var body: some View {
        let names = LucideIcons.search(query)
        VStack(spacing: 0) {
            HStack {
                Text("Icon for \(project.name)").font(Theme.font(16, weight: .semibold)).lineLimit(1)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(22)

            HStack {
                TextField("Search by name or topic, e.g. work, chart, home", text: $query).textFieldStyle(.roundedBorder)
                Button("Automatic") {
                    project.iconName = nil
                    ProjectIcons.assignMissing(to: projects)
                }
                .help("Let Boto pick an icon")
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 12)

            if !LucideIcons.isAvailable {
                message("The Lucide icons are bundled with the app build. Run Scripts/make-app.sh to use them.")
            } else if names.isEmpty {
                message("No icon matches \"\(query)\".")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if query.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("Suggested").font(Theme.font(13, weight: .semibold))
                            grid(LucideIcons.suggested)
                            Text("All icons").font(Theme.font(13, weight: .semibold))
                        }
                        grid(names)
                    }
                    .padding(.horizontal, 22)
                }
                Text("\(names.count) icons from Lucide (ISC licence)")
                    .font(Theme.font(11)).foregroundStyle(Theme.muted)
                    .padding(12)
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 420, idealHeight: 520)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private func grid(_ names: [String]) -> some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(names, id: \.self) { name in
                let icon = ProjectIcons.lucideIcon(name)
                Button { project.iconName = icon } label: {
                    ProjectIconView(icon: icon, size: 20)
                        .frame(width: 40, height: 40)
                        .background(project.icon == icon ? Theme.border : Theme.card,
                                    in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }
                .buttonStyle(.plain)
                .help(name)
                .accessibilityLabel(name)
                .accessibilityAddTraits(project.icon == icon ? .isSelected : [])
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text).font(Theme.font(12)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(22)
    }
}
