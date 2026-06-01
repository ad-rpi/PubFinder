import Foundation

/// The category catalog as produced by `tools/generate_categories.py` and
/// shipped as `categories.json` (bundled default + hosted-on-GitHub copy).
struct CategoryCatalog: Codable {
    struct Entry: Codable {
        let category: String
        let source: String   // "debian" | "ubuntu" | "guess"
    }

    var schema: Int
    var generated: String
    var source: String
    var categories: [String: String]   // section key -> display name
    var formulae: [String: Entry]
    var casks: [String: Entry]

    static let empty = CategoryCatalog(schema: 0, generated: "", source: "",
                                       categories: [:], formulae: [:], casks: [:])
}

/// Resolved category for a single package, ready for display.
struct CategoryInfo: Hashable {
    let key: String
    let name: String
    let isGuess: Bool

    static let uncategorized = CategoryInfo(key: "zzz-uncategorized", name: "Uncategorized", isGuess: false)
}

/// A category section with its packages, for grouped list display.
struct CategoryGroup: Identifiable {
    let id: String      // category key
    let name: String
    let packages: [BrewPackage]
}

/// Loads package→category mappings. Ships a bundled `categories.json` as an
/// offline default and refreshes from a hosted copy on GitHub so categories
/// can change without an app release. Remote wins; on any failure we keep the
/// most recent good data (cached, else bundled).
@MainActor
final class CategoryService: ObservableObject {
    @Published private(set) var catalog: CategoryCatalog = .empty

    /// Hosted copy on GitHub so categories can refresh without an app release.
    /// A 404/offline just falls back to the cached or bundled copy.
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/ad-rpi/PubFinder/main/categories.json")

    private let etagKey = "CategoriesETag"
    private let cacheURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PubFinder", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("categories.json")
    }()

    init() {
        if let bundled = Self.decode(Self.bundledData()) { catalog = bundled }
        if let cached = Self.decode(try? Data(contentsOf: cacheURL)) { catalog = cached }
    }

    // MARK: - Lookup

    func info(for package: BrewPackage) -> CategoryInfo {
        let entry = package.isCask ? catalog.casks[package.name] : catalog.formulae[package.name]
        guard let entry else { return .uncategorized }
        let name = catalog.categories[entry.category] ?? entry.category.capitalized
        return CategoryInfo(key: entry.category, name: name, isGuess: entry.source == "guess")
    }

    /// Group packages into category sections, sorted by display name with
    /// "Uncategorized" pinned last.
    func grouped(_ packages: [BrewPackage]) -> [CategoryGroup] {
        var buckets: [String: (name: String, items: [BrewPackage])] = [:]
        for pkg in packages {
            let ci = info(for: pkg)
            buckets[ci.key, default: (ci.name, [])].items.append(pkg)
        }
        return buckets
            .map { CategoryGroup(id: $0.key, name: $0.value.name, packages: $0.value.items) }
            .sorted {
                if $0.id == CategoryInfo.uncategorized.key { return false }
                if $1.id == CategoryInfo.uncategorized.key { return true }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    // MARK: - Remote refresh (ETag-cached)

    func refreshFromRemote() async {
        guard let url = Self.remoteURL else { return }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        if let etag = UserDefaults.standard.string(forKey: etagKey) {
            req.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 304 { return }            // cached copy is current
            guard http.statusCode == 200, let decoded = Self.decode(data) else { return }
            catalog = decoded
            try? data.write(to: cacheURL)
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                UserDefaults.standard.set(etag, forKey: etagKey)
            }
        } catch {
            // Network/parse failure: keep whatever we already loaded.
        }
    }

    // MARK: - Helpers

    private static func bundledData() -> Data? {
        guard let url = Bundle.main.url(forResource: "categories", withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func decode(_ data: Data?) -> CategoryCatalog? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(CategoryCatalog.self, from: data)
    }
}
