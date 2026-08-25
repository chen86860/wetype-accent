# WeType Accent

在 macOS 上自定义微信输入法候选窗的重点色，让默认绿色变成系统蓝、紫色、粉色或任意你喜欢的颜色。

[![最新版本](https://img.shields.io/github/v/release/chen86860/wetype-accent?label=最新版本)](https://github.com/chen86860/wetype-accent/releases/latest)
[![构建状态](https://github.com/chen86860/wetype-accent/actions/workflows/ci.yml/badge.svg)](https://github.com/chen86860/wetype-accent/actions/workflows/ci.yml)
[![许可证](https://img.shields.io/github/license/chen86860/wetype-accent?label=许可证)](LICENSE)

> [!WARNING]
> 这是非官方社区工具，与腾讯无关。应用补丁后，微信输入法原有的开发者签名会被替换为本机临时签名。更新微信输入法前，请先使用本工具恢复原版。

## 功能

- 支持任意 `#RRGGBB` 颜色
- 自动生成深色模式、次级色和浅色背景
- 支持分别指定每一种颜色
- 修改前完整备份微信输入法
- 严格校验颜色记录和资源文件
- 修改、签名或重启失败时自动回滚
- 支持状态检查、故障诊断和一键恢复
- 不分发腾讯的应用、二进制文件或资源文件

## 兼容性

| 微信输入法版本 | macOS | 处理方式 |
| --- | --- | --- |
| `>= 2.2.0` | `>= 13` | 资源结构符合预期时允许修改 |
| `< 2.2.0` | 任意 | 拒绝修改 |

新版本微信输入法如果改变了资源结构，工具会在写入前停止，不会强行修改应用。

## 快速开始

### 1. 安装

从 [Releases 页面](https://github.com/chen86860/wetype-accent/releases/latest) 下载名为 `wetype-accent` 的文件，然后在“终端”中执行：

```sh
cd ~/Downloads
chmod +x wetype-accent
sudo mv wetype-accent /usr/local/bin/
```

发布文件支持 Apple 芯片和 Intel Mac，但尚未经过 Apple 公证。如果 macOS 阻止运行，建议按照下方说明从源码构建。

### 2. 预览颜色

以 macOS 系统蓝 `#007AFF` 为例：

```sh
wetype-accent preview --color '#007AFF'
```

这一步只显示将要使用的配色，不会修改微信输入法。

### 3. 应用颜色

```sh
sudo wetype-accent apply --color '#007AFF'
```

工具会先完整备份微信输入法，再修改资源、重新签名并重启输入法。

## 常用颜色

| 颜色 | 色值 | 命令 |
| --- | --- | --- |
| macOS 蓝 | `#007AFF` | `sudo wetype-accent apply --color '#007AFF'` |
| 紫色 | `#BF5AF2` | `sudo wetype-accent apply --color '#BF5AF2'` |
| 粉色 | `#FF375F` | `sudo wetype-accent apply --color '#FF375F'` |
| 橙色 | `#FF9F0A` | `sudo wetype-accent apply --color '#FF9F0A'` |

需要完全控制深色模式和辅助颜色时，可以分别指定：

```sh
sudo wetype-accent apply \
  --color '#BF5AF2' \
  --dark '#CC7AFF' \
  --secondary '#CF86F7' \
  --background '#F7EEFC'
```

## 检查与恢复

查看当前状态：

```sh
wetype-accent status
```

检查资源、代码签名和运行状态：

```sh
wetype-accent doctor
```

恢复修改前的腾讯原版应用：

```sh
sudo wetype-accent restore
```

自动化调用时可以添加 `--yes` 跳过确认。使用 `--app /path/to/WeType.app` 可以检查另一份应用副本。

## 从源码构建

需要安装 Xcode Command Line Tools 或 Xcode：

```sh
git clone https://github.com/chen86860/wetype-accent.git
cd wetype-accent
swift build -c release
sudo cp .build/release/wetype-accent /usr/local/bin/
```

## 工作原理

候选窗颜色保存在微信输入法的 CoreUI 资源目录中：

```text
/Library/Input Methods/WeType.app/Contents/Resources/Assets.car
```

工具只替换经过验证的 `bc16`、`bg02`、`bg03` 和 `bg04` 颜色记录。写入前后会执行以下保护：

1. 检查微信输入法版本和颜色记录数量。
2. 完整备份原始 `.app`，并记录原始资源的 SHA-256。
3. 使用 Apple `assetutil` 验证生成的资源目录。
4. 对应用及其内嵌代码进行一致的临时签名。
5. 重启微信输入法并确认新进程正常运行。
6. 任一步骤失败时自动恢复备份。

本工具不会修改微信输入法设置窗口中的 Flutter 绿色渐变。

## 备份与更新

首次修改时，完整备份保存在：

```text
/Library/Application Support/WeTypeAccent/Backups/
```

由于修改资源会改变应用签名，更新微信输入法前建议先运行：

```sh
sudo wetype-accent restore
```

然后通过官方安装程序更新，再重新应用颜色。如果新版本资源结构不兼容，工具会拒绝修改并显示错误。

## 安全与隐私

- 所有操作均在本机完成，不会发送网络请求。
- 只有 `apply` 和 `restore` 需要通过 `sudo` 获取管理员权限。
- 不安装后台服务、守护进程或常驻的特权组件。
- Release 由 GitHub Actions 构建，并提供 SHA-256 校验文件。
- 发布文件使用临时签名，尚未经过 Apple 公证；介意时请从源码构建。

## 开发与贡献

```sh
swift test
swift run wetype-accent preview --color '#007AFF'
```

欢迎提交 Issue 或 Pull Request。新增微信输入法版本兼容性时，请不要提交腾讯的 `Assets.car`、应用包或其他受版权保护的文件。

## 许可证

项目采用 [MIT License](LICENSE)。“WeType”和“微信输入法”是其各自所有者的商标。
