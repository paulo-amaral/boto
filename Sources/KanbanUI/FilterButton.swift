import KanbanCore
import SwiftUI

/// Groups mirror Kan's `Filters.tsx`: Labels, Lists, Due date, a count badge and "Clear filters".
struct FilterButton: View {
    @Binding var filter: CardFilter
    let labels: [KanbanCore.Label]
    let lists: [BoardList]
    var iconOnly = false
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease")
                if !iconOnly { Text("Filter") }
            }
        }
        .help("Filter")
        .buttonStyle(ToolbarButtonStyle(primary: false))
        .overlay(alignment: .topTrailing) {
            if filter.count > 0 {
                Text("\(filter.count)")
                    .font(Theme.font(9, weight: .bold))
                    .foregroundStyle(Theme.border)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Theme.text))
                    .offset(x: 8, y: -8)
            }
        }
        .popover(isPresented: $open, arrowEdge: .bottom) { content }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !labels.isEmpty {
                    group("Labels") {
                        ForEach(labels.sorted { $0.name < $1.name }) { label in
                            row(label.name, selected: filter.labelIds.contains(label.publicId), dot: label.colourCode ?? Theme.defaultLabel) {
                                filter.labelIds.formSymmetricDifference([label.publicId])
                            }
                        }
                    }
                }
                if !lists.isEmpty {
                    group("Lists") {
                        ForEach(lists) { list in
                            row(list.name, selected: filter.listIds.contains(list.publicId)) {
                                filter.listIds.formSymmetricDifference([list.publicId])
                            }
                        }
                    }
                }
                group("Due date") {
                    ForEach(DueDateFilter.allCases, id: \.self) { due in
                        row(due.title, selected: filter.dueDates.contains(due)) {
                            filter.dueDates.formSymmetricDifference([due])
                        }
                    }
                }
                if filter.count > 0 {
                    Button { filter.clear() } label: { Label("Clear filters", systemImage: "xmark") }
                        .buttonStyle(.plain)
                        .font(Theme.font(12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(14)
        }
        .frame(width: 240)
        .frame(maxHeight: 420)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(Theme.font(10, weight: .semibold)).foregroundStyle(Theme.muted)
            content()
        }
    }

    private func row(_ title: String, selected: Bool, dot: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? Theme.text : Theme.muted)
                if let dot { Circle().fill(Color(hex: dot)).frame(width: 8, height: 8) }
                Text(title).font(Theme.font(12))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
