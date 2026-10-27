import AppKit
import XCTest
@testable import KanbanCore

final class ProjectIconTests: XCTestCase {
    private func project(_ name: String, secondsAgo: TimeInterval = 0) -> Project {
        let project = Project(name: name)
        project.createdAt = Date().addingTimeInterval(-secondsAgo)
        return project
    }

    func testEveryIconIsARealSFSymbol() {
        for name in ProjectIcons.all {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "\(name) is not an SF Symbol here")
        }
    }

    func testLucideIconsAreTellableFromSFSymbols() {
        XCTAssertEqual(ProjectIcons.lucideIcon("briefcase"), "lucide:briefcase")
        XCTAssertEqual(ProjectIcons.lucideName(in: "lucide:briefcase"), "briefcase")
        XCTAssertNil(ProjectIcons.lucideName(in: "briefcase"))
        XCTAssertNil(ProjectIcons.lucideName(in: ProjectIcons.default))
    }

    func testAssigningSkipsNothingWhenAProjectKeepsAPickedLucideIcon() {
        let picked = project("A", secondsAgo: 20)
        picked.iconName = ProjectIcons.lucideIcon("rocket")
        let other = project("B", secondsAgo: 10)
        ProjectIcons.assignMissing(to: [picked, other])
        XCTAssertEqual(picked.iconName, "lucide:rocket", "a picked icon is never replaced")
        XCTAssertEqual(other.iconName, ProjectIcons.all.first)
    }

    func testIconsAreUniqueAndIncludeTheDefault() {
        XCTAssertEqual(Set(ProjectIcons.all).count, ProjectIcons.all.count)
        XCTAssertTrue(ProjectIcons.all.contains(ProjectIcons.default))
    }

    func testProjectShowsTheDefaultUntilAnIconIsAssigned() {
        XCTAssertEqual(Project(name: "A").icon, ProjectIcons.default)
    }

    func testProjectsGetDifferentIconsInCreationOrder() {
        let a = project("A", secondsAgo: 30)
        let b = project("B", secondsAgo: 20)
        let c = project("C", secondsAgo: 10)
        ProjectIcons.assignMissing(to: [c, a, b])
        XCTAssertEqual([a.iconName, b.iconName, c.iconName], Array(ProjectIcons.all.prefix(3)))
    }

    func testExistingIconsNeverChange() {
        let old = project("Old", secondsAgo: 100)
        old.iconName = "globe"
        let new = project("New")
        ProjectIcons.assignMissing(to: [old, new])
        XCTAssertEqual(old.iconName, "globe")
        XCTAssertNotEqual(new.iconName, "globe", "a used icon is skipped while unused ones remain")
    }

    func testAssignmentIsIdempotent() {
        let a = project("A")
        ProjectIcons.assignMissing(to: [a])
        let first = a.iconName
        ProjectIcons.assignMissing(to: [a])
        XCTAssertEqual(a.iconName, first)
    }

    func testIconsCycleFairlyWhenThereAreMoreProjectsThanIcons() {
        let projects = (0..<(ProjectIcons.all.count + 2)).map { project("P\($0)", secondsAgo: Double(1000 - $0)) }
        ProjectIcons.assignMissing(to: projects)
        let counts = Dictionary(grouping: projects.compactMap(\.iconName), by: { $0 }).mapValues(\.count)
        XCTAssertTrue(counts.values.allSatisfy { $0 <= 2 })
        XCTAssertEqual(counts.values.filter { $0 == 2 }.count, 2)
    }
}
