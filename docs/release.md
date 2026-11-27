# 发布 Clidock

## 本地验收

日常自用运行 `scripts/install-local.sh`，以 Local 配置构建并启动 `/Applications/ClidockLocal.app`。

验收 DMG 时运行 `scripts/package-dmg.sh --local`。脚本以 Release 配置构建 `Clidock.app`，验证两个 CPU 架构及代码签名，再生成本地 DMG 和校验文件。文件名带 `-local` 表示镜像使用本机临时签名。

在干净的 macOS 用户账户中打开 DMG，把应用拖到「应用程序」，逐项验收。

- 首次启动显示 Clidock 图标和欢迎窗口，历史为空。在其他应用复制文本、富文本和图片，打开面板并手动粘贴。
- 在 Finder 一次复制两个文件。用 Finder 来源筛选找到该记录，再粘贴到另一目录，核对文件数量和顺序。
- 切换桌面和显示器，用快捷键打开面板。预览卡片，编辑文本，把两条记录拖入钉板并排序。
- 启动剪贴队列，复制多条记录，连续粘贴并核对顺序。主动启用直接粘贴后授予辅助功能权限，核对焦点仍回到原应用。
- 添加排除应用，导出 JSON，在另一空库恢复。核对历史、来源、钉板顺序、成员和排除列表，并检查排除规则即时生效。

## 正式版本

在 GitHub 仓库的 Actions secrets 配置本项目的 Apple 凭据。

| Secret | 值 |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | 带私钥的 Developer ID Application 证书的 P12 文件，使用 Base64 编码 |
| `MACOS_CERTIFICATE_PASSWORD` | P12 导出密码 |
| `MACOS_DEVELOPER_ID` | 证书完整身份名，包含 Developer ID Application 前缀和 Team ID |
| `APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_SPECIFIC_PASSWORD` | 用于 Apple 公证的账户、团队与 App 专用密码 |

1. 在 `project.yml` 更新 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`。合入改动，等待主分支通过测试。
2. 给该提交打与版本对应的标签，例如 `v0.1.0`，推送标签。发布任务校验标签与应用版本，运行测试，并构建通用应用。
3. 发布任务签名应用并提交 Apple 公证，把票据装订到应用后制作 DMG，再对 DMG 签名、公证、装订并验证 Gatekeeper。成功后上传 DMG、SHA-256 校验文件和完整源码包到同一条 GitHub Release。
4. 从 Release 下载这三个文件，在同一目录运行下列命令，核对下载内容与公证票据，然后按本页的本地验收步骤安装。

```sh
shasum -a 256 -c Clidock-0.1.0.sha256
xcrun stapler validate Clidock-0.1.0.dmg
spctl --assess --type open --context context:primary-signature Clidock-0.1.0.dmg
```

源码包来自发布标签，并在 `Dependencies/KeyboardShortcuts/` 附带本次构建使用的依赖源码和许可证。离线构建时将 `project.yml` 的 `packages.KeyboardShortcuts` 配置替换为 `path: Dependencies/KeyboardShortcuts`，再生成工程。
