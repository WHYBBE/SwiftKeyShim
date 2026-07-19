import Foundation

/// Applies Caps Lock / Escape remaps via macOS `hidutil` UserKeyMapping.
/// This runs at the HID layer, so MacBook built-in Caps Lock LED follows correctly.
/// Shift tap-mapping stays in CGEventTap (KeyboardRemapper).
@MainActor
final class HIDKeyMapper {
    /// HID usage page Keyboard/Keypad (0x07) + usage, as used by hidutil.
    private static let keyboardPageBase: UInt64 = 0x700000000
    private static let usageEscape: UInt64 = 0x29
    private static let usageCapsLock: UInt64 = 0x39

    private let settings: RemapSettings
    private var lastAppliedSignature: String?

    init(settings: RemapSettings) {
        self.settings = settings
    }

    func applyFromSettings() {
        guard settings.enabled else {
            clearIfNeeded()
            return
        }

        var pairs: [(src: UInt64, dst: UInt64)] = []

        if settings.mapCapsLockToEscape {
            pairs.append((Self.keyboardPageBase | Self.usageCapsLock,
                          Self.keyboardPageBase | Self.usageEscape))
        }
        if settings.mapEscapeToCapsLock {
            pairs.append((Self.keyboardPageBase | Self.usageEscape,
                          Self.keyboardPageBase | Self.usageCapsLock))
        }

        apply(pairs: pairs)
    }

    func clearIfNeeded() {
        apply(pairs: [])
    }

    private func apply(pairs: [(src: UInt64, dst: UInt64)]) {
        let signature = pairs
            .map { "\($0.src)->\($0.dst)" }
            .sorted()
            .joined(separator: ",")

        if signature == lastAppliedSignature {
            return
        }

        let mappingArray: [[String: UInt64]] = pairs.map { pair in
            [
                "HIDKeyboardModifierMappingSrc": pair.src,
                "HIDKeyboardModifierMappingDst": pair.dst
            ]
        }

        let payload: [String: Any] = ["UserKeyMapping": mappingArray]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", json]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                lastAppliedSignature = signature
            }
        } catch {
            // Keep lastAppliedSignature so we retry next time settings change.
            lastAppliedSignature = nil
        }
    }
}
