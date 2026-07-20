import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var sharedRemapper: KeyboardRemapper?

    func applicationDidBecomeActive(_ notification: Notification) {
        // User may have just granted Accessibility in System Settings.
        AppDelegate.sharedRemapper?.refreshAuthorizationStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clear HID-layer Caps/Escape mappings so they do not linger after quit.
        AppDelegate.sharedRemapper?.stop()
    }
}

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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: RemapSettings
    @StateObject private var remapper: KeyboardRemapper
    @StateObject private var launchAtLogin: LaunchAtLoginController

    init() {
        let settings = RemapSettings()
        let remapper = KeyboardRemapper(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _remapper = StateObject(wrappedValue: remapper)
        _launchAtLogin = StateObject(wrappedValue: LaunchAtLoginController())
        AppDelegate.sharedRemapper = remapper

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
                .frame(width: 640, height: 620)
        }

        Window("About SwiftKeyShim", id: "about") {
            AboutView()
                .environmentObject(settings)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 280, height: 220)
    }

    private var menuBarSystemImage: String {
        let needsShiftTap = settings.enabled && settings.mapShiftTap
        let shiftTapBroken = needsShiftTap && (!remapper.isRunning || !remapper.isTrusted)
        return shiftTapBroken ? "keyboard.badge.ellipsis" : "keyboard"
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

            Divider()

            Toggle(text.enableMapping, isOn: $settings.enabled)

            Toggle(text.mapEscapeToCapsLock, isOn: $settings.mapEscapeToCapsLock)
                .disabled(!settings.enabled)

            Toggle(text.mapCapsLockToEscape, isOn: $settings.mapCapsLockToEscape)
                .disabled(!settings.enabled)

            Toggle(text.mapShiftTap, isOn: $settings.mapShiftTap)
                .disabled(!settings.enabled)

            Divider()

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

            Button(text.restart) {
                restartApp()
            }

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

        for delay in [0.05, 0.15, 0.35] {
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

        // Force compact size; macOS may restore a larger previous frame.
        window.setContentSize(NSSize(width: 280, height: 220))
        window.styleMask.remove(.resizable)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    private func restartApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"\(bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    private var statusText: String {
        let hidActive = settings.mapEscapeToCapsLock || settings.mapCapsLockToEscape
        if !settings.enabled { return text.disabled }
        if remapper.isRunning { return settings.language == .chinese ? "正在监听" : "Listening" }
        if settings.mapShiftTap, !remapper.isTrusted {
            return hidActive ? text.hidActiveShiftNeedsPermission : text.waitingForPermission
        }
        if hidActive { return text.hidOnlyActive }
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
    private static let contentSize = NSSize(width: 280, height: 220)

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text(appName)
                .font(.title3.weight(.semibold))

            Text(versionText)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Link("GitHub", destination: repositoryURL)
                Link("MIT", destination: licenseURL)
            }
            .font(.callout)
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .background(WindowConfigurator(contentSize: Self.contentSize))
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "SwiftKeyShim"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        switch (version.isEmpty, build.isEmpty) {
        case (true, true):
            return ""
        case (false, true):
            return "\(text.version) \(version)"
        case (true, false):
            return "\(text.version) (\(build))"
        case (false, false):
            return "\(text.version) \(version) (\(build))"
        }
    }

    private var text: InterfaceText {
        InterfaceText(appLanguage: settings.language)
    }
}

/// Applies a fixed compact size to the hosting NSWindow (overrides restored frames).
private struct WindowConfigurator: NSViewRepresentable {
    let contentSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView)
        }
    }

    private func configure(_ view: NSView) {
        guard let window = view.window else { return }
        window.setContentSize(contentSize)
        window.styleMask.remove(.resizable)
    }
}
