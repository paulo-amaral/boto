import Foundation

/// What Boto keeps from a message dragged out of Mail. Only `messageID` is needed to link back to it.
public struct ParsedEmail: Equatable {
    public var subject: String
    public var from: String?
    public var date: Date?
    /// Without the angle brackets.
    public var messageID: String?
    public var snippet: String

    public init(subject: String, from: String? = nil, date: Date? = nil, messageID: String? = nil, snippet: String = "") {
        self.subject = subject
        self.from = from
        self.date = date
        self.messageID = messageID
        self.snippet = snippet
    }

    /// Sender and date, then the start of the text: what goes in the description of a card made from this message.
    public var descriptionText: String {
        let header = [
            from.map { "From: \($0)" },
            date.map { "Date: \($0.formatted(date: .abbreviated, time: .shortened))" },
        ].compactMap { $0 }.joined(separator: "\n")
        return [header, snippet].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

/// Mail's deep link to a message: `message://%3C<message-id>%3E`. Mail itself writes the form without the slashes
/// (`message:%3C...%3E`) when a message is dragged out; both are read, and the slashed form is written because Cocoa
/// text views recognise it as a link. Mail can only open messages it has downloaded.
public enum MailMessageLink {
    private static let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    public static func messageID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "message" else { return nil }
        var rest = url.absoluteString.dropFirst("message:".count)
        if rest.hasPrefix("//") { rest = rest.dropFirst(2) }
        guard let decoded = String(rest).removingPercentEncoding else { return nil }
        let id = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "<> \n\t"))
        return id.isEmpty ? nil : id
    }

    public static func url(forMessageID id: String) -> URL? {
        let cleaned = id.trimmingCharacters(in: CharacterSet(charactersIn: "<> \n\t"))
        guard !cleaned.isEmpty, let encoded = "<\(cleaned)>".addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "message://\(encoded)")
    }
}

