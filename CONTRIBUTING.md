# 参与 Popback 开发

请在 [Issues](https://github.com/share-man-man/popback/issues) 描述问题或需求。报告剪贴板问题时，请提供 macOS 版本、Popback 版本、来源应用和能复现问题的示例内容。

## Install from source

Install Xcode 26 or later and XcodeGen. From the project folder, run the command below to build, install, and open **PopbackLocal** in Applications.

安装 Xcode 26 或更高版本及 XcodeGen 后，在项目根目录运行以下命令。脚本会构建日常版并从「应用程序」启动 **PopbackLocal**。

```sh
./scripts/install-local.sh
```

## 构建与测试

需要 Xcode 26 或更高版本（Swift 6.2 工具链）和 XcodeGen。首次构建会下载固定版本的 KeyboardShortcuts。工程由 `project.yml` 生成，支持 macOS 14 及以上。在仓库根目录运行以下命令。

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Popback.xcodeproj -scheme Popback -destination 'platform=macOS' test
open Popback.xcodeproj
```

单元测试使用独立测试 target。测试剪贴板读写时使用命名的测试剪贴板，测试数据存储时使用内存库或临时目录。

## 构建配置

| 配置 | 用途 | 应用 | 打开历史面板 |
| --- | --- | --- | --- |
| Debug | 在 Xcode 选择 Popback 和 My Mac，按 ⌘R 调试 | `PopbackDev.app` | `popback-dev://open` |
| Local | 运行 `scripts/install-local.sh` 安装并启动日常版 | `/Applications/PopbackLocal.app` | `popback-local://open` |
| Release | 运行 `scripts/package-dmg.sh --local`，在 `dist/` 生成验收镜像 | `Popback.app` | `popback://open` |

三个版本各自保存设置。历史库位于 `~/Library/Application Support/<Bundle ID>/`，正式版标识为 `io.github.share-man-man.popback`，Debug 和 Local 分别追加 `.dev` 和 `.local`。切换版本前先退出当前应用，让新版本接管全局快捷键。要迁移历史，可在「设置 → 通用」导出和导入 JSON 备份。

Debug 菜单栏图标带有 `DEV` 标记，菜单首行显示 `PopbackDev · DEV`。Local 菜单首行显示 `PopbackLocal · LOCAL`。各版本的 URL scheme 还支持 `toggle` 和 `queue` 命令。签名、公证和安装验收见[发布说明](docs/release.md)。

## 贡献与来源

Popback 的 macOS 代码源自 [Clipbara](https://github.com/mobrava/Clipbara)，取材基线为 [mine 分支的 4682e5e](https://github.com/share-man-man/Clipbara/commit/4682e5ec832e84d86c9412cf423693ebc67f0a2b)。自 2026-11-27 起，本项目独立维护应用身份、本地存储、备份、界面和发布流程。

在拉取请求中说明用户可见的变化和验证结果。提交的贡献按 [GPL-3.0-only](LICENSE) 授权。引入第三方代码时请保留其版权和许可声明。
