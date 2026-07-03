import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: RemapSettings
    @EnvironmentObject private var remapper: KeyboardRemapper

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SwiftKeyShim")
                    .font(.largeTitle.bold())
                Text("短按 Shift 发送目标功能键；按住 Shift 保持正常修饰键行为。")
                    .foregroundStyle(.secondary)
            }

            Toggle("启用键盘映射", isOn: $settings.enabled)
                .toggleStyle(.switch)

            Picker("触发键", selection: $settings.shiftSide) {
                ForEach(ShiftSide.allCases) { side in
                    Text(side.title).tag(side)
                }
            }
            .pickerStyle(.segmented)

            Picker("目标类型", selection: $settings.targetKeyMode) {
                ForEach(TargetKeyMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if settings.targetKeyMode == .preset {
                Picker("短按发送", selection: $settings.targetKeyCode) {
                    ForEach(FunctionKey.supported) { key in
                        Text(key.title).tag(key.id)
                    }
                }
            } else {
                TextField("目标 key code", text: $settings.customTargetKeyCodeText)
                    .textFieldStyle(.roundedBorder)
                Text("常用：F17 = 64，F18 = 79，F19 = 80，左 Shift = 56，右 Shift = 60。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading) {
                HStack {
                    Text("按住判定")
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
                    }
                    if !remapper.isTrusted {
                        Button("打开辅助功能授权提示") {
                            remapper.requestAccessibilityPermission()
                        }
                    }
                }
            }

            Text("提示：若要用 F18 切换输入法，请在 macOS 系统设置的键盘快捷键里把“选择上一个输入法”或对应项目设置为 F18。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .onAppear { remapper.start() }
    }

    private var statusText: String {
        if remapper.isRunning { return "正在监听键盘事件" }
        if !remapper.isTrusted { return "等待辅助功能权限" }
        if !settings.enabled { return "已停用" }
        return "未运行"
    }
}

#Preview {
    let settings = RemapSettings()
    ContentView()
        .environmentObject(settings)
        .environmentObject(KeyboardRemapper(settings: settings))
}
