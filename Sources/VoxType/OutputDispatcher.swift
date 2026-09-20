import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class OutputDispatcher {
    static let clipboardSettleNanoseconds: UInt64 = 20_000_000

    final class InputTarget {
        let application: NSRunningApplication
        let applicationElement: AXUIElement
        let focusedWindow: AXUIElement?
        let focusedElement: AXUIElement
        let selectedTextRange: CFRange?

        init(
            application: NSRunningApplication,
            applicationElement: AXUIElement,
            focusedWindow: AXUIElement?,
            focusedElement: AXUIElement,
            selectedTextRange: CFRange?
        ) {
            self.application = application
            self.applicationElement = applicationElement
            self.focusedWindow = focusedWindow
            self.focusedElement = focusedElement
            self.selectedTextRange = selectedTextRange
        }
    }

    enum DeliveryError: LocalizedError {
        case accessibilityPermissionMissing
        case emptyTranscript
        case originalInputUnavailable
        case pasteEventUnavailable
        case pasteCouldNotBeConfirmed

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionMissing:
                "Accessibility permission is required to paste into another app. The transcript was left on your clipboard instead."
            case .emptyTranscript:
                "There was no transcript to deliver."
            case .originalInputUnavailable:
                "The original input field is no longer available. The transcript was left on your clipboard instead."
            case .pasteEventUnavailable:
                "\(ProductIdentity.displayName) could not send the paste command. The transcript was left on your clipboard instead."
            case .pasteCouldNotBeConfirmed:
                "\(ProductIdentity.displayName) could not confirm that the paste reached the original input field. The transcript was left on your clipboard instead."
            }
        }
    }

    func captureInputTarget(in application: NSRunningApplication?) -> InputTarget? {
        guard AXIsProcessTrusted(),
              let application,
              !application.isTerminated
        else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let focusedElement = elementAttribute(
            kAXFocusedUIElementAttribute as CFString,
            of: applicationElement
        ) else {
            return nil
        }

        var ownerPID: pid_t = 0
        guard AXUIElementGetPid(focusedElement, &ownerPID) == .success,
              ownerPID == application.processIdentifier
        else {
            return nil
        }

        let focusedWindow = elementAttribute(kAXWindowAttribute as CFString, of: focusedElement)
            ?? elementAttribute(kAXFocusedWindowAttribute as CFString, of: applicationElement)
        return InputTarget(
            application: application,
            applicationElement: applicationElement,
            focusedWindow: focusedWindow,
            focusedElement: focusedElement,
            selectedTextRange: selectedTextRange(of: focusedElement)
        )
    }

    func deliver(
        _ text: String,
        mode: DeliveryMode,
        target: InputTarget?,
        preserveClipboard: Bool,
        pasteDelayMilliseconds: Int
    ) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DeliveryError.emptyTranscript }

        guard mode != .saveOnly else { return }

        if mode == .clipboardOnly {
            writeTextToClipboard(trimmed)
            return
        }

        guard AXIsProcessTrusted() else {
            writeTextToClipboard(trimmed)
            throw DeliveryError.accessibilityPermissionMissing
        }

        guard let target, !target.application.isTerminated else {
            writeTextToClipboard(trimmed)
            throw DeliveryError.originalInputUnavailable
        }

        let oldClipboard = preserveClipboard && mode == .insertOnly
            ? ClipboardSnapshot.capture(from: .general)
            : nil

        let transcriptClipboardChangeCount = writeTextToClipboard(trimmed)
        // Chromium and Electron need one short pasteboard settle before Command-V.
        try? await Task.sleep(nanoseconds: Self.clipboardSettleNanoseconds)

        let alreadyFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
            == target.application.processIdentifier
        if !alreadyFrontmost {
            target.application.activate()
            guard await waitUntilFrontmost(target.application) else {
                throw DeliveryError.originalInputUnavailable
            }
            let fallbackDelay = UInt64(min(max(pasteDelayMilliseconds, 50), 800)) * 1_000_000
            try? await Task.sleep(nanoseconds: fallbackDelay)
        }
        if !restoreFocus(to: target) {
            try? await Task.sleep(nanoseconds: 20_000_000)
            guard restoreFocus(to: target) else {
                throw DeliveryError.originalInputUnavailable
            }
        }
        guard targetIsReadyForPaste(target) else {
            throw DeliveryError.originalInputUnavailable
        }
        let inputTextBeforePaste = stringAttribute(
            kAXValueAttribute as CFString,
            of: target.focusedElement
        )
        guard postPasteKeystroke(to: target.application.processIdentifier) else {
            throw DeliveryError.pasteEventUnavailable
        }
        if let didComplete = await waitForTextChange(
            from: inputTextBeforePaste,
            in: target.focusedElement
        ), !didComplete {
            throw DeliveryError.pasteCouldNotBeConfirmed
        }

        if let oldClipboard, NSPasteboard.general.changeCount == transcriptClipboardChangeCount {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 420_000_000)
                if NSPasteboard.general.changeCount == transcriptClipboardChangeCount {
                    oldClipboard.restore(to: .general)
                }
            }
        }
    }

    func copy(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = writeTextToClipboard(trimmed)
    }

    @discardableResult
    private func writeTextToClipboard(_ text: String) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    private func waitUntilFrontmost(_ application: NSRunningApplication) async -> Bool {
        let deadline = Date().addingTimeInterval(0.8)
        while NSWorkspace.shared.frontmostApplication?.processIdentifier
                != application.processIdentifier {
            guard !application.isTerminated, Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    private func restoreFocus(to target: InputTarget) -> Bool {
        var ownerPID: pid_t = 0
        guard AXUIElementGetPid(target.focusedElement, &ownerPID) == .success,
              ownerPID == target.application.processIdentifier
        else {
            return false
        }

        if let focusedWindow = target.focusedWindow {
            _ = AXUIElementPerformAction(focusedWindow, kAXRaiseAction as CFString)
            _ = AXUIElementSetAttributeValue(
                target.applicationElement,
                kAXFocusedWindowAttribute as CFString,
                focusedWindow
            )
        }

        if !isFocused(target.focusedElement, in: target.applicationElement) {
            guard AXUIElementSetAttributeValue(
                target.focusedElement,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            ) == .success else {
                return false
            }
        }
        guard isFocused(target.focusedElement, in: target.applicationElement) else {
            return false
        }
        restoreSelectedTextRange(for: target)
        return true
    }

    private func targetIsReadyForPaste(_ target: InputTarget) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
            == target.application.processIdentifier
            && isFocused(target.focusedElement, in: target.applicationElement)
    }

    private func isFocused(_ element: AXUIElement, in application: AXUIElement) -> Bool {
        guard let current = elementAttribute(
            kAXFocusedUIElementAttribute as CFString,
            of: application
        ) else {
            return false
        }
        return CFEqual(current, element)
    }

    private func elementAttribute(_ attribute: CFString, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func selectedTextRange(of element: AXUIElement) -> CFRange? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rawValue
        ) == .success,
              let rawValue,
              CFGetTypeID(rawValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let value = rawValue as! AXValue
        guard AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }

    private func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value
        else {
            return nil
        }
        if let string = value as? String { return string }
        return (value as? NSAttributedString)?.string
    }

    private func waitForTextChange(
        from initial: String?,
        in element: AXUIElement
    ) async -> Bool? {
        guard let initial else { return nil }
        let deadline = Date().addingTimeInterval(1)
        repeat {
            try? await Task.sleep(nanoseconds: 30_000_000)
            if let current = stringAttribute(kAXValueAttribute as CFString, of: element),
               current != initial {
                return true
            }
        } while Date() < deadline
        return false
    }

    private func restoreSelectedTextRange(for target: InputTarget) {
        guard var range = target.selectedTextRange,
              let value = AXValueCreate(.cfRange, &range)
        else {
            return
        }
        _ = AXUIElementSetAttributeValue(
            target.focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            value
        )
    }

    private func postPasteKeystroke(to processIdentifier: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        return true
    }
}
