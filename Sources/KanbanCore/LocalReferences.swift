import Foundation

public struct ObsidianVault: Equatable, Sendable {
    public let root: URL
    public var name: String { root.lastPathComponent }
}

public enum LocalReferences {
    /// Walks up from `url` looking for a folder that contains `.obsidian`.
    public static func vault(containing url: URL) -> ObsidianVault? {
        let fm = FileManager.default
        var directory = url.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        if !(fm.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue) {
            directory = directory.deletingLastPathComponent()
        }
        while directory.path != "/" {
            if fm.fileExists(atPath: directory.appendingPathComponent(".obsidian").path) {
                return ObsidianVault(root: directory)
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }

    static func relativePath(of url: URL, under root: URL) -> String? {
        let base = root.resolvingSymlinksInPath().path + "/"
        let path = url.resolvingSymlinksInPath().path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : nil
    }
}

extension Reference {
    /// Builds a pointer to `url`. Notes inside an Obsidian vault are stored relative to the vault;
    /// everything else relative to the project root when it lives under it.
    public static func make(url: URL, projectRoot: URL?) -> Reference {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let vault = LocalReferences.vault(containing: url)
        let isNote = !isDirectory.boolValue && url.pathExtension.lowercased() == "md" && vault != nil
        let base = isNote ? vault?.root : projectRoot
        return Reference(
            kind: isNote ? .obsidianNote : (isDirectory.boolValue ? .folder : .file),
            displayPath: url.path,
            relativePath: base.flatMap { LocalReferences.relativePath(of: url, under: $0) },
            vaultName: isNote ? vault?.name : nil,
            vaultRootPath: isNote ? vault?.root.path : nil,
            bookmarkData: try? url.bookmarkData()
        )
    }

    public static func make(item: GitHubItem) -> Reference {
        Reference(
            kind: item.kind == .pullRequest ? .githubPullRequest : .githubIssue,
            displayPath: item.url.absoluteString,
            remoteTitle: item.title,
            remoteState: item.state
        )
    }

    /// "From email": the subject is the title, the sender is the state line, and the address is Mail's `message://` link.
    /// Nil when the message has no Message-ID, because without it there is nothing to link back to.
    public static func make(email: ParsedEmail) -> Reference? {
        guard let id = email.messageID, let url = MailMessageLink.url(forMessageID: id) else { return nil }
        return Reference(kind: .email, displayPath: url.absoluteString, remoteTitle: email.subject, remoteState: email.from)
    }

    public func apply(_ item: GitHubItem) {
        remoteTitle = item.title
        remoteState = item.state
    }

    /// Resolution order: bookmark (survives moves and renames), then root + relative path
    /// (survives moving the whole project folder), then the absolute path. Nil means broken.
    public func resolvedURL(projectRoot: URL?) -> URL? {
        if kind.isRemote { return URL(string: displayPath) }
        let fm = FileManager.default
        if let bookmarkData {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale),
               fm.fileExists(atPath: url.path) {
                return url
            }
        }
        if let relativePath {
            let base = kind == .obsidianNote ? vaultRootPath.map { URL(fileURLWithPath: $0) } : projectRoot
            if let url = base?.appendingPathComponent(relativePath), fm.fileExists(atPath: url.path) {
                return url
            }
        }
        let url = URL(fileURLWithPath: displayPath)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    /// `obsidian://open?vault=...&file=...`. The slash encoding follows my reading of the Obsidian URI docs
    /// and still needs a manual check against a real vault.
    public var obsidianURL: URL? {
        guard kind == .obsidianNote, let vaultName, let relativePath else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let vault = vaultName.addingPercentEncoding(withAllowedCharacters: allowed),
              let file = relativePath.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "obsidian://open?vault=\(vault)&file=\(file)")
    }
}
