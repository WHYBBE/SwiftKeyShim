# SwiftKeyShim

[English](README.md)

> 由 GPT-5.5 / OpenCode Vibe Coding 而成。

SwiftKeyShim 是一个个人使用的 macOS 菜单栏键盘映射小程序，使用 Swift 和 SwiftUI 构建。它主要服务于我自己的键盘使用习惯，因此只专注于少量明确需求，而不是试图成为通用键盘映射工具。

默认行为：短按左 Shift 发送 F18；按住 Shift 时仍作为正常 Shift 修饰键使用。

![SwiftKeyShim 中文设置预览](docs/preview-zh.png)

## 功能

- 默认短按左 Shift 发送 F18。
- 按住 Shift 时保持正常 Shift 行为。
- 可选择左 Shift、右 Shift 或左右 Shift 作为触发键。
- 可发送 F17、F18、F19，或自定义 macOS virtual key code。
- 可调整短按和按住的判定阈值。
- 可从菜单栏启用或停用映射。
- 映射已启用但 app 未正常监听时，菜单栏图标显示异常状态。
- 支持英文和中文界面切换。
- 支持开机自启。

## 要求

- macOS 15.0 或更高版本。
- 使用 Xcode 从源码构建。
- 需要授予辅助功能权限，用于键盘事件监听和映射。

## 使用

1. 用 Xcode 打开 `SwiftKeyShim.xcodeproj`。
2. 构建并运行 `SwiftKeyShim` scheme。
3. 首次运行时按 macOS 提示授予辅助功能权限，也可以在系统设置中手动开启。
4. 如果要让 F18 切换输入法，在 `系统设置 -> 键盘 -> 键盘快捷键 -> 输入源` 中把对应快捷键设置为 F18。
5. 通过菜单栏图标打开设置、启用或停用映射、配置开机自启，或退出 app。

## 构建

```sh
xcodebuild -project SwiftKeyShim.xcodeproj -scheme SwiftKeyShim -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

## 工作原理

SwiftKeyShim 使用 macOS `CGEventTap` 监听键盘事件。当配置的 Shift 键在短按阈值内按下并松开时，app 会拦截原始 Shift 事件，并通过 `CGEvent` 发送配置的目标按键。当 Shift 按住超过阈值，或与其他按键组合使用时，它会保持正常修饰键行为。

SwiftKeyShim 发送的合成事件会被标记，避免 app 再次映射自己生成的按键事件。

## 说明

- app 作为菜单栏工具运行，不显示 Dock 图标。
- 这是围绕我个人输入法切换习惯制作的个人应用。它可能也适合其他人，但并不打算覆盖所有键盘映射场景。
- 之所以没有继续使用 Karabiner，是因为 Karabiner 功能很强，但对这个小需求来说配置过于复杂；同时我在自己的使用环境中遇到了一些始终没有解决的 bug，也担心潜在的内存泄漏问题。
- 如果映射已启用但缺少辅助功能权限，或键盘事件监听无法运行，菜单栏图标会变为 `keyboard.badge.ellipsis`。
- 开机自启使用 `SMAppService.mainApp`，从 Xcode/DerivedData 运行和安装到 `/Applications` 后运行的行为可能不同。

## 许可证

SwiftKeyShim 使用 [MIT License](LICENSE) 开源。
