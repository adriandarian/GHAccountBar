# Free GitHub Release Design

## Goal

Publish GHAccountBar `v0.1.0` as a free GitHub prerelease that users can download and run on Apple Silicon Macs without an App Store account, paid hosting, or Apple Developer Program membership.

## Distribution Model

GitHub Releases is the canonical download channel. A version tag matching `v*` starts a GitHub Actions workflow on the standard `macos-15` arm64 runner. The workflow packages the tagged source and publishes two release assets:

- `GHAccountBar-v0.1.0-arm64.zip`
- `GHAccountBar-v0.1.0-arm64.zip.sha256`

The release remains marked as a prerelease. Source archives generated automatically by GitHub are not presented as substitutes for the packaged app.

## App Bundle

A new `script/package_release.sh` script owns distributable bundle construction. It accepts a semantic version and build number, builds the Swift package in release mode for arm64, and creates `dist/GHAccountBar.app` with:

- bundle identifier `com.adriandarian.GHAccountBar`
- minimum system version `14.0`
- `CFBundleShortVersionString` from the release tag
- `CFBundleVersion` from the workflow run number, or `1` for a local package
- `LSUIElement = true`
- the release executable under `Contents/MacOS`
- `MenuBarIcon.png` under the standard `Contents/Resources` directory

The script applies an ad-hoc signature recursively and verifies the signature. It does not claim Developer ID signing or notarization.

The app resolves the packaged icon through `Bundle.main`. Raw SwiftPM development runs fall back to `Bundle.module`, and the local bundle builder copies the same icon into `Contents/Resources` so both bundle paths behave consistently.

## Automation

`.github/workflows/release.yml` runs only for pushed version tags. It:

1. Checks out the tagged commit.
2. Runs the complete Swift test suite.
3. Calls `script/package_release.sh` with the tag version and GitHub run number.
4. Verifies the app architecture is arm64, validates the property list and signature, expands the ZIP, and checks the packaged app.
5. Publishes the ZIP and checksum to a GitHub prerelease using the repository's `GITHUB_TOKEN`.

The workflow uses only GitHub-provided actions and the public repository's standard macOS runner, so it requires no paid services or repository secrets.

## Local Verification

Packaging tests are shell-based because the release behavior is bundle structure and command execution rather than Swift application logic. A verification script checks:

- missing or malformed version arguments fail
- the expected bundle metadata is present
- the executable and menu bar icon resource are included
- the packaged executable is arm64
- the app signature validates
- the ZIP expands to the expected app bundle
- the recorded SHA-256 matches the ZIP

The existing `swift test` suite must remain green.

## Documentation

The README gains an Install section that links to the latest GitHub release, explains that the first release supports Apple Silicon and requires macOS 14+, and gives the first-launch instructions: move the app into Applications, then Control-click the app and choose Open. It also states that `gh` must already be installed and authenticated.

## Version-Control and Release Integrity

The current color and icon work is included in `v0.1.0` after validation. All application, packaging, workflow, test, and documentation changes are committed before the tag is created. The release artifact is built by GitHub Actions from that tag so the downloadable binary is reproducible from the tagged source.

## Out of Scope

- Developer ID signing and Apple notarization
- Mac App Store distribution
- Intel or universal binaries
- Homebrew cask publishing
- automatic in-app updates
- DMG or PKG installers

These can be added in later releases without changing GitHub Releases as the canonical download channel.
