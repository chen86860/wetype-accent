# Contributing

Contributions are welcome. Do not commit or attach Tencent application bundles, executables, `Assets.car` files, signatures, or backups.

For a new WeType version, provide only:

- macOS version and architecture;
- WeType marketing version and build number;
- SHA-256 of the unmodified `Assets.car`;
- names, original RGBA values, and expected record counts;
- validation results from `assetutil`, `codesign`, process startup, and recent logs.

Run before opening a pull request:

```sh
swift test
swift build -c release
```
