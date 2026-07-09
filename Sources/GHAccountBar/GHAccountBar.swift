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
        refreshTimer = Timer.scheduledTimer(withTimeInterval: GHRefreshPolicy.accountPollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccounts(showLoading: false)
            }
        }
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
                item.representedObject = AccountSelection(host: account.host, login: account.login)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

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
        statusItem.menu = menu
    }

    private func updateButtonTitle(accounts: [GHAccount]) {
        statusItem.button?.title = GHStatusBarDisplay.title(for: accounts)
        statusItem.button?.toolTip = GHStatusBarDisplay.tooltip(for: accounts)
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

    init(host: String, login: String) {
        self.host = host
        self.login = login
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
    static func image() -> NSImage {
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
