import CoreGraphics
import Foundation

final class GlobalHotkeyMonitor {
    static let rightCommandKeyCode = CGKeyCode(54)
    static let tapBounceGuardSeconds: CFTimeInterval = 0.09

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifierIsDown = false
    private var candidateTap = false
    private var usedAsChord = false
    private var pressedAt: CFTimeInterval = 0
    private var lastToggleAt: CFTimeInterval = 0
    private var swallowedChordKey = false
    private var canSwallowEvents = false

    var shortcut = DictationShortcut.default
    var onToggle: (@Sendable () -> Void)?

    var isRunning: Bool { eventTap != nil }

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            if monitor.handle(type: type, event: event) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        let activeTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: pointer
        )
        let tap = activeTap ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: pointer
        )
        guard let tap else { return false }

        canSwallowEvents = activeTap != nil
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        canSwallowEvents = false
        resetCandidate()
        swallowedChordKey = false
    }

    @discardableResult
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return false
        }

        if shortcut.isModifierTap {
            handleModifierTap(type: type, event: event)
            return false
        }
        return handleChord(type: type, event: event)
    }

    private func handleModifierTap(type: CGEventType, event: CGEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        if modifierIsDown, now - pressedAt > 2 {
            resetCandidate()
            modifierIsDown = false
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let trigger = shortcut.triggerKeyCode

        if type == .flagsChanged, keyCode == trigger {
            if !modifierIsDown {
                modifierIsDown = true
                candidateTap = true
                usedAsChord = false
                pressedAt = now
                return
            }

            modifierIsDown = false
            let duration = now - pressedAt
            let isCleanTap = candidateTap && !usedAsChord && duration <= 0.8
            let isDebounced = now - lastToggleAt >= Self.tapBounceGuardSeconds
            if isCleanTap, isDebounced {
                lastToggleAt = now
                onToggle?()
            }
            resetCandidate()
            return
        }

        guard modifierIsDown, candidateTap else { return }

        if type == .keyDown || type == .keyUp {
            usedAsChord = true
        } else if type == .flagsChanged, keyCode != trigger {
            usedAsChord = true
        }
    }

    private func handleChord(type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let trigger = shortcut.triggerKeyCode
        let flags = event.flags
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if type == .keyDown, keyCode == trigger, shortcut.matchesChord(flags: flags) {
            if isRepeat {
                return canSwallowEvents
            }
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastToggleAt >= Self.tapBounceGuardSeconds {
                lastToggleAt = now
                swallowedChordKey = true
                onToggle?()
            }
            return canSwallowEvents
        }

        if type == .keyUp, keyCode == trigger, swallowedChordKey || shortcut.matchesChord(flags: flags) {
            swallowedChordKey = false
            return canSwallowEvents
        }

        return false
    }

    private func resetCandidate() {
        candidateTap = false
        usedAsChord = false
        pressedAt = 0
    }
}
