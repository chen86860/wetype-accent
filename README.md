# WeType Accent

Customize the candidate-window accent color of WeType (微信输入法) on macOS.

> [!WARNING]
> This is an unofficial community tool. It is not affiliated with or endorsed by Tencent. Applying a patch replaces WeType's Developer ID signature with a local ad-hoc signature. Restore the original app before updating WeType.

## Features

- Any `#RRGGBB` accent color
- Automatic light, dark, secondary, and background variants
- Optional explicit colors for every variant
- Strict version and SHA-256 checks
- Full application backup before the first modification
- Automatic rollback when validation, signing, or restart fails
- `status`, `doctor`, and `restore` commands
- No Tencent application, binary, or asset files are distributed

## Compatibility

| WeType version | Build | Status |
| --- | ---: | --- |
| 2.2.0 | 617 | Verified |

Unknown versions and modified original resources are rejected without changing files.

## Install

Download and unzip the universal binary from [GitHub Releases](../../releases), make it executable, and move it somewhere on your `PATH`:

```sh
chmod +x wetype-accent
sudo mv wetype-accent /usr/local/bin/
```

Release binaries are ad-hoc signed but not Apple-notarized. macOS may ask you to confirm opening the downloaded executable. If you do not want to approve an unnotarized binary, build it from the auditable source instead.

Or build from source:

```sh
swift build -c release
cp .build/release/wetype-accent ./wetype-accent
```

## Usage

Preview an automatically derived palette:

```sh
wetype-accent preview --color '#007AFF'
```

Apply it:

```sh
sudo wetype-accent apply --color '#007AFF'
```

Override individual variants:

```sh
sudo wetype-accent apply \
  --color '#BF5AF2' \
  --dark '#CC7AFF' \
  --secondary '#CF86F7' \
  --background '#F7EEFC'
```

Inspect or diagnose the current installation:

```sh
wetype-accent status
wetype-accent doctor
```

Restore the exact Tencent-signed backup:

```sh
sudo wetype-accent restore
```

Use `--yes` for non-interactive confirmation. Use `--app /path/to/WeType.app` to inspect or test another copy.

## What it changes

WeType 2.2.0 stores candidate-window named colors in:

```text
/Library/Input Methods/WeType.app/Contents/Resources/Assets.car
```

The tool patches only six verified serialized CoreUI color records for `bc16`, `bg02`, `bg03`, and `bg04`. It validates the resulting catalog with Apple's `assetutil`, then consistently ad-hoc signs the application and its embedded code:

```sh
codesign --force --deep --sign - \
  --preserve-metadata=identifier,entitlements \
  "/Library/Input Methods/WeType.app"
```

It does not modify the Flutter AOT settings-window gradient.

## Backup and update behavior

The first patch stores a complete original bundle under:

```text
/Library/Application Support/WeTypeAccent/Backups/
```

This is intentionally a full backup because deep signing changes embedded code signatures. Updating WeType may overwrite the patch or reject the modified installation. Restore first, update through the official installer, and wait for a compatible WeType Accent profile before reapplying.

## Security and privacy

- All operations are local.
- The tool performs no network requests.
- Administrator access is requested only by running `apply` or `restore` with `sudo`.
- No background helper, daemon, or persistent privileged component is installed.
- Release builds are produced by GitHub Actions; SHA-256 checksums are attached to each release.
- Release binaries are built for Apple Silicon and Intel, but are not Apple-notarized.

## Development

```sh
swift test
swift run wetype-accent preview --color '#007AFF'
```

The release artifact is one executable file. Source code is split into a small core module and CLI entry point so the binary patch logic can be tested independently.

## License

MIT. “WeType” and “微信输入法” are trademarks of their respective owner.
