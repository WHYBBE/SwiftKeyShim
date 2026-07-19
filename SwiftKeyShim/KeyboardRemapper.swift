import ApplicationServices
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

    private static let syntheticEventMarker: Int64 = 0x53575348494D

    init(settings: RemapSettings) {
        self.settings = settings
        self.hidKeyMapper = HIDKeyMapper(settings: settings)

        settings.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    await Task.yield()
                    self?.restartIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        holdTimer?.invalidate()

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func refreshAuthorizationStatus() {
        isTrusted = AXIsProcessTrusted()
        if isTrusted, settings.enabled, !isRunning {
            start()
        }
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
            return
        }

        guard isTrusted else {
            stopEventTapOnly()
            // Only Shift tap needs Accessibility; ESC / Caps Lock already applied above via hidutil.
            lastError = settings.language == .chinese
                ? "Shift 短按需要辅助功能权限；ESC / Caps Lock 映射不受影响。"
                : "Shift tap needs Accessibility; ESC / Caps Lock remaps are unaffected."
            return
        }

        stopEventTapOnly()

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let remapper = Unmanaged<KeyboardRemapper>.fromOpaque(refcon).takeUnretainedValue()

            guard Thread.isMainThread else {
                return Unmanaged.passUnretained(event)
            }

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
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
        isRunning = true
        lastError = nil
    }

    func stop() {
        hidKeyMapper.clearIfNeeded()
        stopEventTapOnly()
    }

    private func stopEventTapOnly() {
        holdTimer?.invalidate()
        holdTimer = nil
        pendingShiftKeyCode = nil
        heldShiftKeyCode = nil

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

    private func restartIfNeeded() {
        if isRunning || settings.enabled {
            start()
        } else {
            hidKeyMapper.clearIfNeeded()
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticEventMarker else {
            return Unmanaged.passUnretained(event)
        }

        guard settings.enabled, settings.mapShiftTap else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Caps Lock / Escape are handled by HIDKeyMapper (hidutil), not CGEventTap.

        if type == .flagsChanged, settings.handles(keyCode: keyCode) {
            let flags = event.flags
            let isShiftDown = flags.contains(.maskShift)

            if isShiftDown && pendingShiftKeyCode == nil && heldShiftKeyCode == nil {
                beginPendingShift(keyCode: keyCode)
                return nil
            }

            if pendingShiftKeyCode == keyCode {
                fireTap(keyCode: settings.targetKeyCode)
                clearPendingShift()
                return nil
            }

            if heldShiftKeyCode == keyCode {
                postShift(keyCode: keyCode, down: false)
                heldShiftKeyCode = nil
                return nil
            }
        }

        if pendingShiftKeyCode != nil, type == .keyDown || type == .flagsChanged {
            promotePendingShiftToHeld()
        }

        return Unmanaged.passUnretained(event)
    }

    private func beginPendingShift(keyCode: Int64) {
        pendingShiftKeyCode = keyCode
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: settings.tapThresholdMilliseconds / 1000, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.promotePendingShiftToHeld() }
        }
    }

    private func clearPendingShift() {
        holdTimer?.invalidate()
        holdTimer = nil
        pendingShiftKeyCode = nil
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
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down)
        event?.flags = down ? .maskShift : []
        post(event)
    }

    private func postKey(keyCode: Int64, down: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down)
        post(event)
    }

    private func post(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        event.post(tap: .cghidEventTap)
    }
}
