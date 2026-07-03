import Foundation

enum ShiftSide: String, CaseIterable, Identifiable {
    case left
    case right
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: "Left Shift"
        case .right: "Right Shift"
        case .both: "Both Shifts"
        }
    }
}

enum TargetKeyMode: String, CaseIterable, Identifiable {
    case preset
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preset: "Preset"
        case .custom: "Custom"
        }
    }
}

struct FunctionKey: Identifiable, Hashable {
    let id: Int64
    let title: String
}

extension FunctionKey {
    static let supported: [FunctionKey] = [
        FunctionKey(id: 64, title: "F17"),
        FunctionKey(id: 79, title: "F18"),
        FunctionKey(id: 80, title: "F19")
    ]
}

@MainActor
final class RemapSettings: ObservableObject {
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Keys.enabled) }
    }

    @Published var shiftSide: ShiftSide {
        didSet { UserDefaults.standard.set(shiftSide.rawValue, forKey: Keys.shiftSide) }
    }

    @Published var targetKeyCode: Int64 {
        didSet { UserDefaults.standard.set(targetKeyCode, forKey: Keys.targetKeyCode) }
    }

    @Published var targetKeyMode: TargetKeyMode {
        didSet { UserDefaults.standard.set(targetKeyMode.rawValue, forKey: Keys.targetKeyMode) }
    }

    @Published var customTargetKeyCodeText: String {
        didSet {
            UserDefaults.standard.set(customTargetKeyCodeText, forKey: Keys.customTargetKeyCodeText)
            if targetKeyMode == .custom, let keyCode = Int64(customTargetKeyCodeText) {
                targetKeyCode = keyCode
            }
        }
    }

    @Published var tapThresholdMilliseconds: Double {
        didSet { UserDefaults.standard.set(tapThresholdMilliseconds, forKey: Keys.tapThresholdMilliseconds) }
    }

    init() {
        enabled = UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true
        let savedSide = UserDefaults.standard.string(forKey: Keys.shiftSide) ?? ShiftSide.left.rawValue
        shiftSide = ShiftSide(rawValue: savedSide) ?? .left
        let savedTarget = UserDefaults.standard.object(forKey: Keys.targetKeyCode) as? Int64
        targetKeyCode = savedTarget ?? 79
        let savedMode = UserDefaults.standard.string(forKey: Keys.targetKeyMode) ?? TargetKeyMode.preset.rawValue
        targetKeyMode = TargetKeyMode(rawValue: savedMode) ?? .preset
        customTargetKeyCodeText = UserDefaults.standard.string(forKey: Keys.customTargetKeyCodeText) ?? "79"
        let savedThreshold = UserDefaults.standard.object(forKey: Keys.tapThresholdMilliseconds) as? Double
        tapThresholdMilliseconds = savedThreshold ?? 160
    }

    func handles(keyCode: Int64) -> Bool {
        switch shiftSide {
        case .left: keyCode == KeyCode.leftShift
        case .right: keyCode == KeyCode.rightShift
        case .both: keyCode == KeyCode.leftShift || keyCode == KeyCode.rightShift
        }
    }

    private enum Keys {
        static let enabled = "enabled"
        static let shiftSide = "shiftSide"
        static let targetKeyCode = "targetKeyCode"
        static let targetKeyMode = "targetKeyMode"
        static let customTargetKeyCodeText = "customTargetKeyCodeText"
        static let tapThresholdMilliseconds = "tapThresholdMilliseconds"
    }
}

enum KeyCode {
    static let leftShift: Int64 = 56
    static let rightShift: Int64 = 60
}
