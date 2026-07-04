import SwiftUI
import AppKit

enum SystemSettingsNavigator {
    static func openInputSourceShortcuts() {
        let urls = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard"
        ]

        for urlString in urls {
            guard let url = URL(string: urlString), NSWorkspace.shared.open(url) else { continue }
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

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
        MenuBarExtra("SwiftKeyShim", systemImage: menuBarSystemImage) {
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

        Window("About SwiftKeyShim", id: "about") {
            AboutView()
                .environmentObject(settings)
                .frame(width: 260, height: 230)
        }
    }

    private var menuBarSystemImage: String {
        settings.enabled && (!remapper.isRunning || !remapper.isTrusted) ? "keyboard.badge.ellipsis" : "keyboard"
    }
}

struct StatusMenuView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var settings: RemapSettings
    @EnvironmentObject private var remapper: KeyboardRemapper
    @EnvironmentObject private var launchAtLogin: LaunchAtLoginController

    var body: some View {
        Group {
            Button(text.settings) {
                openFocusedSettings()
            }

            Button(text.openInputSourceShortcuts) {
                SystemSettingsNavigator.openInputSourceShortcuts()
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

            Button(text.about) {
                openFocusedAbout()
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

    private func openFocusedAbout() {
        openWindow(id: "about")

        for delay in [0.1, 0.3, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                focusAboutWindow()
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

    private func focusAboutWindow() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)

        guard let window = NSApp.windows.first(where: { $0.title == "About SwiftKeyShim" }) else {
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

struct AboutView: View {
    @EnvironmentObject private var settings: RemapSettings

    private let repositoryURL = URL(string: "https://github.com/WHYBBE/SwiftKeyShim")!
    private let licenseURL = URL(string: "https://github.com/WHYBBE/SwiftKeyShim/blob/main/LICENSE")!

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                Text(appName)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(versionText)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                Text(text.repository)
                Link("WHYBBE/SwiftKeyShim", destination: repositoryURL)

                Link("MIT", destination: licenseURL)
            }
            .padding(.top, 4)
        }
        .padding(18)
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "SwiftKeyShim"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(text.version) \(version) (\(build))"
    }

    private var text: InterfaceText {
        InterfaceText(appLanguage: settings.language)
    }
}
