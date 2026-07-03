import SwiftUI
import AppKit

@main
struct SwiftKeyShimApp: App {
    @StateObject private var settings: RemapSettings
    @StateObject private var remapper: KeyboardRemapper

    init() {
        let settings = RemapSettings()
        let remapper = KeyboardRemapper(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _remapper = StateObject(wrappedValue: remapper)

        Task { @MainActor in
            remapper.start()
        }
    }

    var body: some Scene {
        MenuBarExtra("SwiftKeyShim", systemImage: "keyboard") {
            StatusMenuView()
                .environmentObject(settings)
                .environmentObject(remapper)
        }

        Settings {
            ContentView()
                .environmentObject(settings)
                .environmentObject(remapper)
                .frame(width: 520)
        }
    }
}

struct StatusMenuView: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var settings: RemapSettings
    @EnvironmentObject private var remapper: KeyboardRemapper

    var body: some View {
        Group {
            Button("设置...") {
                openFocusedSettings()
            }

            Divider()

            Toggle("启用键盘映射", isOn: $settings.enabled)

            Text(statusText)
                .foregroundStyle(.secondary)

            Divider()

            Button("退出 SwiftKeyShim") {
                NSApp.terminate(nil)
            }
        }
        .onAppear {
            remapper.refreshAuthorizationStatus()
        }
    }

    private func openFocusedSettings() {
        openSettings()

        for delay in [0.1, 0.3, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                focusSettingsWindow()
            }
        }
    }

    private func focusSettingsWindow() {
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)

        guard let window = NSApp.windows.first(where: { $0.isVisible && !$0.title.isEmpty }) else {
            return
        }

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    private var statusText: String {
        if remapper.isRunning { return "正在监听" }
        if !remapper.isTrusted { return "等待辅助功能权限" }
        if !settings.enabled { return "已停用" }
        return "未运行"
    }
}
