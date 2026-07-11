<p align="center">
  <img src="output/imagegen/readme-hero.svg" alt="GH Account Bar menu bar mockup" width="100%">
</p>

# GH Account Bar

GH Account Bar is a tiny macOS menu bar app for switching between authenticated GitHub CLI accounts without leaving your current workflow.

It reads your authenticated `gh` accounts, shows them in a native menu, and switches the selected identity with one click.

## Features

- Native macOS menu bar utility with no Dock icon.
- Lists authenticated `gh` users across multiple GitHub hosts.
- Disables the active account so accidental no-op switches are obvious.
- Uses customizable account colors for menu swatches and the active menu bar icon.
- Keeps the active account visible in the icon tooltip and refreshes automatically.

## Requirements

- macOS 14 or newer
- GitHub CLI installed and authenticated with one or more accounts

Check your CLI auth state before running:

```sh
gh auth status
```

## Build from Source

Building requires the Swift 6.3 toolchain. Create and open a local app bundle with:

```sh
./script/build_and_run.sh
```

The script creates `dist/GHAccountBar.app` and opens it as a menu bar-only app. For development checks:

```sh
swift test
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
```
