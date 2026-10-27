import Foundation

/// The type sizes the UI may use. Call sites ask for whatever size they like and get the nearest step, so a stray
/// 15 or 17 cannot make the text feel uneven. A tie rounds up.
public enum TypeScale {
    /// caption, small, body, body large, subheading, heading, title
    public static let steps: [CGFloat] = [11, 12, 13, 14, 16, 20, 26]

    public static func snap(_ size: CGFloat) -> CGFloat {
        steps.min { (abs($0 - size), -$0) < (abs($1 - size), -$1) } ?? size
    }
}
