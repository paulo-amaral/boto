import Foundation

public struct GitHubLink: Equatable, Sendable {
    public enum Kind: Sendable { case issue, pullRequest, unknown }

    public let owner: String
    public let repo: String
    public let number: Int
    public let kind: Kind

    public var slug: String { "\(owner)/\(repo)#\(number)" }

    /// Accepts `https://github.com/owner/repo/issues/12`, `.../pull/12` and the short form `owner/repo#12`.
    public static func parse(_ text: String) -> GitHubLink? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = #"([A-Za-z0-9_.-]+)"#
        if let groups = match(#"^https?://(?:www\.)?github\.com/\#(name)/\#(name)/(issues|pull)/(\d+)(?:[/?#].*)?$"#, in: input),
           let link = make(groups[0], groups[1], groups[3], kind: groups[2] == "pull" ? .pullRequest : .issue) {
            return link
        }
        if let groups = match(#"^\#(name)/\#(name)#(\d+)$"#, in: input) {
            return make(groups[0], groups[1], groups[2], kind: .unknown)
        }
        return nil
    }

    private static func make(_ owner: String, _ repo: String, _ number: String, kind: Kind) -> GitHubLink? {
        guard let number = Int(number), number > 0 else { return nil }
        let link = GitHubLink(owner: owner, repo: repo, number: number, kind: kind)
        return link.isWellFormed ? link : nil
    }

    /// Letters, digits, "_", "." and "-" only, and never "." or "..": these would become path traversal in an API path.
    var isWellFormed: Bool {
        [owner, repo].allSatisfy { part in
            ![".", ".."].contains(part) && !part.isEmpty
                && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0)) }
        }
    }

    private static func match(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<result.numberOfRanges).compactMap { Range(result.range(at: $0), in: text).map { String(text[$0]) } }
    }
}

public struct GitHubIssue {
    public let number: Int
    public let title: String
    public let body: String
    public let state: String
    public let url: URL
    public let labels: [(name: String, color: String?)]
}

public enum GitHubImporter {
    /// Open issues go to "Open"; closed ones to "Closed", which is omitted when empty. Oldest first, like the repo.
    public static func board(repo: String, issues: [GitHubIssue]) -> ImportedBoard {
        func card(_ issue: GitHubIssue) -> ImportedBoard.Card {
            ImportedBoard.Card(
                title: issue.title,
                details: issue.body,
                labels: issue.labels.map { ImportedBoard.Label(name: $0.name, colour: hex($0.color)) },
                githubItem: GitHubItem(kind: .issue, title: issue.title, state: issue.state, url: issue.url)
            )
        }
        var lists = [ImportedBoard.List(name: "Open", cards: issues.filter { $0.state == "open" }.map(card))]
        let closed = issues.filter { $0.state != "open" }
        if !closed.isEmpty { lists.append(ImportedBoard.List(name: "Closed", cards: closed.map(card))) }
        return ImportedBoard(name: repo, lists: lists)
    }

    /// GitHub documents the colour only as a string; accept it with or without a leading "#".
    private static func hex(_ color: String?) -> String? {
        guard let color, !color.isEmpty else { return nil }
        return color.hasPrefix("#") ? color : "#\(color)"
    }
}

public struct GitHubItem: Equatable, Sendable {
    public enum Kind: Sendable { case issue, pullRequest }

    public let kind: Kind
    public let title: String
    /// "open", "closed", "merged" or "draft".
    public let state: String
    public let url: URL
}

public enum GitHubError: LocalizedError, Equatable {
    case unauthorized, notFound, rateLimited, forbidden, invalidResponse
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "GitHub rejected the token. Check it in GitHub settings."
        case .notFound: "Not found. The item may not exist, or the token cannot see that repository."
        case .rateLimited: "GitHub rate limit reached. Try again later."
        case .forbidden: "The token does not have permission to read this item."
        case .invalidResponse: "GitHub returned an unexpected response."
        case .http(let status): "GitHub returned status \(status)."
        }
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await self.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }
        return (data, http)
    }
}

