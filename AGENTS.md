# Popback 开发指引

Popback 是面向 macOS 14+ 的本地剪贴板历史与剪贴队列应用（Swift 6 / SwiftUI / AppKit / SwiftData）。`CLAUDE.md` 软链指向本文件。

## 构建与测试

工程由 `project.yml` 通过 XcodeGen 生成，增删文件或改动构建配置后需重新生成：

```sh
xcodegen generate
xcodebuild -project Popback.xcodeproj -scheme Popback -destination 'platform=macOS' test
```

- 日常本地安装：`./scripts/install-local.sh`（安装至 `/Applications/PopbackLocal.app`）
- 本地 Release 验收镜像：`./scripts/package-dmg.sh --local`（输出至 `dist/`）
- 开发调试：在 Xcode 中使用 Debug 配置运行 `PopbackDev.app`

## 项目约定

- **系统与并发**：保持 macOS 14 兼容与 Swift 6 严格并发；操作 AppKit 窗口与面板的代码标注 `@MainActor`。
- **非激活面板**：历史面板使用非激活式 `NSPanel` 承载 SwiftUI，避免抢占来源应用的输入焦点。
- **剪贴板写入**：Popback 自身写入剪贴板时必须使用 `OwnPasteboardWrite` 标记，供 `ClipboardMonitor` 识别忽略。
- **测试隔离**：单元测试使用独立的命名剪贴板与内存或临时存储，不污染用户剪贴板和本地数据库。
- **常量与资源**：共享界面常量维护在 `Popback/Utilities/DesignTokens.swift`；应用图标源图在 `design/AppIcon.svg`，图标资源在 `Popback/Resources/Assets.xcassets`。

## 参考

- 开发与构建配置说明：[CONTRIBUTING.md](CONTRIBUTING.md)
- 签名、公证与发布流程：[docs/release.md](docs/release.md)
