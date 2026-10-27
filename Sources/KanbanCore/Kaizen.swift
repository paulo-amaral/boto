import Foundation
import SwiftData

/// Where a Kaizen experiment is in the Plan, Do, Check, Act cycle.
public enum ImprovementStatus: String, CaseIterable, Sendable {
    case running, adopted, adjusted, dropped

    public var title: String {
        switch self {
        case .running: "Running"
        case .adopted: "Adopted"
        case .adjusted: "Adjusted"
        case .dropped: "Dropped"
        }
    }

    public var isConcluded: Bool { self != .running }
}

/// One small experiment to improve how work flows: the problem seen (Plan), the change tried (Do), what was expected
/// and what happened (Check), and the decision (Act). Small, time-boxed and reviewed on a date.
@Model
public final class Improvement {
    @Attribute(.unique) public var publicId: String
    public var createdAt: Date
    public var deletedAt: Date?
    public var problem: String
    public var experiment: String
    public var expected: String
    public var reviewDate: Date
    public var result: String?
    public var concludedAt: Date?
    var statusRaw: String
    public var board: Board?

    public init(problem: String, experiment: String, expected: String, reviewDate: Date) {
        self.publicId = makePublicId()
        self.createdAt = Date()
        self.problem = problem
        self.experiment = experiment
        self.expected = expected
        self.reviewDate = reviewDate
        self.statusRaw = ImprovementStatus.running.rawValue
    }

    public var status: ImprovementStatus { ImprovementStatus(rawValue: statusRaw) ?? .running }

    public func isDueForReview(at now: Date = Date()) -> Bool { status == .running && reviewDate <= now }

    /// The Act step. Keeps what was learned even when the experiment is dropped.
    public func conclude(_ outcome: ImprovementStatus, result: String, at now: Date = Date()) {
        guard outcome.isConcluded, status == .running else { return }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        self.result = trimmed.isEmpty ? nil : trimmed
        statusRaw = outcome.rawValue
        concludedAt = now
    }
}

extension Board {
    /// Experiments should be short; a week is the default so the review lands in the next weekly look at the board.
    @discardableResult
    public func addImprovement(problem: String, experiment: String, expected: String,
                               reviewInDays days: Int = 7, from now: Date = Date()) -> Improvement? {
        let problem = problem.trimmingCharacters(in: .whitespacesAndNewlines)
        let experiment = experiment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !problem.isEmpty, !experiment.isEmpty else { return nil }
        let review = Calendar.current.date(byAdding: .day, value: max(1, days), to: now) ?? now
        let improvement = Improvement(problem: problem, experiment: experiment,
                                      expected: expected.trimmingCharacters(in: .whitespacesAndNewlines), reviewDate: review)
        improvements.append(improvement)
        return improvement
    }

    /// Newest first, deleted ones hidden.
    public var orderedImprovements: [Improvement] {
        improvements.filter { $0.deletedAt == nil }.sorted { $0.createdAt > $1.createdAt }
    }
}
