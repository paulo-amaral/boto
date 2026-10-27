import XCTest
@testable import KanbanCore

private final class FakeTransport: HTTPTransport, @unchecked Sendable {
    var responses: [String: (Int, String, [String: String])] = [:]
    private(set) var requests: [URLRequest] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url!.path
        let key = request.url!.query.map { "\(path)?\($0)" } ?? path
        let (status, body, headers) = responses[key] ?? responses[path] ?? (404, "{}", [:])
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (Data(body.utf8), response)
    }
}

final class GitHubTests: XCTestCase {
    func testParsesWebAndShortForms() {
        XCTAssertEqual(GitHubLink.parse("https://github.com/acme/app/issues/12")?.slug, "acme/app#12")
        XCTAssertEqual(GitHubLink.parse("https://github.com/acme/app/issues/12")?.kind, .issue)
        XCTAssertEqual(GitHubLink.parse(" https://www.github.com/acme/app/pull/7#discussion ")?.kind, .pullRequest)
        XCTAssertEqual(GitHubLink.parse("acme/app#12")?.kind, .unknown)
        XCTAssertEqual(GitHubLink.parse("acme/my.repo-x#3")?.repo, "my.repo-x")
    }

    func testRejectsInvalidLinks() {
        XCTAssertNil(GitHubLink.parse("https://example.com/acme/app/issues/12"))
        XCTAssertNil(GitHubLink.parse("https://github.com/acme/app/issues/0"))
        XCTAssertNil(GitHubLink.parse("https://github.com/acme/app/issues/abc"))
        XCTAssertNil(GitHubLink.parse("../app#12"))
        XCTAssertNil(GitHubLink.parse("acme/../x#1"))
        XCTAssertNil(GitHubLink.parse("not a link"))
    }

