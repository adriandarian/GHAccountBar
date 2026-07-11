import AppKit
import Foundation
import GHAccountBarCore

@main
struct GHAccountBar {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = AppRuntime.delegate
        app.run()
    }
}

private enum AppRuntime {
    @MainActor static let delegate = AppDelegate()
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let client = GHClient()
    private let colorStore = GHAccountColorStore()
    private var accounts: [GHAccount] = []
    private var colorPanelSelection: AccountSelection?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        refreshAccounts(showLoading: true)
        startAutomaticRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        statusItem.length = NSStatusItem.squareLength
        button.image = GHMenuBarIcon.image()
        button.imagePosition = .imageOnly
        button.title = GHStatusBarDisplay.title(for: [])
        button.toolTip = "GitHub account switcher"
    }

    private func startAutomaticRefresh() {
        let timer = Timer(timeInterval: GHRefreshPolicy.accountPollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccounts(showLoading: false)
            }
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: GHRefreshPolicy.accountPollingRunLoopMode)
    }

    private func refreshAccounts(showLoading: Bool) {
        if showLoading {
            setLoadingMenu()
        }

        refreshTask?.cancel()
        refreshTask = Task {
            do {
                let accounts = try await client.accounts()
                guard !Task.isCancelled else {
                    return
                }
                renderMenu(accounts: accounts)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                renderErrorMenu(error)
            }
        }
    }

    private func setLoadingMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let loadingItem = NSMenuItem(title: "Loading GitHub accounts...", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        menu.addItem(loadingItem)
        statusItem.menu = menu
    }

    private func renderMenu(accounts: [GHAccount]) {
        self.accounts = accounts
        let menu = NSMenu()
        menu.delegate = self
        let showsHost = Set(accounts.map(\.host)).count > 1

        if accounts.isEmpty {
            let emptyItem = NSMenuItem(title: "No authenticated gh users", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for account in accounts {
                let title = showsHost ? "\(account.login) (\(account.host))" : account.login
                let item = NSMenuItem(title: title, action: #selector(selectAccount(_:)), keyEquivalent: "")
                item.target = self
                item.state = account.active ? .on : .off
                item.isEnabled = !account.active
                item.image = GHColorSwatch.image(color: colorStore.color(for: account))
                item.representedObject = AccountSelection(account: account)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        if let activeAccount = accounts.first(where: \.active) {
            let activeSelection = AccountSelection(account: activeAccount)
            let colorItem = NSMenuItem(
                title: "Set Color for \(displayName(for: activeAccount, showsHost: showsHost))...",
                action: #selector(chooseAccountColor(_:)),
                keyEquivalent: ""
            )
            colorItem.target = self
            colorItem.image = GHColorSwatch.image(color: colorStore.color(for: activeAccount))
            colorItem.representedObject = activeSelection
            menu.addItem(colorItem)

            let resetColorItem = NSMenuItem(
                title: "Reset Color for \(displayName(for: activeAccount, showsHost: showsHost))",
                action: #selector(resetAccountColor(_:)),
                keyEquivalent: ""
            )
            resetColorItem.target = self
            resetColorItem.representedObject = activeSelection
            resetColorItem.isEnabled = colorStore.hasCustomColor(for: activeAccount)
            menu.addItem(resetColorItem)

            menu.addItem(.separator())
        }

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshMenu(_:)), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit GH Account Bar", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        updateButtonTitle(accounts: accounts)
        statusItem.menu = menu
    }

    private func renderErrorMenu(_ error: Error) {
        let menu = NSMenu()
        menu.delegate = self

        let errorItem = NSMenuItem(title: "Unable to load gh users", action: nil, keyEquivalent: "")
        errorItem.isEnabled = false
        menu.addItem(errorItem)

        let detailItem = NSMenuItem(title: String(describing: error), action: nil, keyEquivalent: "")
        detailItem.isEnabled = false
        menu.addItem(detailItem)

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Retry", action: #selector(refreshMenu(_:)), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "Quit GH Account Bar", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.button?.title = GHStatusBarDisplay.errorTitle()
        statusItem.button?.toolTip = GHStatusBarDisplay.errorTooltip()
        statusItem.button?.image = GHMenuBarIcon.image()
        statusItem.button?.contentTintColor = nil
        statusItem.menu = menu
    }

    private func updateButtonTitle(accounts: [GHAccount]) {
        statusItem.button?.title = GHStatusBarDisplay.title(for: accounts)
        statusItem.button?.toolTip = GHStatusBarDisplay.tooltip(for: accounts)
        updateButtonIcon(accounts: accounts)
    }

    private func updateButtonIcon(accounts: [GHAccount]) {
        guard let activeAccount = accounts.first(where: \.active) else {
            statusItem.button?.image = GHMenuBarIcon.image()
            statusItem.button?.contentTintColor = nil
            return
        }

        statusItem.button?.image = GHMenuBarIcon.image(tintColor: colorStore.color(for: activeAccount))
        statusItem.button?.contentTintColor = nil
    }

    private func displayName(for account: GHAccount, showsHost: Bool) -> String {
        showsHost ? "\(account.login) (\(account.host))" : account.login
    }

    @objc private func selectAccount(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? AccountSelection else {
            return
        }

        setLoadingMenu()

        Task {
            do {
                try await client.switchAccount(host: selection.host, login: selection.login)
                refreshAccounts(showLoading: true)
            } catch {
                renderErrorMenu(error)
            }
        }
    }

    @objc private func chooseAccountColor(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? AccountSelection else {
            return
        }

        colorPanelSelection = selection
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.mode = .wheel
        panel.color = colorStore.color(for: selection)
        NotificationCenter.default.removeObserver(
            self,
            name: NSColorPanel.colorDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accountColorChanged(_:)),
            name: NSColorPanel.colorDidChangeNotification,
            object: panel
        )
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func accountColorChanged(_ notification: Notification) {
        guard let selection = colorPanelSelection else {
            return
        }

        let panel = notification.object as? NSColorPanel ?? NSColorPanel.shared
        colorStore.setColor(panel.color, for: selection)
        updateButtonIcon(accounts: accounts)
    }

    @objc private func resetAccountColor(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? AccountSelection else {
            return
        }

        colorStore.resetColor(for: selection)
        updateButtonIcon(accounts: accounts)
    }

    @objc private func refreshMenu(_ sender: NSMenuItem) {
        refreshAccounts(showLoading: true)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            refreshAccounts(showLoading: false)
        }
    }
}

private final class AccountSelection: NSObject {
    let host: String
    let login: String

    var id: String {
        "\(host)/\(login)"
    }

    init(account: GHAccount) {
        self.host = account.host
        self.login = account.login
    }

    init(host: String, login: String) {
        self.host = host
        self.login = login
    }
}

private final class GHAccountColorStore {
    private let defaults: UserDefaults
    private let keyPrefix = "accountColor."
    private let defaultColors = [
        "#0969DA",
        "#8250DF",
        "#1A7F37",
        "#BC4C00",
        "#BF3989",
        "#1B7C83",
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func color(for account: GHAccount) -> NSColor {
        color(forID: account.id)
    }

    func color(for selection: AccountSelection) -> NSColor {
        color(forID: selection.id)
    }

    func hasCustomColor(for account: GHAccount) -> Bool {
        defaults.string(forKey: key(forID: account.id)) != nil
    }

    func setColor(_ color: NSColor, for selection: AccountSelection) {
        defaults.set(hexString(for: color), forKey: key(forID: selection.id))
    }

    func resetColor(for selection: AccountSelection) {
        defaults.removeObject(forKey: key(forID: selection.id))
    }

    private func color(forID id: String) -> NSColor {
        if let storedHex = defaults.string(forKey: key(forID: id)),
           let storedColor = NSColor(hexString: storedHex) {
            return storedColor
        }

        let colorIndex = stableColorIndex(for: id)
        return NSColor(hexString: defaultColors[colorIndex]) ?? .controlAccentColor
    }

    private func key(forID id: String) -> String {
        keyPrefix + id
    }

    private func hexString(for color: NSColor) -> String {
        guard let rgbColor = color.usingColorSpace(.sRGB) else {
            return "#0969DA"
        }

        let red = Int((rgbColor.redComponent * 255).rounded())
        let green = Int((rgbColor.greenComponent * 255).rounded())
        let blue = Int((rgbColor.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private func stableColorIndex(for id: String) -> Int {
        var hash = 5381
        for scalar in id.unicodeScalars {
            hash = (hash &* 33) &+ Int(scalar.value)
        }

        return Int(hash.magnitude % UInt(defaultColors.count))
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        let trimmedHex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmedHex.count == 6,
              let value = Int(trimmedHex, radix: 16) else {
            return nil
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

private enum GHColorSwatch {
    static func image(color: NSColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        let bounds = NSRect(origin: .zero, size: size)
        let swatch = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        color.setFill()
        swatch.fill()

        NSColor.separatorColor.setStroke()
        swatch.lineWidth = 1
        swatch.stroke()

        image.isTemplate = false
        return image
    }
}

private final class GHClient: @unchecked Sendable {
    private let runner = GHProcessRunner()
    private let parser = GHAuthStatusParser()

    func accounts() async throws -> [GHAccount] {
        let output = try await runner.run(arguments: GHCommandBuilder.statusArguments())
        return try parser.parse(Data(output.utf8))
    }

    func switchAccount(host: String, login: String) async throws {
        let account = GHAccount(host: host, login: login, active: false)
        _ = try await runner.run(arguments: GHCommandBuilder.switchArguments(for: account))
    }
}

private final class GHProcessRunner: @unchecked Sendable {
    func run(arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try self.runSync(arguments: arguments)
        }.value
    }

    private func runSync(arguments: [String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = ghExecutableURL()
        process.arguments = process.executableURL?.lastPathComponent == "env"
            ? ["gh"] + arguments
            : arguments
        process.environment = processEnvironment()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw GHProcessError(exitCode: process.terminationStatus, stderr: errorOutput)
        }

        return output
    }

    private func ghExecutableURL() -> URL {
        for path in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"] where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return URL(fileURLWithPath: "/usr/bin/env")
    }

    private func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

        if let path = environment["PATH"], !path.isEmpty {
            environment["PATH"] = "\(defaultPath):\(path)"
        } else {
            environment["PATH"] = defaultPath
        }

        return environment
    }
}

private struct GHProcessError: Error, CustomStringConvertible {
    let exitCode: Int32
    let stderr: String

    var description: String {
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "gh exited with code \(exitCode)" : message
    }
}

private enum GHMenuBarIcon {
    static func image(tintColor: NSColor? = nil) -> NSImage {
        let image = templateImage()
        guard let tintColor else {
            return image
        }

        return tintedImage(from: image, color: tintColor)
    }

    private static func templateImage() -> NSImage {
        if let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            image.accessibilityDescription = "GitHub account switcher"
            return image
        }

        return fallbackImage()
    }

    private static func tintedImage(from image: NSImage, color: NSColor) -> NSImage {
        let tintedImage = NSImage(size: image.size)
        let rect = NSRect(origin: .zero, size: image.size)

        tintedImage.lockFocus()
        defer { tintedImage.unlockFocus() }

        color.setFill()
        rect.fill()
        image.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)

        tintedImage.isTemplate = false
        tintedImage.accessibilityDescription = image.accessibilityDescription
        return tintedImage
    }

    private static func fallbackImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.setFill()

        let head = NSBezierPath(ovalIn: NSRect(x: 3.1, y: 2.4, width: 11.8, height: 11.4))
        head.fill()

        let leftEar = NSBezierPath()
        leftEar.move(to: NSPoint(x: 5.0, y: 11.6))
        leftEar.line(to: NSPoint(x: 5.8, y: 16.1))
        leftEar.line(to: NSPoint(x: 8.4, y: 13.1))
        leftEar.close()
        leftEar.fill()

        let rightEar = NSBezierPath()
        rightEar.move(to: NSPoint(x: 9.6, y: 13.1))
        rightEar.line(to: NSPoint(x: 12.2, y: 16.1))
        rightEar.line(to: NSPoint(x: 13.0, y: 11.6))
        rightEar.close()
        rightEar.fill()

        let leftShoulder = NSBezierPath(ovalIn: NSRect(x: 4.3, y: 0.5, width: 3.8, height: 4.4))
        leftShoulder.fill()

        let rightShoulder = NSBezierPath(ovalIn: NSRect(x: 9.9, y: 0.5, width: 3.8, height: 4.4))
        rightShoulder.fill()

        let bridge = NSBezierPath(rect: NSRect(x: 7.1, y: 1.0, width: 3.8, height: 3.4))
        bridge.fill()

        let previousOperation = NSGraphicsContext.current?.compositingOperation
        NSGraphicsContext.current?.compositingOperation = .clear
        NSColor.clear.setFill()
        let leftEye = NSBezierPath(ovalIn: NSRect(x: 6.2, y: 7.8, width: 1.2, height: 1.4))
        leftEye.fill()

        let rightEye = NSBezierPath(ovalIn: NSRect(x: 10.6, y: 7.8, width: 1.2, height: 1.4))
        rightEye.fill()
        NSGraphicsContext.current?.compositingOperation = previousOperation ?? .sourceOver

        image.isTemplate = true
        image.accessibilityDescription = "GitHub account switcher"
        return image
    }
}
