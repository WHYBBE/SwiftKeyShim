import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: RemapSettings
    @EnvironmentObject private var remapper: KeyboardRemapper
    @EnvironmentObject private var launchAtLogin: LaunchAtLoginController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SwiftKeyShim")
                    .font(.largeTitle.bold())
                Text(text.subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker(text.languagePicker, selection: $settings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.segmented)

            Toggle(text.enableMapping, isOn: $settings.enabled)
                .toggleStyle(.switch)

            Toggle(text.launchAtLogin, isOn: launchAtLoginBinding)
                .toggleStyle(.switch)

            if let launchAtLoginError = launchAtLogin.lastError {
                Text(launchAtLoginError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

            Divider()

            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(remapper.isRunning ? .green : .orange)
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 8) {
                    Text(statusText)
                        .font(.headline)
                    if let lastError = remapper.lastError {
                        Text(lastError)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !remapper.isTrusted {
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
            }
            .padding(28)
        }
        .onAppear { remapper.start() }
    }

    private var statusText: String {
        if remapper.isRunning { return text.running }
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

struct InterfaceText {
    let appLanguage: AppLanguage

    var languagePicker: String { appLanguage == .chinese ? "语言" : "Language" }
    var subtitle: String { appLanguage == .chinese ? "短按 Shift 发送目标功能键；按住 Shift 保持正常修饰键行为。" : "Tap Shift to send the target function key. Hold Shift to keep normal modifier behavior." }
    var enableMapping: String { appLanguage == .chinese ? "启用键盘映射" : "Enable keyboard mapping" }
    var launchAtLogin: String { appLanguage == .chinese ? "开机自启" : "Launch at login" }
    var triggerKey: String { appLanguage == .chinese ? "触发键" : "Trigger key" }
    var targetType: String { appLanguage == .chinese ? "目标类型" : "Target type" }
    var tapSends: String { appLanguage == .chinese ? "短按发送" : "Tap sends" }
    var targetKeyCode: String { appLanguage == .chinese ? "目标按键代码" : "Target key code" }
    var commonKeyCodes: String { appLanguage == .chinese ? "常用：F17 = 64，F18 = 79，F19 = 80，左 Shift = 56，右 Shift = 60。" : "Common values: F17 = 64, F18 = 79, F19 = 80, Left Shift = 56, Right Shift = 60." }
    var holdThreshold: String { appLanguage == .chinese ? "按住判定" : "Hold threshold" }
    var requestPermission: String { appLanguage == .chinese ? "打开辅助功能授权提示" : "Open Accessibility permission prompt" }
    var inputSourceTip: String { appLanguage == .chinese ? "提示：若要用 F18 切换输入法，请在 macOS 系统设置的键盘快捷键里把“选择上一个输入法”或对应项目设置为 F18。" : "Tip: To use F18 for input source switching, set the corresponding Input Sources keyboard shortcut in macOS System Settings to F18." }
    var running: String { appLanguage == .chinese ? "正在监听键盘事件" : "Listening for keyboard events" }
    var waitingForPermission: String { appLanguage == .chinese ? "等待辅助功能权限" : "Waiting for Accessibility permission" }
    var disabled: String { appLanguage == .chinese ? "已停用" : "Disabled" }
    var notRunning: String { appLanguage == .chinese ? "未运行" : "Not running" }
    var settings: String { appLanguage == .chinese ? "设置..." : "Settings..." }
    var about: String { appLanguage == .chinese ? "关于 SwiftKeyShim..." : "About SwiftKeyShim..." }
    var version: String { appLanguage == .chinese ? "版本" : "Version" }
    var repository: String { appLanguage == .chinese ? "开源仓库" : "Open Source Repository" }
    var license: String { appLanguage == .chinese ? "开源协议" : "Open Source License" }
    var quit: String { appLanguage == .chinese ? "退出 SwiftKeyShim" : "Quit SwiftKeyShim" }
}

#Preview {
    let settings = RemapSettings()
    ContentView()
        .environmentObject(settings)
        .environmentObject(KeyboardRemapper(settings: settings))
}
