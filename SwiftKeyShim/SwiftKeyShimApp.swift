import SwiftUI
import AppKit

@main
struct SwiftKeyShimApp: App {
    @StateObject private var settings: RemapSettings
    @StateObject private var remapper: KeyboardRemapper
    @StateObject private var launchAtLogin: LaunchAtLoginController

    init() {
        let settings = RemapSettings()
        let remapper = KeyboardRemapper(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _remapper = StateObject(wrappedValue: remapper)
        _launchAtLogin = StateObject(wrappedValue: LaunchAtLoginController())

        Task { @MainActor in
            remapper.start()
        }
    }

    var body: some Scene {
        MenuBarExtra("SwiftKeyShim", systemImage: "keyboard") {
            StatusMenuView()
                .environmentObject(settings)
                .environmentObject(remapper)
                .environmentObject(launchAtLogin)
        }

        Settings {
            ContentView()
                .environmentObject(settings)
                .environmentObject(remapper)
                .environmentObject(launchAtLogin)
                .frame(width: 640, height: 560)
        }
    }
}

struct StatusMenuView: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var settings: RemapSettings
    @EnvironmentObject private var remapper: KeyboardRemapper
    @EnvironmentObject private var launchAtLogin: LaunchAtLoginController

    var body: some View {
        Group {
            Button(text.settings) {
                openFocusedSettings()
            }

            Divider()

            Toggle(text.enableMapping, isOn: $settings.enabled)

            Toggle(text.launchAtLogin, isOn: launchAtLoginBinding)

            Text(statusText)
                .foregroundStyle(.secondary)

            if let launchAtLoginError = launchAtLogin.lastError {
                Text(launchAtLoginError)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button(text.quit) {
                NSApp.terminate(nil)
            }
        }
        .onAppear {
            remapper.refreshAuthorizationStatus()
            launchAtLogin.refresh()
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
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)

        guard let window = NSApp.windows.first(where: { $0.isVisible && !$0.title.isEmpty }) else {
            return
        }

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    private var statusText: String {
        if remapper.isRunning { return settings.language == .chinese ? "正在监听" : "Listening" }
        if !remapper.isTrusted { return text.waitingForPermission }
        if !settings.enabled { return text.disabled }
        return text.notRunning
    }

    private var text: InterfaceText {
        InterfaceText(appLanguage: settings.language)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }
}