    func testFetchesAnIssue() async throws {
        let transport = FakeTransport()
        transport.responses["/repos/acme/app/issues/12"] =
            (200, #"{"title":"Fix login","state":"open","html_url":"https://github.com/acme/app/issues/12"}"#, [:])
        let item = try await GitHubClient(token: nil, transport: transport).fetch(GitHubLink.parse("acme/app#12")!)
        XCTAssertEqual(item.kind, .issue)
        XCTAssertEqual(item.title, "Fix login")
        XCTAssertEqual(item.state, "open")
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testPullRequestStateComesFromPullsEndpoint() async throws {
        let transport = FakeTransport()
        let issue = #"{"title":"Add search","state":"closed","html_url":"https://github.com/acme/app/pull/7","pull_request":{}}"#
        transport.responses["/repos/acme/app/issues/7"] = (200, issue, [:])
        transport.responses["/repos/acme/app/pulls/7"] =
            (200, #"{"title":"Add search","state":"closed","html_url":"https://github.com/acme/app/pull/7","merged":true,"draft":false}"#, [:])
        let item = try await GitHubClient(token: nil, transport: transport).fetch(GitHubLink.parse("acme/app#7")!)
        XCTAssertEqual(item.kind, .pullRequest)
        XCTAssertEqual(item.state, "merged")

        transport.responses["/repos/acme/app/pulls/7"] =
            (200, #"{"title":"Add search","state":"open","html_url":"https://github.com/acme/app/pull/7","merged":false,"draft":true}"#, [:])
        let draft = try await GitHubClient(token: nil, transport: transport).fetch(GitHubLink.parse("acme/app#7")!)
        XCTAssertEqual(draft.state, "draft")
    }

    func testSendsTokenOnlyWhenPresent() async throws {
        let transport = FakeTransport()
        transport.responses["/repos/acme/app/issues/1"] =
            (200, #"{"title":"t","state":"open","html_url":"https://github.com/acme/app/issues/1"}"#, [:])
        let link = GitHubLink.parse("acme/app#1")!
        _ = try await GitHubClient(token: nil, transport: transport).fetch(link)
        _ = try await GitHubClient(token: "", transport: transport).fetch(link)
        _ = try await GitHubClient(token: "secret", transport: transport).fetch(link)
        XCTAssertNil(transport.requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(transport.requests[1].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(transport.requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(transport.requests[2].value(forHTTPHeaderField: "User-Agent"), "Boto")
    }

    func testMapsErrorStatuses() async {
        let link = GitHubLink.parse("acme/app#1")!
        let cases: [(Int, [String: String], GitHubError)] = [
            (401, [:], .unauthorized),
            (404, [:], .notFound),
            (403, ["x-ratelimit-remaining": "0"], .rateLimited),
            (403, [:], .forbidden),
            (429, [:], .rateLimited),
            (500, [:], .http(500)),
        ]
        for (status, headers, expected) in cases {
            let transport = FakeTransport()
            transport.responses["/repos/acme/app/issues/1"] = (status, "{}", headers)
            do {
                _ = try await GitHubClient(token: nil, transport: transport).fetch(link)
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? GitHubError, expected)
            }
        }
    }

    func testMalformedBodyIsInvalidResponse() async {
        let transport = FakeTransport()
        transport.responses["/repos/acme/app/issues/1"] = (200, "not json", [:])
        do {
            _ = try await GitHubClient(token: nil, transport: transport).fetch(GitHubLink.parse("acme/app#1")!)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? GitHubError, .invalidResponse)
        }
    }

    private func issueJSON(_ number: Int, state: String = "open", pull: Bool = false, labels: String = "[]") -> String {
        let marker = pull ? #","pull_request":{}"# : ""
        return #"{"number":\#(number),"title":"Issue \#(number)","body":"Body \#(number)","state":"\#(state)","html_url":"https://github.com/acme/app/issues/\#(number)","labels":\#(labels)\#(marker)}"#
    }

    private func listKey(state: String, page: Int) -> String {
        "/repos/acme/app/issues?state=\(state)&per_page=100&page=\(page)&sort=created&direction=asc"
    }

    func testIssuesPaginateAndSkipPullRequests() async throws {
        let transport = FakeTransport()
        let first = (1...100).map { issueJSON($0, pull: $0 % 10 == 0) }.joined(separator: ",")
        transport.responses[listKey(state: "all", page: 1)] = (200, "[\(first)]", [:])
        transport.responses[listKey(state: "all", page: 2)] = (200, "[\(issueJSON(101, state: "closed"))]", [:])

        let issues = try await GitHubClient(token: nil, transport: transport)
            .issues(owner: "acme", repo: "app", includeClosed: true)
        XCTAssertEqual(issues.count, 91)
        XCTAssertEqual(issues.last?.state, "closed")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testIssuesStopsAfterShortPageAndHonoursMaxPages() async throws {
        let transport = FakeTransport()
        transport.responses[listKey(state: "open", page: 1)] = (200, "[\(issueJSON(1))]", [:])
        let few = try await GitHubClient(token: nil, transport: transport).issues(owner: "acme", repo: "app", includeClosed: false)
        XCTAssertEqual(few.count, 1)
        XCTAssertEqual(transport.requests.count, 1)

        let full = (1...100).map { issueJSON($0) }.joined(separator: ",")
        for page in 1...3 { transport.responses[listKey(state: "open", page: page)] = (200, "[\(full)]", [:]) }
        let capped = try await GitHubClient(token: nil, transport: transport)
            .issues(owner: "acme", repo: "app", includeClosed: false, maxPages: 2)
        XCTAssertEqual(capped.count, 200)
    }

    func testIssuesRejectsUnsafeOwnerOrRepo() async {
        for (owner, repo) in [("..", "app"), ("acme", "a/b"), ("acme", "")] {
            do {
                _ = try await GitHubClient(token: nil, transport: FakeTransport()).issues(owner: owner, repo: repo, includeClosed: false)
                XCTFail("expected \(owner)/\(repo) to be rejected")
            } catch {
                XCTAssertEqual(error as? GitHubError, .notFound)
            }
        }
    }

    func testIssueLabelsAcceptStringsAndColoursWithOrWithoutHash() async throws {
        let transport = FakeTransport()
        let labels = ##"["plain",{"name":"bug","color":"d73a4a"},{"name":"ui","color":"#00ff00"},{"name":"none","color":null}]"##
        transport.responses[listKey(state: "open", page: 1)] = (200, "[\(issueJSON(1, labels: labels))]", [:])
        let issues = try await GitHubClient(token: nil, transport: transport).issues(owner: "acme", repo: "app", includeClosed: false)
        let board = GitHubImporter.board(repo: "acme/app", issues: issues)
        let cardLabels = board.lists[0].cards[0].labels
        XCTAssertEqual(cardLabels.map(\.name), ["plain", "bug", "ui", "none"])
        XCTAssertEqual(cardLabels.map(\.colour), [nil, "#d73a4a", "#00ff00", nil])
    }

    func testBoardSplitsOpenAndClosed() async throws {
        let transport = FakeTransport()
        transport.responses[listKey(state: "all", page: 1)] =
            (200, "[\(issueJSON(1)),\(issueJSON(2, state: "closed"))]", [:])
        let issues = try await GitHubClient(token: nil, transport: transport).issues(owner: "acme", repo: "app", includeClosed: true)
        let board = GitHubImporter.board(repo: "acme/app", issues: issues)
        XCTAssertEqual(board.lists.map(\.name), ["Open", "Closed"])
        XCTAssertEqual(board.lists[1].cards.first?.githubItem?.state, "closed")

        let openOnly = GitHubImporter.board(repo: "acme/app", issues: issues.filter { $0.state == "open" })
        XCTAssertEqual(openOnly.lists.map(\.name), ["Open"])
    }

    func testKeychainRoundTrip() throws {
        let store = KeychainSecretStore(service: "app.boto.kanban.tests.\(UUID().uuidString)", account: "token")
        defer { try? store.delete() }
        XCTAssertNil(try store.read())
        try store.save("one")
        try store.save("two")
        XCTAssertEqual(try store.read(), "two")
        try store.delete()
        XCTAssertNil(try store.read())
    }
}
