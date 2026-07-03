# SwiftKeyShim

一个独立的 macOS SwiftUI 键盘映射小程序，不依赖 Karabiner。

默认行为：短按 Left Shift 发送 F18；按住 Shift 时仍作为正常 Shift 使用。界面里可以改为 Right Shift、Both Shifts，也可以把目标键改成 F17、F18、F19 或自定义 macOS virtual key code。

## 使用

1. 用 Xcode 打开 `SwiftKeyShim.xcodeproj`。
2. 运行 `SwiftKeyShim`。
3. 首次运行时，在系统设置中允许辅助功能权限。
4. 如果要让 F18 切换输入法，在 `系统设置 -> 键盘 -> 键盘快捷键 -> 输入源` 中把对应快捷键设置为 F18。

## 构建

```sh
xcodebuild -project SwiftKeyShim.xcodeproj -scheme SwiftKeyShim -configuration Debug build
```

## 说明

实现使用 macOS `CGEventTap` 拦截键盘事件，并通过 `CGEvent` 发送目标按键事件。代码没有引用 Karabiner 的配置、代码或运行环境。
