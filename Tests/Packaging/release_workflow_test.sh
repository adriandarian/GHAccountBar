#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"
README="$ROOT_DIR/README.md"

fail() {
  echo "release_workflow_test: $*" >&2
  exit 1
}

test -f "$WORKFLOW" || fail "release workflow is missing"

ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$WORKFLOW"

rg -q 'tags:' "$WORKFLOW" || fail "workflow does not declare a tag trigger"
rg -q '"v\*"' "$WORKFLOW" || fail "workflow does not target version tags"
rg -q 'contents: write' "$WORKFLOW" || fail "workflow cannot publish release assets"
rg -q 'runs-on: macos-15' "$WORKFLOW" || fail "workflow does not use the standard arm64 runner"
rg -q 'DEVELOPER_DIR: /Applications/Xcode_26\.3\.app/Contents/Developer' "$WORKFLOW" || fail "workflow does not select the Swift 6.3 toolchain"
rg -q 'actions/checkout@v7' "$WORKFLOW" || fail "workflow does not use the pinned checkout major"
rg -q 'swift test' "$WORKFLOW" || fail "workflow does not run Swift tests"
rg -q 'package_release_test\.sh' "$WORKFLOW" || fail "workflow does not run package verification"
rg -q 'gh release create' "$WORKFLOW" || fail "workflow does not create a GitHub release"
rg -q -- '--prerelease' "$WORKFLOW" || fail "workflow does not mark the release as a prerelease"

rg -q 'github\.com/adriandarian/GHAccountBar/releases' "$README" || fail "README does not link to GitHub Releases"
rg -q 'Apple Silicon' "$README" || fail "README does not state architecture support"
rg -q 'Control-click' "$README" || fail "README does not explain the first launch"

echo "release workflow verified"
