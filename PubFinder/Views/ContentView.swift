import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var brew: HomebrewService
    @EnvironmentObject private var categories: CategoryService

    enum Category: Hashable {
        case formulae, casks, outdated, browse, search, taps
    }

    enum BrowseKind: String, CaseIterable, Identifiable {
        case all = "All", formulae = "Formulae", casks = "Casks"
        var id: String { rawValue }
    }

    @State private var category: Category = .formulae
    @State private var query = ""
    @State private var selection: BrewPackage?
    @State private var info = ""
    @State private var loadingInfo = false

    // Browse pane state
    @State private var browseFilter = ""
    @State private var browseKind: BrowseKind = .all
    @State private var hideInstalled = false

    // Selected category in the category column (sentinel == show everything).
    @State private var selectedCategoryKey: String = allCategoryKey
    static let allCategoryKey = "__all__"

    // Taps pane state
    @State private var newTap = ""

    var body: some View {
        Group {
            if brew.isAvailable {
                browser
            } else {
                HomebrewMissingView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .brewRefreshRequested)) { _ in
            Task { await brew.refreshAll() }
        }
        .task { await brew.refreshAll() }
    }

    private var browser: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            detailColumn
        }
        .onChange(of: category) { _, newValue in
            selectedCategoryKey = Self.allCategoryKey
            selection = nil
            if newValue == .browse { Task { await brew.loadCatalog() } }
            if newValue == .taps { Task { await brew.refreshTaps() } }
        }
        .onChange(of: selectedCategoryKey) { _, _ in selection = nil }
        .onChange(of: selection) { _, newValue in
            guard let newValue else { info = ""; return }
            Task { await loadInfo(newValue) }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        // List single-selection needs an optional binding.
        let categoryBinding = Binding<Category?>(
            get: { category },
            set: { if let new = $0 { category = new } }
        )
        return List(selection: categoryBinding) {
            Section("Installed") {
                Label("Formulae", systemImage: "shippingbox").tag(Category.formulae)
                Label("Casks", systemImage: "macwindow").tag(Category.casks)
                Label("Outdated", systemImage: "arrow.triangle.2.circlepath").tag(Category.outdated)
            }
            Section("Catalog") {
                Label("Browse", systemImage: "square.grid.2x2").tag(Category.browse)
                Label("Search", systemImage: "magnifyingglass").tag(Category.search)
                Label("Taps", systemImage: "spigot").tag(Category.taps)
            }
        }
        .navigationTitle("PubFinder")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await brew.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh (⌘R)")
                .disabled(brew.isBusy)
            }
        }
    }

    // MARK: - Content column (categories, or search results)

    @ViewBuilder
    private var contentColumn: some View {
        switch category {
        case .search: searchColumn
        case .taps:   tapsColumn
        default:      categoryColumn
        }
    }

    /// Selectable list of categories present in the current mode, each with a
    /// count, plus an "All" entry. Driving column for the drill-down.
    private var categoryColumn: some View {
        let items = currentItems
        let groups = categories.grouped(items)
        let keyBinding = Binding<String?>(
            get: { selectedCategoryKey },
            set: { if let v = $0 { selectedCategoryKey = v } }
        )
        return VStack(spacing: 0) {
            if category == .browse { browseBar }
            if category == .outdated { outdatedBar }

            if category == .browse && !brew.catalogLoaded {
                ContentUnavailableView {
                    Label("Loading Catalog…", systemImage: "square.grid.2x2")
                } description: {
                    Text("Reading every installable formula and cask.")
                }
            } else if items.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "shippingbox",
                                       description: Text(emptyHint))
            } else {
                List(selection: keyBinding) {
                    CategoryRow(name: "All", count: items.count, systemImage: "tray.full")
                        .tag(Optional(Self.allCategoryKey))
                    ForEach(groups) { group in
                        CategoryRow(name: group.name, count: group.packages.count, systemImage: "tag")
                            .tag(Optional(group.id))
                    }
                }
            }
        }
        .navigationTitle(title)
    }

    private var searchColumn: some View {
        VStack(spacing: 0) {
            searchBar
            if brew.searchResults.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "magnifyingglass",
                                       description: Text(emptyHint))
            } else {
                List(brew.searchResults, selection: $selection) { package in
                    PackageRow(package: package, categoryInfo: categories.info(for: package)).tag(package)
                }
            }
        }
        .navigationTitle("Search")
    }

    // MARK: - Detail column (packages of the selected category + info)

    @ViewBuilder
    private var detailColumn: some View {
        switch category {
        case .search: detail
        case .taps:   tapsDetail
        default:
            HSplitView {
                categoryPackageList
                    .frame(minWidth: 240, idealWidth: 300, maxHeight: .infinity)
                detail
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Taps

    private var tapsColumn: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("owner/name (e.g. homebrew/cask-fonts)", text: $newTap)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addCurrentTap)
                Button("Add", action: addCurrentTap)
                    .disabled(!isValidTap(newTap) || brew.isBusy)
            }
            .padding(8)
            Divider()

            if brew.taps.isEmpty {
                ContentUnavailableView("No Taps", systemImage: "spigot",
                                       description: Text("Add a tap above, e.g. ad-rpi/tap."))
            } else {
                List(brew.taps, id: \.self) { tap in
                    HStack {
                        Image(systemName: "spigot").foregroundStyle(.secondary)
                        Text(tap)
                        Spacer()
                        Button(role: .destructive) {
                            Task { await brew.removeTap(tap) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(brew.isBusy)
                        .help("Untap \(tap)")
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if brew.isBusy { ProgressView().controlSize(.small).padding(6) }
        }
        .navigationTitle("Taps")
    }

    @ViewBuilder
    private var tapsDetail: some View {
        if brew.consoleOutput.isEmpty {
            ContentUnavailableView {
                Label("Taps", systemImage: "spigot")
            } description: {
                Text("Add or remove Homebrew taps (extra formula/cask repositories). "
                     + "Packages from your taps show up in Browse and Search.")
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Console").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.top, 8)
                ScrollView {
                    Text(brew.consoleOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
        }
    }

    private func addCurrentTap() {
        let tap = newTap.trimmingCharacters(in: .whitespaces)
        guard isValidTap(tap) else { return }
        Task { await brew.addTap(tap); newTap = "" }
    }

    /// A valid tap is `owner/name` — exactly two non-empty slash-separated parts.
    private func isValidTap(_ s: String) -> Bool {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
    }

    private var categoryPackageList: some View {
        let items = selectedCategoryPackages
        return Group {
            if items.isEmpty {
                ContentUnavailableView("No Packages", systemImage: "shippingbox",
                                       description: Text("Pick a category on the left."))
            } else {
                List(items, selection: $selection) { package in
                    PackageRow(package: package, categoryInfo: categories.info(for: package)).tag(package)
                }
            }
        }
        .overlay(alignment: .top) {
            if brew.isBusy { ProgressView().controlSize(.small).padding(6) }
        }
        .navigationTitle(selectedCategoryTitle)
    }

    /// Packages belonging to the selected category (or everything for "All").
    private var selectedCategoryPackages: [BrewPackage] {
        let items = currentItems
        if selectedCategoryKey == Self.allCategoryKey { return items }
        return items.filter { categories.info(for: $0).key == selectedCategoryKey }
    }

    private var selectedCategoryTitle: String {
        if selectedCategoryKey == Self.allCategoryKey { return "All" }
        if selectedCategoryKey == CategoryInfo.uncategorized.key { return "Uncategorized" }
        return categories.catalog.categories[selectedCategoryKey] ?? selectedCategoryKey.capitalized
    }

    private var browseBar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter catalog…", text: $browseFilter)
                        .textFieldStyle(.plain)
                    if !browseFilter.isEmpty {
                        Button { browseFilter = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Picker("", selection: $browseKind) {
                        ForEach(BrowseKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Toggle("Hide installed", isOn: $hideInstalled)
                        .toggleStyle(.checkbox).font(.callout)
                }
            }
            .padding(8)
            Divider()
        }
    }

    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search Homebrew…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await brew.search(query) } }
                Button("Search") { Task { await brew.search(query) } }
                    .disabled(query.isEmpty)
            }
            .padding(8)
            Divider()
        }
    }

    @ViewBuilder
    private var outdatedBar: some View {
        let count = currentItems.count
        if count > 0 {
            VStack(spacing: 0) {
                HStack {
                    Text("^[\(count) update](inflect: true) available")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await brew.upgradeAll() }
                    } label: {
                        Label("Upgrade All", systemImage: "arrow.up.circle")
                    }
                    .disabled(brew.isBusy)
                }
                .padding(8)
                Divider()
            }
        }
    }

    private var currentItems: [BrewPackage] {
        switch category {
        case .formulae: return brew.installedFormulae
        case .casks:    return brew.installedCasks
        case .outdated: return (brew.installedFormulae + brew.installedCasks).filter(\.outdated)
        case .search:   return brew.searchResults
        case .browse:   return browseItems
        case .taps:     return []   // taps pane manages its own list
        }
    }

    private var browseItems: [BrewPackage] {
        var items: [BrewPackage]
        switch browseKind {
        case .all:      items = brew.catalogFormulae + brew.catalogCasks
        case .formulae: items = brew.catalogFormulae
        case .casks:    items = brew.catalogCasks
        }
        if hideInstalled { items = items.filter { !$0.installed } }
        let q = browseFilter.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { items = items.filter { $0.name.lowercased().contains(q) } }
        return items
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let package = selection {
            PackageDetailView(
                package: package,
                categoryInfo: categories.info(for: package),
                info: info,
                loadingInfo: loadingInfo,
                consoleOutput: brew.consoleOutput,
                isBusy: brew.isBusy,
                onInstall: { Task { await brew.install(package) } },
                onUninstall: { Task { await brew.uninstall(package) } },
                onUpgrade: { Task { await brew.upgrade(package) } }
            )
        } else {
            ContentUnavailableView("No Package Selected", systemImage: "cube.box",
                                   description: Text("Pick a formula or cask to see details."))
        }
    }

    private func loadInfo(_ package: BrewPackage) async {
        loadingInfo = true
        info = await brew.info(for: package)
        loadingInfo = false
    }

    // MARK: - Labels

    private var title: String {
        switch category {
        case .formulae: return "Formulae"
        case .casks:    return "Casks"
        case .outdated: return "Outdated"
        case .browse:   return "Browse Catalog"
        case .search:   return "Search"
        case .taps:     return "Taps"
        }
    }
    private var emptyTitle: String {
        switch category {
        case .search: return "Search Homebrew"
        case .browse: return "No Matches"
        default:      return "Nothing Here"
        }
    }
    private var emptyHint: String {
        switch category {
        case .search:   return "Type a name and press Search."
        case .outdated: return "Everything is up to date."
        case .browse:   return hideInstalled ? "Nothing installable matches your filter." : "No packages match your filter."
        default:        return "No packages installed in this category."
        }
    }
}

