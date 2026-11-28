// Modified for Popback on 2026-11-27. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit

struct HistoryPanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    /// Settings > Appearance > Background Transparency, from the standard
    /// blur (0) to clear (1).
    @AppStorage(PanelBackgroundTransparency.defaultsKey)
    private var backgroundTransparency: Double = PanelBackgroundTransparency.defaultValue
    /// System Settings > Accessibility > Display > Reduce Transparency.
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency

    var body: some View {
        ZStack {
            VisualEffectBackground(
                material: colorScheme == .dark ? .hudWindow : .popover
            )
                .opacity(PanelBackgroundTransparency.blurOpacity(
                    for: backgroundTransparency,
                    reducesTransparency: reducesTransparency
                ))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                NavigationBarView()

                if appState.directPastePermission.showsPanelBanner {
                    DirectPastePermissionBanner(
                        colorScheme: colorScheme,
                        onOpenSettings: { appState.openDirectPasteAccessibilitySettings() },
                        onTurnOff: { appState.directPastePermission.disableDirectPaste() },
                        onDismiss: { appState.directPastePermission.dismissPanelBanner() }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                ZStack {
                    // Cards layer
                    Group {
                        CardGridView()
                            .opacity(appState.selectedTab == .history ? 1 : 0)
                            .allowsHitTesting(appState.selectedTab == .history)

                        if case .pinboard(let id) = appState.selectedTab {
                            PinboardGridView(pinboardId: id)
                                .id(id)
                        }
                    }
                    .opacity(appState.previewItem == nil ? 1 : 0)

                    // Preview layer (replaces cards)
                    if let previewItem = appState.previewItem {
                        PreviewView(
                            item: previewItem,
                            onClose: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    appState.searchState.selectedIndex = nil
                                    appState.selectForPreview(nil)
                                }
                            },
                            onPaste: {
                                appState.paste(previewItem)
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .bottom))
                        ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onChange(of: appState.selectedTab) { _, _ in
                appState.selectForPreview(nil)
            }
            if let toast = appState.panelToast {
                PanelToastView(
                    toast: toast,
                    topInset: DesignTokens.Nav.height
                        + (appState.directPastePermission.showsPanelBanner ? DesignTokens.Nav.bannerHeight : 0)
                        + 8
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.16), value: appState.panelToast)
        .animation(.easeOut(duration: 0.16), value: appState.directPastePermission.showsPanelBanner)
    }
}

private struct DirectPastePermissionBanner: View {
    let colorScheme: ColorScheme
    let onOpenSettings: () -> Void
    let onTurnOff: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)

            Text("Direct paste needs Accessibility permission. Clips are only copied.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.Nav.activeTextColor(for: colorScheme))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Button("Open Settings\u{2026}", action: onOpenSettings)
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.orange.opacity(colorScheme == .dark ? 0.22 : 0.15))
                )
                .fixedSize()

            Button("Turn Off", action: onTurnOff)
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DesignTokens.Nav.activeBackground(for: colorScheme))
                )
                .fixedSize()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, DesignTokens.Nav.horizontalPadding)
        .frame(height: DesignTokens.Nav.bannerHeight)
        .background(Color.orange.opacity(colorScheme == .dark ? 0.13 : 0.09))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.orange.opacity(colorScheme == .dark ? 0.22 : 0.16))
                .frame(height: 0.75)
        }
    }
}

private struct PanelToastView: View {
    let toast: PanelToast
    let topInset: CGFloat

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: toast.systemImage)
                .font(.system(size: 12, weight: .semibold))

            Text(toast.message)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.primary.opacity(0.86))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, topInset)
        .allowsHitTesting(false)
    }
}
