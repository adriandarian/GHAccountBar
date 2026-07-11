# Free GitHub Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish GHAccountBar `v0.1.0` as a free Apple Silicon GitHub prerelease with an ad-hoc-signed app ZIP and verified checksum.

**Architecture:** A repository-owned shell script builds and validates the distributable app bundle. A tag-triggered GitHub Actions workflow runs the same tests and packaging script on GitHub's standard arm64 macOS runner, then creates the prerelease with `gh`. The README directs users to the release and documents the unsigned first-launch flow.

**Tech Stack:** Swift Package Manager, Bash, macOS `codesign`/`ditto`/`plutil`/`lipo`, GitHub Actions, GitHub CLI

## Global Constraints

- GitHub Releases remains the canonical download channel.
- The first release supports arm64 and macOS 14 or newer.
- The release uses ad-hoc signing and must not claim Developer ID signing or notarization.
- The workflow uses standard public-repository runners and requires no paid service or repository secret.
- The current account color and menu bar icon feature is included in `v0.1.0`.
- Homebrew, Intel builds, universal builds, DMG, PKG, App Store, and automatic updates remain out of scope.

---

### Task 1: Release bundle packager

**Files:**
- Create: `Tests/Packaging/package_release_test.sh`
- Create: `script/package_release.sh`
- Modify: `script/build_and_run.sh`
- Modify: `Sources/GHAccountBar/GHAccountBar.swift`

**Interfaces:**
- Consumes: semantic version as `$1`; positive numeric build number as optional `$2`
- Produces: `dist/GHAccountBar.app`, `dist/GHAccountBar-v<version>-arm64.zip`, and the adjacent `.sha256` file

- [ ] **Step 1: Write the failing packaging test**

Create a shell test that accepts an optional version and build number (defaulting to `0.1.0` and `1`), rejects invalid input through direct packager calls, invokes the packager with the selected values, checks bundle metadata and the standard `Contents/Resources/MenuBarIcon.png` path, validates arm64 architecture and code signing, expands the ZIP, and verifies the checksum.

- [ ] **Step 2: Run the test to verify it fails because the packager is absent**

Run: `bash Tests/Packaging/package_release_test.sh`

Expected: nonzero exit with `script/package_release.sh` missing.

- [ ] **Step 3: Implement the release packager**

The script must:

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
BUILD_NUMBER="${2:-1}"
APP_NAME="GHAccountBar"
BUNDLE_ID="com.adriandarian.GHAccountBar"
RESOURCE_BUNDLE="GHAccountBar_GHAccountBar.bundle"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || exit 2
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || exit 2

swift build -c release --arch arm64
```

It then stages the executable and `MenuBarIcon.png` under `Contents/Resources`, writes versioned `Info.plist` metadata, validates the property list, applies and verifies an ad-hoc signature, archives with `ditto --keepParent`, and writes a portable SHA-256 file from inside `dist`. The app and local builder prefer `Bundle.main` for the packaged icon while retaining `Bundle.module` for raw SwiftPM runs.

- [ ] **Step 4: Run static checks and the packaging test**

Run:

```bash
bash -n script/package_release.sh Tests/Packaging/package_release_test.sh
shellcheck script/package_release.sh Tests/Packaging/package_release_test.sh
bash Tests/Packaging/package_release_test.sh
```

Expected: all commands exit zero; the test prints `release package verified`.

- [ ] **Step 5: Commit the packager**

```bash
git add script/package_release.sh Tests/Packaging/package_release_test.sh
git commit -m "Add verified release packager"
```

### Task 2: GitHub prerelease automation and install documentation

**Files:**
- Create: `.github/workflows/release.yml`
- Modify: `README.md`

**Interfaces:**
- Consumes: pushed `v*` tag, `GITHUB_RUN_NUMBER`, and the built-in `GITHUB_TOKEN`
- Produces: a GitHub prerelease containing the ZIP and checksum

- [ ] **Step 1: Add the release workflow**

Create a workflow with `contents: write`, `runs-on: macos-15`, and these actions:

```yaml
on:
  push:
    tags:
      - "v*"
```

The job selects `/Applications/Xcode_26.3.app/Contents/Developer` through `DEVELOPER_DIR`, checks out the tag, reports `swift --version`, runs `swift test`, runs the packaging test with the tag version and workflow build number, and creates or updates a prerelease using the installed `gh` CLI. Release notes state that the build is for Apple Silicon, requires macOS 14 and `gh`, and requires Control-click then Open on first launch.

- [ ] **Step 2: Add README installation instructions**

Add an `Install` section before `Build from Source` with the GitHub Releases page link, Apple Silicon/macOS 14 requirements, drag-to-Applications instructions, Control-click/Open first launch, and the existing `gh auth status` prerequisite. Use `/releases`, not `/releases/latest`, because GitHub excludes prereleases from its latest-release route.

- [ ] **Step 3: Validate workflow and documentation**

Run:

```bash
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml"); puts "workflow yaml verified"'
rg -n "GHAccountBar/releases|Control-click|Apple Silicon|macOS 14" README.md .github/workflows/release.yml
git diff --check
```

Expected: YAML parses, all install strings are found, and the diff check is clean.

- [ ] **Step 4: Run the complete local verification suite**

Run:

```bash
swift test
bash Tests/Packaging/package_release_test.sh
```

Expected: seven Swift tests pass and the packaging test prints `release package verified`.

- [ ] **Step 5: Commit the workflow and documentation**

```bash
git add .github/workflows/release.yml README.md
git commit -m "Automate GitHub prereleases"
```

### Task 3: Publish and verify v0.1.0

**Files:**
- No repository files change during publication.

**Interfaces:**
- Consumes: verified `main` commit and GitHub authentication for `adriandarian/GHAccountBar`
- Produces: pushed `v0.1.0` tag and public GitHub prerelease assets

- [ ] **Step 1: Verify release state immediately before publication**

Run:

```bash
git status --short
git log -1 --oneline
git ls-remote --tags origin refs/tags/v0.1.0
gh release view v0.1.0
```

Expected: clean working tree, verified release commit at HEAD, and no existing `v0.1.0` tag or release.

- [ ] **Step 2: Push main and create the release tag**

```bash
git push origin main
git tag -a v0.1.0 -m "GHAccountBar v0.1.0"
git push origin v0.1.0
```

- [ ] **Step 3: Watch the release workflow**

Run `gh run list --workflow release.yml --limit 1`, obtain the run ID, then run `gh run watch <run-id> --exit-status`.

Expected: the tag workflow completes successfully.

- [ ] **Step 4: Verify the published prerelease and assets**

Run:

```bash
gh release view v0.1.0 --json url,isPrerelease,tagName,assets
rm -rf /tmp/ghaccountbar-v0.1.0-verify
mkdir -p /tmp/ghaccountbar-v0.1.0-verify
gh release download v0.1.0 --dir /tmp/ghaccountbar-v0.1.0-verify
(cd /tmp/ghaccountbar-v0.1.0-verify && shasum -a 256 -c GHAccountBar-v0.1.0-arm64.zip.sha256)
```

Expected: `isPrerelease` is true, both assets are present, and the downloaded checksum passes.