// MARK: - Rows & detail views

private struct CategoryRow: View {
    let name: String
    let count: Int
    let systemImage: String

    var body: some View {
        HStack {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 18)
            Text(name)
            Spacer()
            Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

private struct PackageRow: View {
    let package: BrewPackage
    let categoryInfo: CategoryInfo

    var body: some View {
        HStack {
            Image(systemName: package.isCask ? "macwindow" : "shippingbox")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(package.name)
                if !package.version.isEmpty {
                    Text(package.version).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if categoryInfo.isGuess {
                Image(systemName: "sparkles")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .help("Category inferred from description")
            }
            if package.outdated {
                Image(systemName: "arrow.up.circle.fill").foregroundStyle(.orange)
                    .help("Update available")
            } else if package.installed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .help("Installed")
            }
        }
    }
}

private struct PackageDetailView: View {
    let package: BrewPackage
    let categoryInfo: CategoryInfo
    let info: String
    let loadingInfo: Bool
    let consoleOutput: String
    let isBusy: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(package.name).font(.title2).fontWeight(.semibold).textSelection(.enabled)
                    Text(package.kindLabel + (package.version.isEmpty ? "" : " · \(package.version)"))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "tag").font(.caption2)
                        Text(categoryInfo.name)
                        if categoryInfo.isGuess {
                            Text("· inferred").foregroundStyle(.tertiary)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                actions
            }
            .padding(12)
            Divider()

            ScrollView {
                if loadingInfo {
                    ProgressView().padding()
                } else {
                    Text(info.isEmpty ? "No info available." : info)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }

            if !consoleOutput.isEmpty {
                Divider()
                Text("Console").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 6)
                ScrollView {
                    Text(consoleOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(height: 160)
                .background(.black.opacity(0.04))
            }
        }
    }

    private var actions: some View {
        HStack {
            if package.outdated {
                Button("Upgrade", action: onUpgrade).disabled(isBusy)
            }
            if package.installed {
                Button("Uninstall", role: .destructive, action: onUninstall).disabled(isBusy)
            } else {
                Button("Install", action: onInstall).buttonStyle(.borderedProminent).disabled(isBusy)
            }
        }
    }
}

private struct HomebrewMissingView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48)).foregroundStyle(.orange)
            Text("Homebrew Not Found").font(.title2).fontWeight(.semibold)
            Text("PubFinder couldn't find the `brew` binary in the usual locations\n(/opt/homebrew/bin or /usr/local/bin).")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Link("Install Homebrew", destination: URL(string: "https://brew.sh")!)
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
