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
    /// AppKit's `NSAttributedString.Key.link`, by its raw name: the core does not import AppKit.
    static let linkKey = NSAttributedString.Key("NSLink")

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

    /// A link whose address is hidden behind a title, as in an e-mail or a web page.
    public struct HiddenLink: Equatable {
        public let title: String
        public let url: URL
    }

    /// Plain text for text copied from somewhere else, where a link is often a title with the address hidden behind it.
    /// Each hidden address is written as `[title](address)`, which `segments(in:)` shows as a link; text that already is
    /// the address stays as it is. Plain text cannot hold a link any other way.
    public static func markdown(text: String, links: [HiddenLink]) -> String {
        var result = normalized(text)
        var cursor = result.startIndex
        for link in links {
            // The title is looked for as it came, then with its line breaks folded, since a page and its plain text
            // do not always break lines in the same places. It is written without brackets and breaks.
            let raw = normalized(link.title).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = clean(raw)
            guard !title.isEmpty,
                  let found = result.range(of: raw, range: cursor..<result.endIndex) ?? result.range(of: title, range: cursor..<result.endIndex)
            else { continue }
            let written = "[\(title)](\(link.url.absoluteString))"
            result.replaceSubrange(found, with: written)
            cursor = result.index(found.lowerBound, offsetBy: written.count)
        }
        return result
    }

    /// Rich text from the pasteboard (RTF, which Mail and Safari provide).
    public static func markdown(from attributed: NSAttributedString) -> String {
        markdown(text: attributed.string, links: hiddenLinks(in: attributed))
    }

    /// HTML from the pasteboard (what Chrome and web mail provide) next to its plain text. The HTML is only read for its
    /// links with a pattern, never rendered, so a message cannot make Boto load anything.
    public static func markdown(fromHTML html: String, plainText: String) -> String {
        markdown(text: plainText, links: hiddenLinks(inHTML: html))
    }

    public static func hiddenLinks(in attributed: NSAttributedString) -> [HiddenLink] {
        var links: [HiddenLink] = []
        attributed.enumerateAttribute(linkKey, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            let target = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
            if let target, let safe = safeURL(target.absoluteString) { links.append(appendable(attributed.attributedSubstring(from: range).string, safe)) }
        }
        return links.filter { !$0.title.isEmpty }
    }

    private static let anchor = try? NSRegularExpression(pattern: #"<a\b[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*>(.*?)</a>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let tag = try? NSRegularExpression(pattern: "<[^>]+>")

    public static func hiddenLinks(inHTML html: String) -> [HiddenLink] {
        let ns = html as NSString
        var links: [HiddenLink] = []
        for match in anchor?.matches(in: html, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let href = [1, 2].map { match.range(at: $0) }.first { $0.location != NSNotFound }.map { decode(ns.substring(with: $0)) } ?? ""
            let inner = ns.substring(with: match.range(at: 3))
            let title = decode(tag?.stringByReplacingMatches(in: inner, range: NSRange(location: 0, length: (inner as NSString).length), withTemplate: "") ?? inner)
            if let safe = safeURL(href.trimmingCharacters(in: .whitespacesAndNewlines)) { links.append(appendable(title, safe)) }
        }
        return links.filter { !$0.title.isEmpty }
    }

    /// A title that already is the address needs no brackets; the detector links it as it stands.
    private static func appendable(_ title: String, _ url: URL) -> HiddenLink {
        let shown = normalized(title).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = shown.lowercased()
        let isAddress = lower == url.absoluteString.lowercased() || lower.hasPrefix("http://") || lower.hasPrefix("https://")
            || lower.hasPrefix("www.") || (url.scheme == "mailto" && shown.contains("@"))
        return HiddenLink(title: isAddress ? "" : shown, url: url)
    }

    /// Brackets and line breaks in a title would end the Markdown link early.
    private static func clean(_ title: String) -> String {
        normalized(title).trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
    }

    /// Rich text comes with non-breaking spaces and trailing line breaks that plain text would keep.
    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .newlines)
    }

    private static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
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
