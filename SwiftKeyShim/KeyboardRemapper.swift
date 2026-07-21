@preconcurrency import ApplicationServices
import Combine
import SwiftUI

@MainActor
final class KeyboardRemapper: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private let settings: RemapSettings
    private let hidKeyMapper: HIDKeyMapper
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cancellables = Set<AnyCancellable>()
    private var pendingShiftKeyCode: Int64?
    private var heldShiftKeyCode: Int64?
    private var holdTimer: Timer?
    private var accessibilityPollTimer: Timer?
    /// Prevents synthetic posts from re-entering the state machine on the same call stack.
    private var isEmittingSynthetic = false
    /// Last applied mapping config; language / threshold / target key do not touch this.
    private var appliedConfiguration: RemapperConfiguration?

    private static let syntheticEventMarker: Int64 = 0x53575348494D
    /// Device-dependent modifier bits (IOKit NX_DEVICE*SHIFTKEYMASK) for left/right Shift.
    private static let leftShiftDeviceFlag: UInt64 = 0x00000002
    private static let rightShiftDeviceFlag: UInt64 = 0x00000004

    init(settings: RemapSettings) {
        self.settings = settings
        self.hidKeyMapper = HIDKeyMapper(settings: settings)

        settings.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    await Task.yield()
                    self?.applyConfigurationIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    // Cleanup runs via stop() / applicationWillTerminate; deinit cannot touch MainActor state in Swift 6.

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        if isTrusted {
            stopAccessibilityPolling()
            if settings.enabled {
                start()
            }
        } else {
            beginAccessibilityPolling()
        }
    }

    /// Re-check Accessibility and auto-start Shift tap when permission appears.
    func refreshAuthorizationStatus() {
        let wasTrusted = isTrusted
        isTrusted = AXIsProcessTrusted()

        if isTrusted {
            stopAccessibilityPolling()
            if settings.enabled, settings.mapShiftTap, (!isRunning || !wasTrusted) {
                start()
            }
        } else if needsAccessibilityPolling {
            beginAccessibilityPolling()
        } else {
            stopAccessibilityPolling()
        }
    }

    private var needsAccessibilityPolling: Bool {
        settings.enabled && settings.mapShiftTap && !AXIsProcessTrusted()
    }

    private func beginAccessibilityPolling() {
        guard needsAccessibilityPolling else {
            stopAccessibilityPolling()
            return
        }
        guard accessibilityPollTimer == nil else { return }

        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAuthorizationStatus()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        accessibilityPollTimer = timer
    }

    private func stopAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
    }

    func start() {
        isTrusted = AXIsProcessTrusted()
        guard settings.enabled else {
            stop()
            return
        }

        // Caps Lock / Escape: HID-layer remap (handles MacBook built-in LED correctly).
        hidKeyMapper.applyFromSettings()

        // Shift tap needs CGEventTap; skip when that feature is off.
        guard settings.mapShiftTap else {
            stopEventTapOnly()
            lastError = nil
            appliedConfiguration = settings.remapperConfiguration
            return
        }

        guard isTrusted else {
            stopEventTapOnly()
            // Only Shift tap needs Accessibility; ESC / Caps Lock already applied above via hidutil.
            lastError = settings.language == .chinese
                ? "Shift 短按需要辅助功能权限；ESC / Caps Lock 映射不受影响。"
                : "Shift tap needs Accessibility; ESC / Caps Lock remaps are unaffected."
            beginAccessibilityPolling()
            appliedConfiguration = settings.remapperConfiguration
            return
        }

        stopAccessibilityPolling()

        stopEventTapOnly()

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        // Source is on the main run loop, so callbacks are delivered on the main thread.
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let remapper = Unmanaged<KeyboardRemapper>.fromOpaque(refcon).takeUnretainedValue()
            return MainActor.assumeIsolated {
                remapper.handle(type: type, event: event)
            }
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        )

        guard let eventTap else {
            lastError = settings.language == .chinese
                ? "无法创建键盘事件监听。请检查辅助功能和输入监控权限。"
                : "Could not create the keyboard event tap. Check Accessibility and Input Monitoring permissions."
            isRunning = false
            appliedConfiguration = settings.remapperConfiguration
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
        isRunning = true
        lastError = nil
        appliedConfiguration = settings.remapperConfiguration
    }

    func stop() {
        hidKeyMapper.clearIfNeeded()
        stopEventTapOnly()
        appliedConfiguration = settings.remapperConfiguration
    }

    private func stopEventTapOnly() {
        // Release any synthetic held Shift so the OS modifier state cannot stick across restarts.
        resetShiftState(postKeyUpIfNeeded: true)

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        isRunning = false
    }

    private func applyConfigurationIfNeeded() {
        let configuration = settings.remapperConfiguration
        guard configuration != appliedConfiguration else { return }
        restartIfNeeded()
    }

    private func restartIfNeeded() {
        if isRunning || settings.enabled {
            start()
            if needsAccessibilityPolling {
                beginAccessibilityPolling()
            } else if isTrusted || !settings.mapShiftTap || !settings.enabled {
                stopAccessibilityPolling()
            }
        } else {
            hidKeyMapper.clearIfNeeded()
            stopAccessibilityPolling()
            appliedConfiguration = settings.remapperConfiguration
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            // Dropped events while disabled can leave pending/held stuck; recover cleanly.
            resetShiftState(postKeyUpIfNeeded: true)
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventMarker || isEmittingSynthetic {
            return Unmanaged.passUnretained(event)
        }

        guard settings.enabled, settings.mapShiftTap else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Caps Lock / Escape are handled by HIDKeyMapper (hidutil), not CGEventTap.
        // Use per-key device flags (not aggregate .maskShift) so left/right Shift
        // and synthetic posts cannot desync press vs release detection.

        if type == .flagsChanged, settings.handles(keyCode: keyCode) {
            let isDown = isPhysicalShiftDown(keyCode: keyCode, flags: event.flags)

            if isDown {
                // Duplicate down (or already tracking) — swallow, do not re-arm.
                if pendingShiftKeyCode == keyCode || heldShiftKeyCode == keyCode {
                    return nil
                }
                if pendingShiftKeyCode != nil || heldShiftKeyCode != nil {
                    resetShiftState(postKeyUpIfNeeded: true)
                }
                beginPendingShift(keyCode: keyCode)
                return nil
            }

            if pendingShiftKeyCode == keyCode {
                clearPendingShift()
                fireTap(keyCode: settings.targetKeyCode)
                return nil
            }

            if heldShiftKeyCode == keyCode {
                heldShiftKeyCode = nil
                postShift(keyCode: keyCode, down: false)
                return nil
            }

            // Spurious up after recovery — swallow so a bare Shift up cannot leak.
            return nil
        }

        if pendingShiftKeyCode != nil, type == .keyDown || type == .flagsChanged {
            promotePendingShiftToHeld()
        }

        return Unmanaged.passUnretained(event)
    }

    private func isPhysicalShiftDown(keyCode: Int64, flags: CGEventFlags) -> Bool {
        let raw = flags.rawValue
        let leftDown = raw & Self.leftShiftDeviceFlag != 0
        let rightDown = raw & Self.rightShiftDeviceFlag != 0

        switch keyCode {
        case KeyCode.leftShift:
            if leftDown { return true }
            if rightDown { return false }
        case KeyCode.rightShift:
            if rightDown { return true }
            if leftDown { return false }
        default:
            return flags.contains(.maskShift)
        }

        // No per-key device bits: release clears aggregate maskShift; any set mask is still down.
        return flags.contains(.maskShift)
    }

    private func beginPendingShift(keyCode: Int64) {
        pendingShiftKeyCode = keyCode
        holdTimer?.invalidate()
        let timer = Timer(timeInterval: settings.tapThresholdMilliseconds / 1000, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.promotePendingShiftToHeld() }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func clearPendingShift() {
        holdTimer?.invalidate()
        holdTimer = nil
        pendingShiftKeyCode = nil
    }

    private func resetShiftState(postKeyUpIfNeeded: Bool) {
        let held = heldShiftKeyCode
        clearPendingShift()
        heldShiftKeyCode = nil
        if postKeyUpIfNeeded, let held {
            postShift(keyCode: held, down: false)
        }
    }

    private func promotePendingShiftToHeld() {
        guard let keyCode = pendingShiftKeyCode else { return }
        clearPendingShift()
        heldShiftKeyCode = keyCode
        postShift(keyCode: keyCode, down: true)
    }

    private func fireTap(keyCode: Int64) {
        postKey(keyCode: keyCode, down: true)
        postKey(keyCode: keyCode, down: false)
    }

    private func postShift(keyCode: Int64, down: Bool) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down)
        event?.flags = down ? .maskShift : []
        post(event)
    }

    private func postKey(keyCode: Int64, down: Bool) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down)
        post(event)
    }

    private func post(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        isEmittingSynthetic = true
        defer { isEmittingSynthetic = false }
        // Session-level post keeps userData and avoids HID re-injection races with our FSM.
        event.post(tap: .cgAnnotatedSessionEventTap)
    }
}
