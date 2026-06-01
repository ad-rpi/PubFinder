import Foundation

/// Drives the `brew` CLI: locates the binary, lists installed/outdated packages,
/// searches, fetches info, and runs install/uninstall/upgrade with live output.
@MainActor
final class HomebrewService: ObservableObject {
    @Published private(set) var installedFormulae: [BrewPackage] = []
    @Published private(set) var installedCasks: [BrewPackage] = []
    @Published private(set) var outdatedNames: Set<String> = []
    @Published private(set) var searchResults: [BrewPackage] = []

    /// The full installable catalog (every tapped formula/cask name), lazily
    /// loaded the first time the Browse pane is opened.
    @Published private(set) var catalogFormulae: [BrewPackage] = []
    @Published private(set) var catalogCasks: [BrewPackage] = []
    @Published private(set) var catalogLoaded = false

    @Published private(set) var brewPath: String?
    @Published private(set) var isBusy = false
    @Published var consoleOutput = ""
    @Published var errorMessage: String?

    init() { brewPath = Self.locateBrew() }

    var isAvailable: Bool { brewPath != nil }

    // MARK: - Discovery

    static func locateBrew() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/home/linuxbrew/.linuxbrew/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Reads

    func refreshAll() async {
        await refreshInstalled()
        await refreshOutdated()
    }

    func refreshInstalled() async {
        guard let brew = brewPath else { return }
        isBusy = true; defer { isBusy = false }

        let formulae = await Self.run(brew, ["list", "--formula", "--versions"]).output
        installedFormulae = parseVersioned(formulae, isCask: false)

        let casks = await Self.run(brew, ["list", "--cask", "--versions"]).output
        installedCasks = parseVersioned(casks, isCask: true)

        applyOutdatedFlags()
    }

    func refreshOutdated() async {
        guard let brew = brewPath else { return }
        let result = await Self.run(brew, ["outdated", "--quiet"]).output
        outdatedNames = Set(result.split(whereSeparator: \.isNewline).map { String($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty })
        applyOutdatedFlags()
    }

    /// Load the entire installable catalog via `brew formulae` / `brew casks`
    /// (local, fast — reads the tapped formula/cask names). Installed packages
    /// are flagged so the Browse pane can mark them.
    func loadCatalog(force: Bool = false) async {
        guard let brew = brewPath else { return }
        if catalogLoaded && !force { return }
        isBusy = true; defer { isBusy = false }

        let formulae = await Self.run(brew, ["formulae"]).output
        let casks = await Self.run(brew, ["casks"]).output
        catalogFormulae = parseCatalog(formulae, isCask: false)
        catalogCasks = parseCatalog(casks, isCask: true)
        catalogLoaded = true
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard let brew = brewPath, !trimmed.isEmpty else { searchResults = []; return }
        isBusy = true; defer { isBusy = false }

        let result = await Self.run(brew, ["search", trimmed]).output
        let installedNames = Set((installedFormulae + installedCasks).map(\.name))
        var packages: [BrewPackage] = []
        var isCaskSection = false
        for raw in result.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("==>") {
                isCaskSection = line.lowercased().contains("cask")
                continue
            }
            let name = line
            packages.append(BrewPackage(name: name, isCask: isCaskSection,
                                        installed: installedNames.contains(name),
                                        outdated: outdatedNames.contains(name)))
        }
        searchResults = packages
    }

    func info(for package: BrewPackage) async -> String {
        guard let brew = brewPath else { return "Homebrew not found." }
        let flag = package.isCask ? "--cask" : "--formula"
        return await Self.run(brew, ["info", flag, package.name]).output
    }

    // MARK: - Mutations

    func install(_ package: BrewPackage) async { await mutate("install", package) }
    func uninstall(_ package: BrewPackage) async { await mutate("uninstall", package) }
    func upgrade(_ package: BrewPackage) async { await mutate("upgrade", package) }

