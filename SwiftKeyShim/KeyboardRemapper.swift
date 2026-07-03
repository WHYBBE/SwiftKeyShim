import ApplicationServices
import Combine
import SwiftUI

@MainActor
final class KeyboardRemapper: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private let settings: RemapSettings
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cancellables = Set<AnyCancellable>()
    private var pendingShiftKeyCode: Int64?
    private var heldShiftKeyCode: Int64?
    private var holdTimer: Timer?

    private static let syntheticEventMarker: Int64 = 0x53575348494D

    init(settings: RemapSettings) {
        self.settings = settings

        settings.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    await Task.yield()
                    self?.restartIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        isTrusted = AXIsProcessTrusted()
        guard settings.enabled else {
            stop()
            return
        }

        guard isTrusted else {
            stop()
            lastError = "需要在系统设置中授予辅助功能权限。"
            return
        }

        stop()

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let remapper = Unmanaged<KeyboardRemapper>.fromOpaque(refcon).takeUnretainedValue()
            return remapper.handle(type: type, event: event)
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
            lastError = "无法创建键盘事件监听。请检查辅助功能/Input Monitoring 权限。"
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

        guard settings.enabled else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

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
