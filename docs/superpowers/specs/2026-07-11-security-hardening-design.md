# GHAccountBar Security Hardening Design

## Context

The repository security scan preserved three concrete weaknesses even though final policy did not promote them as reportable vulnerabilities:

1. `GHProcessRunner` falls back to `/usr/bin/env gh` and retains inherited `PATH`, so executable selection is not fail-closed.
2. Account refresh can replace the loading menu while `gh auth switch` is pending, allowing a second switch to race the first.
3. The release workflow executes `actions/checkout@v7` by mutable tag while the job has `contents: write`.

The release workflow currently runs on every `v*` tag push. The desired operating model is manual release only, so GitHub Actions minutes are consumed only when a release is explicitly requested.

## Goals

- Execute `gh` only from the supported trusted installation paths.
- Prevent overlapping account-switch operations and refreshes during a switch.
- Pin the checkout action to the exact official commit currently referenced by `v7`.
- Change releases from automatic tag-push execution to explicit `workflow_dispatch`.
- Preserve existing account enumeration, switching, packaging, release notes, prerelease behavior, and local build workflows.
- Add regression tests that fail against the current implementation and pass with the hardened implementation.

## Non-goals

- Add a settings UI or user-configurable `gh` path.
- Add notarization, Developer ID signing, or a new distribution channel.
- Split the release into multiple jobs or introduce artifact upload/download actions.
- Redesign the app menu, account color behavior, or polling interval.

## Design

### Trusted GitHub CLI resolution

Move the executable-selection policy into `GHAccountBarCore` so it can be tested directly. The policy checks these paths in order:

1. `/opt/homebrew/bin/gh`
2. `/usr/local/bin/gh`
3. `/usr/bin/gh`

It returns the first executable path and throws a dedicated not-found error when none exists. It never searches inherited `PATH` and never returns `/usr/bin/env`.

`GHProcessRunner` will use the resolved absolute URL, pass the existing argument array directly, and stop rewriting `PATH`. Existing Homebrew installations continue to work. Unsupported custom locations fail visibly through the existing error-menu path with an actionable message listing the supported locations.

### Serialized account switching

Add a small state guard in `GHAccountBarCore` with three operations:

- `begin()` succeeds only when no switch is active.
- `finish()` clears the active state.
- `isInProgress` exposes whether refresh should be suppressed.

`AppDelegate` owns one guard and one stored switch task. `selectAccount` must acquire the guard, cancel any already-running refresh task, and then replace the menu before starting switch work. Periodic and menu-open refreshes return without changing the menu while the guard is active. A refresh that began before the switch must re-check the guard before rendering either accounts or an error, so late refresh output cannot replace the loading menu. Both switch success and failure paths release the guard exactly once; success then refreshes accounts, while failure renders the existing error menu. Application termination cancels the stored task.

This preserves the current UI: the loading menu remains visible during a switch, and a successful switch refreshes immediately. The only behavior removed is starting or rendering another account selection before the active switch finishes.

### Manual, pinned release workflow

Replace the push-tag trigger with:

```yaml
on:
  workflow_dispatch:
    inputs:
      tag:
        description: Release tag to build and publish
        required: true
        type: string
```

The workflow checks out `${{ inputs.tag }}`, derives the semantic version from that same input, and publishes to that exact tag. It rejects values that do not match the existing `v<semantic-version>` convention before building.

Pin checkout to the current official `v7` commit resolved from `actions/checkout`:

```yaml
uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7
```

`contents: write` remains job-scoped because publishing a release requires it. The immutable action pin closes the scanned mutable-action path without adding new workflow actions or artifact-transfer complexity. Tag pushes alone no longer start the workflow or consume Actions minutes.

## Error Handling

- Missing trusted `gh`: throw a stable error that names the trusted paths; the existing menu error renderer displays it and offers Retry/Quit.
- Duplicate switch request: ignore it while the loading menu is active. No second process is launched.
- Switch failure: release the guard, preserve the existing process error text, and render Retry/Quit.
- Invalid manual release tag: fail before checkout/build with a clear validation error.
- Missing release tag: GitHub prevents dispatch because the input is required.

## Test Strategy

Follow red-green TDD for each behavior.

### Swift tests

- Resolver selects the first executable trusted path.
- Resolver falls back to the next trusted path when earlier paths are unavailable.
- Resolver throws when no trusted path is executable and never considers an arbitrary PATH location.
- Switch guard rejects a second `begin()` while active.
- Switch guard permits a new operation after `finish()`.
- Source-level integration coverage confirms `selectAccount` cancels an in-flight refresh and refresh completion checks the active-switch guard before rendering.

### Workflow tests

- Workflow declares `workflow_dispatch` with required `tag` input.
- Workflow has no push/tag trigger.
- Checkout uses the exact 40-character SHA `9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0` and checks out the requested tag.
- Version derivation and release publication use the dispatch input rather than `GITHUB_REF_NAME`.
- Existing runner, toolchain, package verification, prerelease, and README checks remain.

### Verification

- Run focused Swift tests through `swift test`.
- Run `bash Tests/Packaging/release_workflow_test.sh`.
- Run `bash -n` on modified shell tests and embedded workflow shell blocks where applicable.
- Run the repository's full `swift test` suite.
- Inspect the final diff for inherited PATH fallback, unguarded switch-task creation, mutable action refs, and automatic push triggers.

## Compatibility and Security Invariants

- Supported Homebrew and system `gh` locations keep working unchanged.
- Host and login remain separate process arguments; no shell is introduced.
- Only one global account switch can be active at a time.
- Account polling resumes after the active switch succeeds or fails.
- Release source, version, and publication tag all come from the same explicit dispatch input.
- No mutable GitHub Action reference executes in the write-capable release job.
