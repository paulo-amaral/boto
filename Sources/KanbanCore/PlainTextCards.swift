import Foundation

public enum PlainTextCards {
    /// Leading list markers: "- ", "* ", "• ", "+ ", "1. ", "1) ", "[ ]", "[x]", and combinations like "- [ ] ".
    private static let marker = #"^\s*(?:(?:[-*•+]|\d+[.)])\s+|\[[ xX]\]\s*)+"#

    public static func titles(in text: String) -> [String] {
        text.components(separatedBy: .newlines).compactMap { line in
            let title = line
                .replacingOccurrences(of: marker, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : title
        }
    }
}
