import AppKit
import KanbanCore
import SwiftUI

/// The Lucide icon set (ISC licence, see Resources/Lucide/LICENSE). Scripts/make-app.sh puts icons.json in the app's
/// Resources; a bare `swift run` has no such file, and project icons then fall back to the default symbol.
@MainActor
enum LucideIcons {
    struct Entry: Decodable {
        /// The SVG elements inside the 24x24 canvas.
        let s: String
        let t: [String]
    }

    private struct File: Decodable {
        let version: String
        let icons: [String: Entry]
    }

    /// Where the data lives. A test points this at the copy in the repository.
    static var dataURL: URL? = Bundle.main.resourceURL?.appendingPathComponent("Lucide/icons.json")

    private static var loaded: File?
    private static var images: [String: NSImage] = [:]

    private static var file: File? {
        if loaded == nil, let dataURL, let data = try? Data(contentsOf: dataURL) {
            loaded = try? JSONDecoder().decode(File.self, from: data)
        }
        return loaded
    }

    static var isAvailable: Bool { file != nil }
    static var version: String? { file?.version }
    static var names: [String] { file.map { $0.icons.keys.sorted() } ?? [] }

    /// Names that contain the text, or whose tags do ("work" finds briefcase). Empty text lists everything.
    static func search(_ text: String) -> [String] {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard let icons = file?.icons else { return [] }
        guard !query.isEmpty else { return names }
        return icons.filter { name, entry in name.contains(query) || entry.t.contains { $0.lowercased().contains(query) } }
            .keys.sorted()
    }

    /// Drawn in black with transparency, as a template image, so the view's foreground style colours it.
    static func image(_ name: String) -> NSImage? {
        if let cached = images[name] { return cached }
        guard let entry = file?.icons[name] else { return nil }
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#000" \
        stroke-width="2" stroke-linecap="round" stroke-linejoin="round">\(entry.s)</svg>
        """
        guard let image = NSImage(data: Data(svg.utf8)) else { return nil }
        image.isTemplate = true
        images[name] = image
        return image
    }
}

/// A project's icon: a Lucide icon when one was picked, otherwise the SF Symbol.
struct ProjectIconView: View {
    let icon: String
    var size: CGFloat = 14

    var body: some View {
        if let name = ProjectIcons.lucideName(in: icon), let image = LucideIcons.image(name) {
            Image(nsImage: image).renderingMode(.template).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            let symbol = ProjectIcons.lucideName(in: icon) == nil ? icon : ProjectIcons.default
            Image(systemName: symbol).font(.system(size: size))
        }
    }
}
