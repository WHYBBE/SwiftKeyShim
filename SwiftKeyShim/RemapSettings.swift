import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese: "中文"
        case .english: "English"
        }
    }
}

enum ShiftSide: String, CaseIterable, Identifiable {
    case left
    case right
    case both

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .left: language == .chinese ? "左 Shift" : "Left Shift"
        case .right: language == .chinese ? "右 Shift" : "Right Shift"
        case .both: language == .chinese ? "左右 Shift" : "Both Shift Keys"
        }
    }
}

enum TargetKeyMode: String, CaseIterable, Identifiable {
    case preset
    case custom

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .preset: language == .chinese ? "预设" : "Preset"
        case .custom: language == .chinese ? "自定义" : "Custom"
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
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Keys.enabled) }
    }

    /// Shift tap → target key (F18 etc.)
    @Published var mapShiftTap: Bool {
        didSet { UserDefaults.standard.set(mapShiftTap, forKey: Keys.mapShiftTap) }
    }

    @Published var shiftSide: ShiftSide {
        didSet { UserDefaults.standard.set(shiftSide.rawValue, forKey: Keys.shiftSide) }
    }

    @Published var targetKeyCode: Int64 {
        didSet {
            let keyCode = Self.validKeyCode(targetKeyCode)
            if targetKeyCode != keyCode {
                targetKeyCode = keyCode
                return
            }

            UserDefaults.standard.set(keyCode, forKey: Keys.targetKeyCode)
        }
    }

    @Published var targetKeyMode: TargetKeyMode {
        didSet { UserDefaults.standard.set(targetKeyMode.rawValue, forKey: Keys.targetKeyMode) }
    }

    @Published var customTargetKeyCodeText: String {
        didSet {
            UserDefaults.standard.set(customTargetKeyCodeText, forKey: Keys.customTargetKeyCodeText)
            if targetKeyMode == .custom,
               let keyCode = Int64(customTargetKeyCodeText),
               Self.validKeyCodeRange.contains(keyCode) {
                targetKeyCode = keyCode
            }
        }
    }

    @Published var tapThresholdMilliseconds: Double {
        didSet { UserDefaults.standard.set(tapThresholdMilliseconds, forKey: Keys.tapThresholdMilliseconds) }
    }

    /// ESC → Caps Lock
    @Published var mapEscapeToCapsLock: Bool {
        didSet { UserDefaults.standard.set(mapEscapeToCapsLock, forKey: Keys.mapEscapeToCapsLock) }
    }

    /// Caps Lock → ESC
    @Published var mapCapsLockToEscape: Bool {
        didSet { UserDefaults.standard.set(mapCapsLockToEscape, forKey: Keys.mapCapsLockToEscape) }
    }

    init() {
        let savedLanguage = UserDefaults.standard.string(forKey: Keys.language) ?? AppLanguage.chinese.rawValue
        language = AppLanguage(rawValue: savedLanguage) ?? .chinese
        enabled = UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true
        mapShiftTap = UserDefaults.standard.object(forKey: Keys.mapShiftTap) as? Bool ?? true
        let savedSide = UserDefaults.standard.string(forKey: Keys.shiftSide) ?? ShiftSide.left.rawValue
        shiftSide = ShiftSide(rawValue: savedSide) ?? .left
        let savedTarget = UserDefaults.standard.object(forKey: Keys.targetKeyCode) as? Int64
        let validatedTarget = Self.validKeyCode(savedTarget)
        targetKeyCode = validatedTarget
        if savedTarget != nil, savedTarget != validatedTarget {
            UserDefaults.standard.set(validatedTarget, forKey: Keys.targetKeyCode)
        }
        let savedMode = UserDefaults.standard.string(forKey: Keys.targetKeyMode) ?? TargetKeyMode.preset.rawValue
        targetKeyMode = TargetKeyMode(rawValue: savedMode) ?? .preset
        customTargetKeyCodeText = UserDefaults.standard.string(forKey: Keys.customTargetKeyCodeText) ?? "79"
        let savedThreshold = UserDefaults.standard.object(forKey: Keys.tapThresholdMilliseconds) as? Double
        tapThresholdMilliseconds = savedThreshold ?? 160
        mapEscapeToCapsLock = UserDefaults.standard.object(forKey: Keys.mapEscapeToCapsLock) as? Bool ?? false
        mapCapsLockToEscape = UserDefaults.standard.object(forKey: Keys.mapCapsLockToEscape) as? Bool ?? false
    }

    func handles(keyCode: Int64) -> Bool {
        guard mapShiftTap else { return false }
        switch shiftSide {
        case .left: return keyCode == KeyCode.leftShift
        case .right: return keyCode == KeyCode.rightShift
        case .both: return keyCode == KeyCode.leftShift || keyCode == KeyCode.rightShift
        }
    }

    /// Values that require remapper/HID reconfiguration when they change.
    /// Language, threshold, and target key code are read live and excluded.
    var remapperConfiguration: RemapperConfiguration {
        RemapperConfiguration(
            enabled: enabled,
            mapShiftTap: mapShiftTap,
            shiftSide: shiftSide,
            mapEscapeToCapsLock: mapEscapeToCapsLock,
            mapCapsLockToEscape: mapCapsLockToEscape
        )
    }

    private enum Keys {
        static let language = "language"
        static let enabled = "enabled"
        static let mapShiftTap = "mapShiftTap"
        static let shiftSide = "shiftSide"
        static let targetKeyCode = "targetKeyCode"
        static let targetKeyMode = "targetKeyMode"
        static let customTargetKeyCodeText = "customTargetKeyCodeText"
        static let tapThresholdMilliseconds = "tapThresholdMilliseconds"
        static let mapEscapeToCapsLock = "mapEscapeToCapsLock"
        static let mapCapsLockToEscape = "mapCapsLockToEscape"
    }

    private static let defaultTargetKeyCode: Int64 = 79
    private static let validKeyCodeRange: ClosedRange<Int64> = 0...127

    private static func validKeyCode(_ keyCode: Int64?) -> Int64 {
        guard let keyCode, validKeyCodeRange.contains(keyCode) else {
            return defaultTargetKeyCode
        }

        return keyCode
    }
}

enum KeyCode {
    static let leftShift: Int64 = 56
    static let rightShift: Int64 = 60
    static let capsLock: Int64 = 57
    static let escape: Int64 = 53
}

struct RemapperConfiguration: Equatable {
    var enabled: Bool
    var mapShiftTap: Bool
    var shiftSide: ShiftSide
    var mapEscapeToCapsLock: Bool
    var mapCapsLockToEscape: Bool
}
