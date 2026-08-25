# 参与贡献

欢迎提交 Issue 和 Pull Request。请勿提交或附加腾讯的应用包、可执行文件、`Assets.car`、签名或备份。

反馈新版本兼容性时，请只提供：

- macOS 版本和芯片架构；
- 微信输入法版本号和构建号；
- 未修改 `Assets.car` 的 SHA-256；
- 颜色名称、原始 RGBA 值及预期记录数量；
- `assetutil`、`codesign`、进程启动和近期日志的验证结果。

提交 Pull Request 前请运行：

```sh
npm ci
npm run check
npm pack --dry-run
```
