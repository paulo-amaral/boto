import Foundation

/// Finds the links in a card description so they can be clicked. It reads two things: Markdown links, `[title](url)`,
/// shown as their title, and addresses written in the text, shown as typed. Only web and mail links are ever made:
/// `file:`, `javascript:` and other schemes stay plain text, because a description can be pasted from anywhere.
public enum LinkedText {
    public struct Segment: Equatable {
        public let text: String
        public let url: URL?
    }

    private static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    private static let markdownLink = try? NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(((?:https?://|mailto:)[^\s)]+)\)"#)
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// The text cut into pieces in order; joined, the plain pieces and the link texts give what is shown.
    public static func segments(in text: String) -> [Segment] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        var segments: [Segment] = []
        var cursor = 0
        for match in markdownLink?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? [] {
            guard let url = safeURL(ns.substring(with: match.range(at: 2))) else { continue }
            segments += detect(in: ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            segments.append(Segment(text: ns.substring(with: match.range(at: 1)), url: url))
            cursor = match.range.location + match.range.length
        }
        segments += detect(in: ns.substring(from: cursor))
        return segments
    }

    public static func hasLinks(_ text: String) -> Bool { segments(in: text).contains { $0.url != nil } }

    private static func detect(in text: String) -> [Segment] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        var segments: [Segment] = []
        var cursor = 0
        for match in detector?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? [] {
            var shown = ns.substring(with: match.range)
            var address = match.url?.absoluteString ?? ""
            // A "?" or "!" that ends a sentence is not part of the address.
            while let last = shown.last, "?!,;:".contains(last), address.last == last { shown.removeLast(); address.removeLast() }
            guard let safe = safeURL(address), isWrittenAsALink(shown, url: safe) else { continue }
            if match.range.location > cursor { segments.append(Segment(text: ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), url: nil)) }
            segments.append(Segment(text: shown, url: safe))
            cursor = match.range.location + (shown as NSString).length
        }
        if cursor < ns.length { segments.append(Segment(text: ns.substring(from: cursor), url: nil)) }
        return segments
    }

    /// The system detector also reads file names as web addresses (`README.md`, `main.py`: .md and .py are country
    /// domains). A bare name counts only with `www.` or a path after it; `https://` and mail addresses always count.
    private static func isWrittenAsALink(_ shown: String, url: URL) -> Bool {
        let lower = shown.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return true }
        if url.scheme == "mailto" { return shown.contains("@") }
        if lower.hasPrefix("www.") { return true }
        return shown.contains("/") && !shown.hasPrefix("/")
    }

    private static func safeURL(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else { return nil }
        return url
    }
}