    /// Upgrade every outdated formula and cask in one pass (`brew upgrade`).
    func upgradeAll() async {
        guard let brew = brewPath else { return }
        isBusy = true; defer { isBusy = false }
        consoleOutput = "$ brew upgrade\n"

        let status = await Self.run(brew, ["upgrade"]) { [weak self] chunk in
            Task { @MainActor in self?.consoleOutput += chunk }
        }.status

        if status != 0 { errorMessage = "brew upgrade exited with code \(status)." }
        await refreshAll()
    }

    private func mutate(_ action: String, _ package: BrewPackage) async {
        guard let brew = brewPath else { return }
        isBusy = true; defer { isBusy = false }
        consoleOutput = "$ brew \(action) \(package.isCask ? "--cask " : "")\(package.name)\n"

        var args = [action]
        if package.isCask { args.append("--cask") }
        args.append(package.name)

        let status = await Self.run(brew, args) { [weak self] chunk in
            Task { @MainActor in self?.consoleOutput += chunk }
        }.status

        if status != 0 { errorMessage = "brew \(action) exited with code \(status)." }
        await refreshAll()
    }

    // MARK: - Parsing

    private func parseVersioned(_ text: String, isCask: Bool) -> [BrewPackage] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let parts = raw.split(separator: " ")
            guard let name = parts.first else { return nil }
            let version = parts.count > 1 ? parts[1...].joined(separator: " ") : ""
            return BrewPackage(name: String(name), version: version, isCask: isCask,
                               installed: true, outdated: outdatedNames.contains(String(name)))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Parse a bare newline-separated catalog name list, filling installed
    /// state (and version) from what we already know is installed.
    private func parseCatalog(_ text: String, isCask: Bool) -> [BrewPackage] {
        let versions = Dictionary((isCask ? installedCasks : installedFormulae).map { ($0.name, $0.version) },
                                  uniquingKeysWith: { a, _ in a })
        return text.split(whereSeparator: \.isNewline).compactMap { raw -> BrewPackage? in
            let name = raw.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let installed = versions[name] != nil
            return BrewPackage(name: name, version: installed ? (versions[name] ?? "") : "",
                               isCask: isCask, installed: installed,
                               outdated: outdatedNames.contains(name))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func applyOutdatedFlags() {
        func flag(_ list: inout [BrewPackage]) {
            for i in list.indices { list[i].outdated = outdatedNames.contains(list[i].name) }
        }
        flag(&installedFormulae)
        flag(&installedCasks)
        applyInstalledToCatalog()
    }

    /// Re-derive installed/outdated state on the cached catalog after a refresh
    /// or a mutation, so Browse rows update without a full catalog reload.
    private func applyInstalledToCatalog() {
        guard catalogLoaded else { return }
        let installedF = Set(installedFormulae.map(\.name))
        let installedC = Set(installedCasks.map(\.name))
        for i in catalogFormulae.indices {
            catalogFormulae[i].installed = installedF.contains(catalogFormulae[i].name)
            catalogFormulae[i].outdated = outdatedNames.contains(catalogFormulae[i].name)
        }
        for i in catalogCasks.indices {
            catalogCasks[i].installed = installedC.contains(catalogCasks[i].name)
            catalogCasks[i].outdated = outdatedNames.contains(catalogCasks[i].name)
        }
    }

    // MARK: - Process runner

    /// Runs an executable off the main thread, optionally streaming combined
    /// stdout/stderr in chunks, and returns the exit status plus full output.
    nonisolated static func run(_ executable: String, _ args: [String],
                                onChunk: (@Sendable (String) -> Void)? = nil) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.environment = enrichedEnvironment(for: executable)

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                let handle = pipe.fileHandleForReading

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: (-1, "Failed to launch \(executable): \(error.localizedDescription)"))
                    return
                }

                var collected = ""
                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    if let text = String(data: data, encoding: .utf8) {
                        collected += text
                        onChunk?(text)
                    }
                }
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, collected))
            }
        }
    }

    /// Ensure the brew bin dir is on PATH so brew's own subprocess calls resolve.
    private nonisolated static func enrichedEnvironment(for executable: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let brewBin = (executable as NSString).deletingLastPathComponent
        let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        if !existing.split(separator: ":").contains(Substring(brewBin)) {
            env["PATH"] = brewBin + ":" + existing
        }
        return env
    }
}