/// A small reader for the `.eml` Mail provides. It handles what real mail needs most: folded headers, RFC 2047 encoded
/// words in the subject and sender, multipart messages, base64 and quoted-printable bodies, and HTML-only mail.
public enum EmailParser {
    public static func parse(_ data: Data, snippetLimit: Int = 1500) -> ParsedEmail? {
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let (headers, body) = split(text)
        guard !headers.isEmpty else { return nil }
        let fields = parseHeaders(headers)
        let subject = fields["subject"].map(decodeWords) ?? ""
        let messageID = fields["message-id"].map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "<> \n\t")) }
        guard !subject.isEmpty || !(messageID ?? "").isEmpty else { return nil }
        return ParsedEmail(
            subject: subject.isEmpty ? "(no subject)" : subject,
            from: fields["from"].map(decodeWords),
            date: fields["date"].flatMap(parseDate),
            messageID: messageID?.isEmpty == true ? nil : messageID,
            snippet: snippet(of: plainText(headers: fields, body: body), limit: snippetLimit)
        )
    }

    // MARK: Headers

    private static func split(_ text: String) -> (headers: String, body: String) {
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard let range = normalised.range(of: "\n\n") else { return (normalised, "") }
        return (String(normalised[..<range.lowerBound]), String(normalised[range.upperBound...]))
    }

    /// Lowercased name to value. Folded lines are joined; the first occurrence of a name wins.
    private static func parseHeaders(_ block: String) -> [String: String] {
        var fields: [String: String] = [:]
        var name: String?
        var value = ""
        func flush() {
            if let name, fields[name] == nil { fields[name] = value.trimmingCharacters(in: .whitespaces) }
        }
        for line in block.components(separatedBy: "\n") {
            if line.first == " " || line.first == "\t" {
                value += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                flush()
                name = line[..<colon].lowercased()
                value = String(line[line.index(after: colon)...])
            }
        }
        flush()
        return fields
    }

    // MARK: RFC 2047

    static func decodeWords(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"=\?([^?\s]+)\?([bBqQ])\?([^?\s]*)\?="#) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        var result = ""
        var cursor = value.startIndex
        var previousWasWord = false
        for match in regex.matches(in: value, range: range) {
            guard let whole = Range(match.range, in: value), let charset = Range(match.range(at: 1), in: value),
                  let kind = Range(match.range(at: 2), in: value), let payload = Range(match.range(at: 3), in: value)
            else { continue }
            let between = String(value[cursor..<whole.lowerBound])
            // Whitespace between two encoded words is not part of the text.
            if !(previousWasWord && between.allSatisfy(\.isWhitespace)) { result += between }
            let bytes = value[kind].lowercased() == "b"
                ? Data(base64Encoded: String(value[payload]))
                : decodeQ(String(value[payload]))
            result += bytes.flatMap { string($0, charset: String(value[charset])) } ?? String(value[whole])
            cursor = whole.upperBound
            previousWasWord = true
        }
        return result + value[cursor...]
    }

    private static func decodeQ(_ text: String) -> Data? {
        var bytes: [UInt8] = []
        let chars = Array(text.utf8)
        var index = 0
        while index < chars.count {
            let c = chars[index]
            if c == UInt8(ascii: "_") { bytes.append(0x20); index += 1 }
            else if c == UInt8(ascii: "="), index + 2 < chars.count, let byte = hexByte(chars[index + 1], chars[index + 2]) {
                bytes.append(byte); index += 3
            } else { bytes.append(c); index += 1 }
        }
        return Data(bytes)
    }

    private static func hexByte(_ high: UInt8, _ low: UInt8) -> UInt8? {
        UInt8(String(decoding: [high, low], as: UTF8.self), radix: 16)
    }

    private static func string(_ data: Data, charset: String) -> String? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        let encoding = cfEncoding == kCFStringEncodingInvalidId
            ? String.Encoding.utf8
            : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        return String(data: data, encoding: encoding) ?? String(data: data, encoding: .utf8)
    }

    // MARK: Date

    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let cleaned = text.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression)
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) { return date }
        }
        return nil
    }

    // MARK: Body

    private static func parameter(_ name: String, in header: String) -> String? {
        let pattern = "\(name)\\s*=\\s*(?:\"([^\"]*)\"|([^;\\s]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header))
        else { return nil }
        for group in 1...2 {
            if let range = Range(match.range(at: group), in: header) { return String(header[range]) }
        }
        return nil
    }

    /// Plain text of a message part. Multipart: the first `text/plain` found, else the first `text/html` with tags removed.
    private static func plainText(headers: [String: String], body: String) -> String {
        let type = (headers["content-type"] ?? "text/plain").lowercased()
        if type.hasPrefix("multipart/"), let boundary = parameter("boundary", in: headers["content-type"] ?? "") {
            var html: String?
            for part in body.components(separatedBy: "--\(boundary)").dropFirst() {
                let (partHeaders, partBody) = split(part.hasPrefix("\n") ? String(part.dropFirst()) : part)
                let fields = parseHeaders(partHeaders)
                let partType = (fields["content-type"] ?? "text/plain").lowercased()
                if partType.hasPrefix("multipart/") || partType.hasPrefix("text/plain") {
                    let text = plainText(headers: fields, body: partBody)
                    if !text.isEmpty { return text }
                } else if partType.hasPrefix("text/html"), html == nil {
                    html = plainText(headers: fields, body: partBody)
                }
            }
            return html ?? ""
        }
        let decoded = decodeBody(body, headers: headers)
        return type.hasPrefix("text/html") ? stripTags(decoded) : decoded
    }

    private static func decodeBody(_ body: String, headers: [String: String]) -> String {
        let encoding = (headers["content-transfer-encoding"] ?? "7bit").lowercased()
        let charset = headers["content-type"].flatMap { parameter("charset", in: $0) } ?? "utf-8"
        switch encoding {
        case "base64":
            let compact = body.filter { !$0.isWhitespace }
            return Data(base64Encoded: compact).flatMap { string($0, charset: charset) } ?? ""
        case "quoted-printable":
            let joined = body.replacingOccurrences(of: "=\n", with: "")
            return decodeQ(joined.replacingOccurrences(of: "_", with: "=5F")).flatMap { string($0, charset: charset) } ?? joined
        default:
            return body
        }
    }

    private static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<(script|style).*?</\1>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)<br\s*/?>|</p>|</div>|</tr>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func snippet(of text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "..." : collapsed
    }
}
