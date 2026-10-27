import Foundation

/// SF Symbol names a project can use as its icon. A test checks that every name exists on this macOS.
public enum ProjectIcons {
    public static let `default` = "rectangle.split.3x1"

    /// An icon the person picked from the bundled Lucide set is stored as "lucide:<name>". Anything else is an SF Symbol.
    public static let lucidePrefix = "lucide:"
    public static func lucideIcon(_ name: String) -> String { lucidePrefix + name }
    public static func lucideName(in icon: String) -> String? {
        icon.hasPrefix(lucidePrefix) ? String(icon.dropFirst(lucidePrefix.count)) : nil
    }

    public static let all: [String] = [
        "rectangle.split.3x1", "folder", "briefcase", "building.2", "person.2", "globe",
        "doc.text", "chart.bar", "chart.pie", "calendar", "tray.full", "paperplane",
        "hammer", "wrench.and.screwdriver", "gearshape", "lightbulb", "bolt", "flame",
        "star", "heart", "flag", "bookmark", "leaf", "cart",
        "graduationcap", "stethoscope", "airplane", "banknote", "shield", "lock",
    ]

    /// Icons are not user-editable. Each project without one gets the least-used icon, earliest in `all` on ties,
    /// in creation order, so a handful of projects all look different and an old project never changes its icon.
    public static func assignMissing(to projects: [Project]) {
        var uses: [String: Int] = [:]
        for project in projects {
            if let name = project.iconName { uses[name, default: 0] += 1 }
        }
        for project in projects.filter({ $0.iconName == nil }).sorted(by: { $0.createdAt < $1.createdAt }) {
            let pick = all.enumerated()
                .min { (uses[$0.element, default: 0], $0.offset) < (uses[$1.element, default: 0], $1.offset) }?
                .element ?? `default`
            project.iconName = pick
            uses[pick, default: 0] += 1
        }
    }
}
