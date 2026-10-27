import AppKit
import KanbanCore
import UniformTypeIdentifiers

/// Reads messages dragged out of Apple Mail. On a real drag from macOS 27, Mail offers two items per message:
/// item 0 has the `message:` link (public.url), the subject (public.url-name) and the subject again as plain text;
/// item 1 is a file promise for the .eml. The link is enough to make a card and a "From email" reference, so it is read
/// first and fast; the .eml, which Mail has to export, is read afterwards with a time limit and only adds detail.
enum EmailDrop {
    struct Failure: LocalizedError {
        let offered: [String]

        var errorDescription: String? {
            "Boto could not read that as a message from Mail. Offered: \(offered.isEmpty ? "nothing" : offered.joined(separator: ", "))."
        }
    }

    private static let subjectType = "public.url-name"

    private static func isEmailType(_ identifier: String) -> Bool {
        identifier == "com.apple.mail.email" || identifier == "com.apple.mail.emlx"
            || UTType(identifier)?.conforms(to: .emailMessage) == true
    }

    /// Plain web links and Mail messages both carry public.url; the link reader tells them apart by its scheme.
    static func looksLikeMail(_ providers: [NSItemProvider]) -> Bool {
        providers.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                || $0.hasItemConformingToTypeIdentifier("com.apple.mail.PasteboardTypeMessageTransfer")
                || $0.registeredTypeIdentifiers.contains(where: isEmailType)
        }
    }

    static func offeredTypes(_ providers: [NSItemProvider]) -> [String] {
        Array(Set(providers.flatMap(\.registeredTypeIdentifiers))).sorted()
    }

    /// Phase 1: the link and the subject. Fast, and enough to create the card.
    @MainActor
    static func readLinks(from providers: [NSItemProvider]) async -> [ParsedEmail] {
        var found: [ParsedEmail] = []
        for provider in providers {
            guard let id = await linkID(of: provider) else { continue }
            var subject: String?
            if provider.hasItemConformingToTypeIdentifier(subjectType), let data = await loadData(provider, subjectType) {
                subject = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            found.append(ParsedEmail(subject: (subject?.isEmpty == false ? subject : nil) ?? "(no subject)", messageID: id))
        }
        return merge(found)
    }

    /// The link and subject straight from the drag pasteboard. On a real drop on macOS 27, SwiftUI hands over only the
    /// file promise (type com.apple.mail.email) and leaves out the link item, but the drag pasteboard still holds both,
    /// and reading them is instant. Callers must only use this for a drop that looks like Mail, or it could read
    /// a stale drag.
    static func readPasteboard(_ pasteboard: NSPasteboard) -> [ParsedEmail] {
        var found: [ParsedEmail] = []
        for item in pasteboard.pasteboardItems ?? [] {
            guard let text = item.string(forType: .URL), let url = URL(string: text),
                  let id = MailMessageLink.messageID(from: url)
            else { continue }
            let subject = item.string(forType: NSPasteboard.PasteboardType(subjectType))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            found.append(ParsedEmail(subject: (subject?.isEmpty == false ? subject : nil) ?? "(no subject)", messageID: id))
        }
        return merge(found)
    }

    /// Phase 2: the .eml, for sender, date and text. Mail exports it on demand, so it can be slow (seen: 6 to 11 s) or
    /// never arrive. Every item is requested at once, so the waits do not add up.
    @MainActor
    static func readFiles(from providers: [NSItemProvider], timeout: TimeInterval = 20) async -> [ParsedEmail] {
        let found = await withTaskGroup(of: ParsedEmail?.self) { group in
            for provider in providers {
                group.addTask { @MainActor in await readFile(provider, timeout: timeout) }
            }
            var results: [ParsedEmail] = []
            for await email in group { if let email { results.append(email) } }
            return results
        }
        return merge(found)
    }

    @MainActor
    private static func readFile(_ provider: NSItemProvider, timeout: TimeInterval) async -> ParsedEmail? {
        guard let type = provider.registeredTypeIdentifiers.first(where: isEmailType),
              let data = await loadFile(provider, type, timeout: timeout),
              var parsed = EmailParser.parse(data)
        else { return nil }
        if parsed.messageID == nil { parsed.messageID = await linkID(of: provider) }
        return parsed
    }

    /// Mail sends every message as two items (the link and subject, and a promise of the .eml). Both carry the same
    /// Message-ID, so they are one message; fields missing from one are filled from the other.
    static func merge(_ emails: [ParsedEmail]) -> [ParsedEmail] {
        var order: [String] = []
        var byKey: [String: ParsedEmail] = [:]
        for (index, email) in emails.enumerated() {
            let key = email.messageID ?? "no-id-\(index)"
            if let existing = byKey[key] {
                byKey[key] = ParsedEmail(
                    subject: [existing.subject, email.subject].first { $0 != "(no subject)" && !$0.isEmpty } ?? existing.subject,
                    from: existing.from ?? email.from,
                    date: existing.date ?? email.date,
                    messageID: existing.messageID ?? email.messageID,
                    snippet: existing.snippet.isEmpty ? email.snippet : existing.snippet
                )
            } else {
                byKey[key] = email
                order.append(key)
            }
        }
        return order.compactMap { byKey[$0] }
    }

    private static func linkID(of provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), let url = await loadURL(provider) else { return nil }
        return MailMessageLink.messageID(from: url)
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                switch item {
                case let url as URL: continuation.resume(returning: url)
                case let data as Data: continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                case let text as String: continuation.resume(returning: URL(string: text))
                default: continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadData(_ provider: NSItemProvider, _ type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in continuation.resume(returning: data) }
        }
    }

    /// Resumes exactly once: with the file, or with nil when the time limit passes first.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func run(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            body()
        }
    }

    /// The file is only valid inside the callback, so it is read there.
    private static func loadFile(_ provider: NSItemProvider, _ type: String, timeout: TimeInterval) async -> Data? {
        await withCheckedContinuation { continuation in
            let once = Once()
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                let data = url.flatMap { try? Data(contentsOf: $0) }
                once.run { continuation.resume(returning: data) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                once.run { continuation.resume(returning: nil) }
            }
        }
    }
}
