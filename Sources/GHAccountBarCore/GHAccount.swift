import Foundation

public struct GHAccount: Equatable, Identifiable, Sendable {
    public let host: String
    public let login: String
    public let active: Bool

    public var id: String {
        "\(host)/\(login)"
    }

    public init(host: String, login: String, active: Bool) {
        self.host = host
        self.login = login
        self.active = active
    }
}

public struct GHAuthStatusParser: Sendable {
    public init() {}

    public func parse(_ data: Data) throws -> [GHAccount] {
        let status = try JSONDecoder().decode(GHAuthStatus.self, from: data)

        return status.hosts.keys.sorted().flatMap { hostName in
            status.hosts[hostName, default: []].compactMap { account in
                guard account.state == "success" else {
                    return nil
                }

                let login = account.login.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !login.isEmpty else {
                    return nil
                }

                let host = account.host?.trimmingCharacters(in: .whitespacesAndNewlines)
                return GHAccount(
                    host: host?.isEmpty == false ? host! : hostName,
                    login: login,
                    active: account.active
                )
            }
        }
    }
}

public enum GHCommandBuilder {
    public static func statusArguments() -> [String] {
        ["auth", "status", "--json", "hosts"]
    }

    public static func switchArguments(for account: GHAccount) -> [String] {
        [
            "auth",
            "switch",
            "--hostname",
            account.host,
            "--user",
            account.login,
        ]
    }
}

public enum GHStatusBarDisplay {
    public static func title(for accounts: [GHAccount]) -> String {
        ""
    }

    public static func tooltip(for accounts: [GHAccount]) -> String {
        guard let activeAccount = accounts.first(where: \.active) else {
            return "GitHub account switcher"
        }

        return "GitHub: \(activeAccount.login)"
    }

    public static func errorTitle() -> String {
        ""
    }

    public static func errorTooltip() -> String {
        "GitHub account switcher needs attention"
    }
}

public enum GHRefreshPolicy {
    public static let accountPollingInterval: TimeInterval = 2.0
}

private struct GHAuthStatus: Decodable {
    let hosts: [String: [GHAuthStatusAccount]]
}

private struct GHAuthStatusAccount: Decodable {
    let state: String
    let active: Bool
    let host: String?
    let login: String
}