/// Read-only. A token is optional: public items can be read without one, within GitHub's lower anonymous rate limit.
public struct GitHubClient: Sendable {
    private let token: String?
    private let transport: HTTPTransport

    public init(token: String?, transport: HTTPTransport = URLSession.shared) {
        self.token = token.flatMap { $0.isEmpty ? nil : $0 }
        self.transport = transport
    }

    private struct IssueDTO: Decodable {
        struct PullMarker: Decodable {}
        let title: String
        let state: String
        let html_url: URL
        let pull_request: PullMarker?
    }

    private struct PullDTO: Decodable {
        let title: String
        let state: String
        let html_url: URL
        let merged: Bool
        let draft: Bool?
    }

    public func fetch(_ link: GitHubLink) async throws -> GitHubItem {
        let base = "repos/\(link.owner)/\(link.repo)"
        let issue: IssueDTO = try await get("\(base)/issues/\(link.number)")
        guard issue.pull_request != nil else {
            return GitHubItem(kind: .issue, title: issue.title, state: issue.state, url: issue.html_url)
        }
        // The issues endpoint does not say whether a pull request was merged or is a draft.
        let pull: PullDTO = try await get("\(base)/pulls/\(link.number)")
        let state = pull.merged ? "merged" : (pull.draft == true ? "draft" : pull.state)
        return GitHubItem(kind: .pullRequest, title: pull.title, state: state, url: pull.html_url)
    }

    private struct IssueListDTO: Decodable {
        struct PullMarker: Decodable {}
        struct LabelDTO: Decodable {
            let name: String
            let color: String?

            private enum Keys: String, CodingKey { case name, color }

            // The docs allow a label to be a plain string or an object.
            init(from decoder: Decoder) throws {
                if let text = try? decoder.singleValueContainer().decode(String.self) {
                    name = text
                    color = nil
                } else {
                    let container = try decoder.container(keyedBy: Keys.self)
                    name = try container.decode(String.self, forKey: .name)
                    color = try container.decodeIfPresent(String.self, forKey: .color)
                }
            }
        }
        let number: Int
        let title: String
        let body: String?
        let state: String
        let html_url: URL
        let labels: [LabelDTO]
        let pull_request: PullMarker?
    }

    /// Issues of one repository, pull requests excluded. Pages are 100 issues; `maxPages` bounds the request count.
    public func issues(owner: String, repo: String, includeClosed: Bool, maxPages: Int = 10) async throws -> [GitHubIssue] {
        guard GitHubLink(owner: owner, repo: repo, number: 1, kind: .issue).isWellFormed else { throw GitHubError.notFound }
        var result: [GitHubIssue] = []
        for page in 1...max(maxPages, 1) {
            let state = includeClosed ? "all" : "open"
            let batch: [IssueListDTO] = try await get(
                "repos/\(owner)/\(repo)/issues?state=\(state)&per_page=100&page=\(page)&sort=created&direction=asc"
            )
            result += batch.filter { $0.pull_request == nil }.map {
                GitHubIssue(
                    number: $0.number, title: $0.title, body: $0.body ?? "", state: $0.state, url: $0.html_url,
                    labels: $0.labels.map { (name: $0.name, color: $0.color) }
                )
            }
            if batch.count < 100 { break }
        }
        return result
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: "https://api.github.com/\(path)") else { throw GitHubError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Boto", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200:
            do { return try JSONDecoder().decode(T.self, from: data) } catch { throw GitHubError.invalidResponse }
        case 401: throw GitHubError.unauthorized
        case 404: throw GitHubError.notFound
        case 403, 429:
            throw response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" || response.statusCode == 429
                ? GitHubError.rateLimited : GitHubError.forbidden
        default: throw GitHubError.http(response.statusCode)
        }
    }
}
