import AppKit

class ConfigManager {
    static let configDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/screendivider")
    static let configFileURL = configDirectory.appendingPathComponent("config.json")

    private var fileWatchSource: DispatchSourceFileSystemObject?
    var onConfigReloaded: ((ScreenDividerConfig) -> Void)?

    func load() -> ScreenDividerConfig? {
        do {
            let data = try Data(contentsOf: Self.configFileURL)
            var config = try JSONDecoder().decode(ScreenDividerConfig.self, from: data)

            // Only keep screens that are currently connected
            let connectedNames = Set(NSScreen.screens.map { $0.localizedName })
            let before = config.screens.count
            config.screens.removeAll { !connectedNames.contains($0.screenName) }

            // Add any newly connected screens with a simple default layout
            for screen in NSScreen.screens {
                let name = screen.localizedName
                if !config.screens.contains(where: { $0.screenName == name }) {
                    let defaultRoot: SplitNode = .split(direction: .vertical, ratio: 0.5,
                        first: .zone(label: "1"), second: .zone(label: "2"))
                    config.screens.append(ScreenLayout(screenName: name, root: defaultRoot, grid: .defaultHalves))
                }
            }

            // Persist if we cleaned up stale or added new screens
            if config.screens.count != before {
                save(config)
            }

            return config
        } catch {
            NSLog("ScreenDivider: Failed to load config: \(error)")
            return nil
        }
    }

    func save(_ config: ScreenDividerConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: Self.configFileURL, options: .atomic)
    }

    func ensureConfigOnFirstLaunch() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.configDirectory.path) {
            try? fm.createDirectory(at: Self.configDirectory, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: Self.configFileURL.path) {
            let defaultRoot: SplitNode = .split(direction: .vertical, ratio: 0.5,
                first: .split(direction: .horizontal, ratio: 0.5,
                    first: .zone(label: "1"), second: .zone(label: "2")),
                second: .split(direction: .horizontal, ratio: 0.5,
                    first: .zone(label: "3"), second: .zone(label: "4")))

            // Create an entry for each connected screen
            let screens = NSScreen.screens.map { ScreenLayout(screenName: $0.localizedName, root: defaultRoot, grid: .defaultQuad) }
            let defaultConfig = ScreenDividerConfig(screens: screens.isEmpty
                ? [ScreenLayout(screenName: "Display", root: defaultRoot, grid: .defaultQuad)]
                : screens)
            save(defaultConfig)
        }
    }

    func startWatching() {
        stopWatching()
        let fd = open(Self.configFileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let config = self?.load() { self?.onConfigReloaded?(config) }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatchSource = source
    }

    func stopWatching() {
        fileWatchSource?.cancel()
        fileWatchSource = nil
    }
}
