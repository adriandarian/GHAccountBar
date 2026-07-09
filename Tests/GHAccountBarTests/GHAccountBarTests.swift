import Foundation
import Testing
@testable import GHAccountBarCore

@Test func parsesAuthenticatedAccountsFromGHAuthStatusJSON() throws {
    let json = """
    {
      "hosts": {
        "github.com": [
          {
            "state": "success",
            "active": true,
            "host": "github.com",
            "login": "primary-user",
            "tokenSource": "keyring",
            "scopes": "gist, read:org, repo, workflow",
            "gitProtocol": "https"
          },
          {
            "state": "success",
            "active": false,
            "host": "github.com",
            "login": "secondary-user",
            "tokenSource": "keyring",
            "scopes": "gist, read:org, repo, workflow, write:packages",
            "gitProtocol": "https"
          }
        ]
      }
    }
    """

    let accounts = try GHAuthStatusParser().parse(Data(json.utf8))

    #expect(accounts == [
        GHAccount(host: "github.com", login: "primary-user", active: true),
        GHAccount(host: "github.com", login: "secondary-user", active: false),
    ])
}

@Test func ignoresFailedOrMissingLoginAccounts() throws {
    let json = """
    {
      "hosts": {
        "github.com": [
          { "state": "failed", "active": false, "host": "github.com", "login": "broken" },
          { "state": "success", "active": false, "host": "github.com", "login": "" },
          { "state": "success", "active": true, "host": "github.com", "login": "ok" }
        ]
      }
    }
    """

    let accounts = try GHAuthStatusParser().parse(Data(json.utf8))

    #expect(accounts == [
        GHAccount(host: "github.com", login: "ok", active: true),
    ])
}

@Test func buildsGlobalSwitchArgumentsForSelectedAccount() {
    let account = GHAccount(host: "github.com", login: "secondary-user", active: false)

    let arguments = GHCommandBuilder.switchArguments(for: account)

    #expect(arguments == [
        "auth",
        "switch",
        "--hostname",
        "github.com",
        "--user",
        "secondary-user",
    ])
}

@Test func statusBarTitleIsEmptyForIconOnlyMenuBarItem() {
    let accounts = [
        GHAccount(host: "github.com", login: "very_long_github_username", active: true),
    ]

    #expect(GHStatusBarDisplay.title(for: accounts) == "")
}

@Test func statusBarTooltipShowsActiveAccount() {
    let accounts = [
        GHAccount(host: "github.com", login: "primary-user", active: true),
        GHAccount(host: "github.com", login: "secondary-user", active: false),
    ]

    #expect(GHStatusBarDisplay.tooltip(for: accounts) == "GitHub: primary-user")
}

@Test func refreshPolicyKeepsMenuStateFreshWithoutBeingAggressive() {
    #expect(GHRefreshPolicy.accountPollingInterval == 2.0)
}

@Test func refreshPolicyUsesCommonRunLoopModeForMenuTracking() {
    #expect(GHRefreshPolicy.accountPollingRunLoopMode == .common)
}
