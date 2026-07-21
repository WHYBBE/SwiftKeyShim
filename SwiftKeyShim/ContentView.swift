import SwiftUI

private enum SettingsTab: Hashable {
    case keyboard
    case general
}

struct ContentView: View {
    @EnvironmentObject private var settings: RemapSettings
    @EnvironmentObject private var remapper: KeyboardRemapper
    @EnvironmentObject private var launchAtLogin: LaunchAtLoginController
    @State private var selectedTab: SettingsTab = .keyboard

    var body: some View {
        TabView(selection: $selectedTab) {
            KeyboardSettingsView()
                .tabItem {
                    Label(text.keyboardTab, systemImage: "keyboard")
                }
                .tag(SettingsTab.keyboard)

            GeneralSettingsView()
                .tabItem {
                    Label(text.generalTab, systemImage: "gearshape")
                }
                .tag(SettingsTab.general)
        }
        .onAppear {
            remapper.refreshAuthorizationStatus()
        }
    }

    private var text: InterfaceText {
        InterfaceText(appLanguage: settings.language)
    }
}

private struct KeyboardSettingsView: View {
    @EnvironmentObject private var settings: RemapSettings
    @EnvironmentObject private var remapper: KeyboardRemapper

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(text.keyboardTab)
                        .font(.title2.bold())
                    Text(text.subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(text.enableMapping, isOn: $settings.enabled)
                    .toggleStyle(.switch)

                Divider()

                Text(text.capsEscapeSection)
                    .font(.headline)

                Text(text.capsEscapePermissionNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(text.mapEscapeToCapsLock, isOn: $settings.mapEscapeToCapsLock)
                    .toggleStyle(.switch)
                    .disabled(!settings.enabled)

                Toggle(text.mapCapsLockToEscape, isOn: $settings.mapCapsLockToEscape)
                    .toggleStyle(.switch)
                    .disabled(!settings.enabled)

                Text(text.capsEscapeTip)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text(text.shiftSection)
                    .font(.headline)

                Text(text.shiftPermissionNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(text.mapShiftTap, isOn: $settings.mapShiftTap)
                    .toggleStyle(.switch)
                    .disabled(!settings.enabled)

                Group {
                    Picker(text.triggerKey, selection: $settings.shiftSide) {
                        ForEach(ShiftSide.allCases) { side in
                            Text(side.title(language: settings.language)).tag(side)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(text.targetType, selection: $settings.targetKeyMode) {
                        ForEach(TargetKeyMode.allCases) { mode in
                            Text(mode.title(language: settings.language)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if settings.targetKeyMode == .preset {
                        Picker(text.tapSends, selection: $settings.targetKeyCode) {
                            ForEach(FunctionKey.supported) { key in
                                Text(key.title).tag(key.id)
                            }
                        }
                    } else {
                        TextField(text.targetKeyCode, text: $settings.customTargetKeyCodeText)
                            .textFieldStyle(.roundedBorder)
                        Text(text.commonKeyCodes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text(text.holdThreshold)
                            Spacer()
                            Text("\(Int(settings.tapThresholdMilliseconds)) ms")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.tapThresholdMilliseconds, in: 80...300, step: 10)
                    }
                }
                .disabled(!settings.enabled || !settings.mapShiftTap)

                Divider()

                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(statusText)
                            .font(.headline)
                        if let statusDetail {
                            Text(statusDetail)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if settings.enabled, settings.mapShiftTap, !remapper.isTrusted {
                            Button(text.requestPermission) {
                                remapper.requestAccessibilityPermission()
                            }
                        }
                    }
                }

                Text(text.inputSourceTip)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(text.openInputSourceShortcuts) {
                    SystemSettingsNavigator.openInputSourceShortcuts()
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            remapper.refreshAuthorizationStatus()
        }
    }

    private var hidActive: Bool {
        settings.enabled && (settings.mapEscapeToCapsLock || settings.mapCapsLockToEscape)
    }

    private var statusColor: Color {
        if !settings.enabled { return .orange }
        if remapper.isRunning { return .green }
        if hidActive { return .green }
        if settings.mapShiftTap, !remapper.isTrusted { return .orange }
        return .orange
    }

    private var statusText: String {
        if !settings.enabled { return text.disabled }
        if remapper.isRunning { return text.running }
        if settings.mapShiftTap, !remapper.isTrusted {
            return hidActive ? text.hidActiveShiftNeedsPermission : text.waitingForPermission
        }
        if hidActive { return text.hidOnlyActive }
        return text.notRunning
    }

    private var statusDetail: String? {
        if !settings.enabled { return nil }
        if remapper.isRunning { return text.runningDetail }
        if settings.mapShiftTap, !remapper.isTrusted {
            return hidActive ? text.hidActiveShiftNeedsPermissionDetail : text.shiftNeedsPermissionDetail
        }
        if hidActive { return text.hidOnlyDetail }
        if let lastError = remapper.lastError { return lastError }
        return nil
    }

    private var text: InterfaceText {
        InterfaceText(appLanguage: settings.language)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: RemapSettings
    @EnvironmentObject private var launchAtLogin: LaunchAtLoginController

    var body: some View {
        Form {
            Section {
                Picker(text.languagePicker, selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.segmented)

                Toggle(text.launchAtLogin, isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)

                if let launchAtLoginError = launchAtLogin.lastError {
                    Text(launchAtLoginError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(text.generalTab)
            } footer: {
                Text(text.generalFooter)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(12)
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

struct InterfaceText {
    let appLanguage: AppLanguage

    var keyboardTab: String { appLanguage == .chinese ? "键盘" : "Keyboard" }
    var generalTab: String { appLanguage == .chinese ? "通用" : "General" }
    var generalFooter: String {
        appLanguage == .chinese
            ? "语言影响本 app 界面文案。开机自启使用系统登录项。"
            : "Language affects this app’s UI. Launch at login uses the system login item."
    }
    var languagePicker: String { appLanguage == .chinese ? "语言" : "Language" }
    var subtitle: String { appLanguage == .chinese ? "短按 Shift 发送目标功能键；支持 ESC / Caps Lock 独立映射。" : "Tap Shift to send the target function key. Optional independent ESC / Caps Lock mappings." }
    var enableMapping: String { appLanguage == .chinese ? "启用键盘映射" : "Enable keyboard mapping" }
    var launchAtLogin: String { appLanguage == .chinese ? "开机自启" : "Launch at login" }
    var capsEscapeSection: String { appLanguage == .chinese ? "ESC / Caps Lock" : "ESC / Caps Lock" }
    var shiftSection: String { appLanguage == .chinese ? "Shift 短按映射" : "Shift tap mapping" }
    var mapShiftTap: String { appLanguage == .chinese ? "Shift 短按映射" : "Shift tap mapping" }
    var mapEscapeToCapsLock: String { appLanguage == .chinese ? "ESC → Caps Lock" : "ESC → Caps Lock" }
    var mapCapsLockToEscape: String { appLanguage == .chinese ? "Caps Lock → ESC" : "Caps Lock → ESC" }
    var capsEscapePermissionNote: String {
        appLanguage == .chinese
            ? "无需辅助功能权限，总开关开启即可生效。"
            : "No Accessibility permission required; works when the master switch is on."
    }
    var shiftPermissionNote: String {
        appLanguage == .chinese
            ? "需要辅助功能权限（CGEventTap）。未授权时不影响上方 ESC / Caps Lock。"
            : "Requires Accessibility (CGEventTap). ESC / Caps Lock above still work without it."
    }
    var capsEscapeTip: String { appLanguage == .chinese ? "两条映射可单独开启，通过系统 HID 层（hidutil）生效，MacBook 内置键盘指示灯会正确跟随。关闭映射或退出 app 时会自动清除。" : "Each mapping can be enabled independently via the system HID layer (hidutil), so MacBook built-in Caps Lock LED follows correctly. Mappings are cleared when disabled or when the app quits." }
    var triggerKey: String { appLanguage == .chinese ? "触发键" : "Trigger key" }
    var targetType: String { appLanguage == .chinese ? "目标类型" : "Target type" }
    var tapSends: String { appLanguage == .chinese ? "短按发送" : "Tap sends" }
    var targetKeyCode: String { appLanguage == .chinese ? "目标按键代码" : "Target key code" }
    var commonKeyCodes: String { appLanguage == .chinese ? "常用：F17 = 64，F18 = 79，F19 = 80，左 Shift = 56，右 Shift = 60。" : "Common values: F17 = 64, F18 = 79, F19 = 80, Left Shift = 56, Right Shift = 60." }
    var holdThreshold: String { appLanguage == .chinese ? "按住判定" : "Hold threshold" }
    var requestPermission: String { appLanguage == .chinese ? "打开辅助功能授权提示" : "Open Accessibility permission prompt" }
    var openInputSourceShortcuts: String { appLanguage == .chinese ? "打开输入法快捷键设置" : "Open Input Source Shortcuts" }
    var inputSourceTip: String { appLanguage == .chinese ? "提示：若要用 F18 切换输入法，请在 macOS 系统设置的键盘快捷键里把“选择上一个输入法”或对应项目设置为 F18。" : "Tip: To use F18 for input source switching, set the corresponding Input Sources keyboard shortcut in macOS System Settings to F18." }
    var running: String { appLanguage == .chinese ? "正在监听键盘事件" : "Listening for keyboard events" }
    var runningDetail: String {
        appLanguage == .chinese
            ? "Shift 短按与 ESC / Caps Lock（若已开启）均可用。"
            : "Shift tap and ESC / Caps Lock (if enabled) are active."
    }
    var waitingForPermission: String { appLanguage == .chinese ? "Shift 等待辅助功能权限" : "Shift needs Accessibility" }
    var hidActiveShiftNeedsPermission: String {
        appLanguage == .chinese ? "ESC / Caps 已生效 · Shift 待授权" : "ESC / Caps active · Shift needs permission"
    }
    var hidActiveShiftNeedsPermissionDetail: String {
        appLanguage == .chinese
            ? "HID 映射无需辅助功能，已在运行。Shift 短按需授予辅助功能后才会监听。"
            : "HID remaps need no Accessibility and are active. Shift tap waits until Accessibility is granted."
    }
    var shiftNeedsPermissionDetail: String {
        appLanguage == .chinese
            ? "仅 Shift 短按需要辅助功能。可先使用 ESC / Caps Lock，或点下方按钮授权。"
            : "Only Shift tap needs Accessibility. You can use ESC / Caps Lock first, or grant permission below."
    }
    var hidOnlyActive: String { appLanguage == .chinese ? "ESC / Caps Lock 映射运行中" : "ESC / Caps Lock remaps active" }
    var hidOnlyDetail: String {
        appLanguage == .chinese
            ? "通过 hidutil 生效，无需辅助功能权限。"
            : "Applied via hidutil; Accessibility is not required."
    }
    var disabled: String { appLanguage == .chinese ? "已停用" : "Disabled" }
    var notRunning: String { appLanguage == .chinese ? "未运行" : "Not running" }
    var settings: String { appLanguage == .chinese ? "设置..." : "Settings..." }
    var about: String { appLanguage == .chinese ? "关于 SwiftKeyShim..." : "About SwiftKeyShim..." }
    var version: String { appLanguage == .chinese ? "版本" : "Version" }
    var repository: String { appLanguage == .chinese ? "开源仓库" : "Open Source Repository" }
    var license: String { appLanguage == .chinese ? "开源协议" : "Open Source License" }
    var restart: String { appLanguage == .chinese ? "重启 SwiftKeyShim" : "Restart SwiftKeyShim" }
    var quit: String { appLanguage == .chinese ? "退出 SwiftKeyShim" : "Quit SwiftKeyShim" }
}

#Preview {
    let settings = RemapSettings()
    ContentView()
        .environmentObject(settings)
        .environmentObject(KeyboardRemapper(settings: settings))
        .environmentObject(LaunchAtLoginController())
}
