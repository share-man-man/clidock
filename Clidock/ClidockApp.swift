// Modified for Clidock on 2026-11-27. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import SwiftData

@main
struct ClidockApp: App {
    // Not @State: init() starts clipboard monitoring and registers the hotkeys on this
    // instance, but SwiftUI is free to discard the first @State value and build a new
    // one. Built with the Xcode 27 SDK it does exactly that, so the started instance
    // was deallocated right after launch and the UI got one that never started.
    private let appState = AppState.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppState.showsMenuBarIconDefaultsKey) private var showsMenuBarIcon = true

    private var sharedModelContainer: ModelContainer { Self.sharedModelContainer }

    private static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ClipboardItem.self,
            Pinboard.self,
            PinboardEntry.self,
            ExcludedApp.self,
        ])

        let storeURL = StoreManager.resolveStoreURL()
        StoreManager.backupStore(at: storeURL)

        let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)

        // 1차: 정상 오픈
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            StoreManager.logger.error("Failed to open store: \(error.localizedDescription)")
        }

        // 2차: 열 수 없는 store를 격리 폴더로 옮기고 새로 시작 (원본과 백업은 보존)
        StoreManager.quarantineStore(at: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            StoreManager.logger.error("Recovery failed: \(error.localizedDescription)")
        }

        // 3차: in-memory 폴백 (앱은 실행되지만 데이터 비영속)
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        } catch {
            fatalError("Cannot create any ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        // MenuBarExtra writes its own state back through `isInserted` whenever
        // the app activates or is inspected. With Settings open, turning the
        // icon off got that stale `true` written back before the scene saw
        // `false`, and the toggle flipped back on (#25). The setting only
        // changes from Settings, so the write-back is ignored.
        MenuBarExtra(isInserted: Binding(get: { showsMenuBarIcon }, set: { _ in })) {
            MenuBarContentView()
                .environment(appState)
                .modelContainer(sharedModelContainer)
        } label: {
            Image(nsImage: MenuBarIconImage.current)
                .accessibilityLabel(Text(verbatim: Bundle.main.appName))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(appState)
                .modelContainer(sharedModelContainer)
        }
        .defaultSize(width: 750, height: 605)
        .windowResizability(.contentMinSize)
    }

    init() {
        let context = sharedModelContainer.mainContext
        appState.start(modelContext: context, modelContainer: sharedModelContainer)

        // First-run welcome tour (NSApp is not ready in init, defer it)
        Task { @MainActor [appState, sharedModelContainer] in
            try? await Task.sleep(for: .milliseconds(400))
            OnboardingWindowController.shared.showIfNeeded(
                appState: appState,
                modelContainer: sharedModelContainer
            )
        }

        // Apply saved theme on launch (NSApp is not ready in init, defer it)
        DispatchQueue.main.async { [sharedModelContainer] in

            let theme = UserDefaults.standard.string(forKey: "appTheme") ?? "System"
            switch theme {
            case "Light": NSApp.appearance = NSAppearance(named: .aqua)
            case "Dark": NSApp.appearance = NSAppearance(named: .darkAqua)
            default: NSApp.appearance = nil
            }

            // Save SwiftData on app termination
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    try? sharedModelContainer.mainContext.save()
                }
            }

            // Save when app loses focus (guards against force-kill/power loss)
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    try? sharedModelContainer.mainContext.save()
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Opening Clidock again while it runs (Finder, Spotlight, `open -a`)
    /// opens Settings, which is the way back when the menu bar icon is
    /// hidden (#25). Rectangle and BetterDisplay do the same.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppState.shared.openSettings()
        return false
    }
}
