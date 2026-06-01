import Foundation

/// A Homebrew formula or cask, as surfaced in the browser.
struct BrewPackage: Identifiable, Hashable {
    var id: String { (isCask ? "cask:" : "formula:") + name }
    let name: String
    var version: String = ""
    var description: String = ""
    var isCask: Bool = false
    var installed: Bool = false
    var outdated: Bool = false

    var kindLabel: String { isCask ? "Cask" : "Formula" }
}
