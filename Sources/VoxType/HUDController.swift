import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import QuartzCore
import SwiftUI

private enum HUDLayout {
    static let compactSize = NSSize(width: 300, height: 72)

    static func size(for transcript: String) -> NSSize {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return compactSize }
        return NSSize(width: 480, height: transcriptHeight(for: clean) + 80)
    }

    static func transcriptHeight(for transcript: String) -> CGFloat {
        let estimatedLines = transcript
            .split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { total, line in
                total + max(1, Int(ceil(Double(line.count) / 52)))
            }
        let visibleLines = min(max(estimatedLines, 1), 6)
        return 36 + CGFloat(visibleLines * 21)
    }
}

private final class PassiveHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HUDController {
    static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllApplications,
        .canJoinAllSpaces,
        .stationary,
        .ignoresCycle
    ]

    private let model: AppModel
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?
    private var screenChangeTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var targetProcessIdentifier: pid_t?
    private var targetWindow: AXUIElement?

    init(model: AppModel) {
        self.model = model
        let panel = PassiveHUDPanel(
            contentRect: NSRect(origin: .zero, size: HUDLayout.compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = Self.overlayCollectionBehavior
        panel.contentView = NSHostingView(rootView: RecordingHUDView(model: model))
        self.panel = panel

        model.$transcript
            .map(HUDLayout.size(for:))
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] size in
                self?.resize(to: size)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.reposition()
                self.screenChangeTask?.cancel()
                self.screenChangeTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    self?.reposition()
                }
            }
            .store(in: &cancellables)

        reposition()
    }

    private func resize(to size: NSSize) {
        guard panel.frame.size != size else { return }
        panel.setContentSize(size)
        reposition()
    }

    func show(targetProcessIdentifier: pid_t?, targetWindow: AXUIElement?) {
        hideTask?.cancel()
        self.targetProcessIdentifier = targetProcessIdentifier
        self.targetWindow = targetWindow
        reposition()
        let style = model.settings.motionStyle
        let needsEntrance = !panel.isVisible || panel.alphaValue < 0.99
        if needsEntrance {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = style.showDuration
                context.timingFunction = style.timingFunction
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    func hide(after delay: TimeInterval = 0) {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            let style = self.model.settings.motionStyle
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = style.hideDuration
                context.timingFunction = style.timingFunction
                self.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.panel.orderOut(nil)
                }
            })
        }
    }

    private func reposition() {
        let screen = screenContainingTargetWindow()
            ?? NSScreen.main
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        let margin: CGFloat = 12
        let preferredX = visible.midX - panel.frame.width / 2
        let preferredY = visible.minY + 24
        let origin = NSPoint(
            x: clamp(
                preferredX,
                lower: visible.minX + margin,
                upper: visible.maxX - margin - panel.frame.width
            ),
            y: clamp(
                preferredY,
                lower: visible.minY + margin,
                upper: visible.maxY - margin - panel.frame.height
            )
        )
        panel.setFrameOrigin(origin)
    }

    private func screenContainingTargetWindow() -> NSScreen? {
        if let bounds = targetWindowBounds(),
           let screen = screen(withLargestIntersectionWith: bounds) {
            return screen
        }

        guard let targetProcessIdentifier,
              let windowList = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]]
        else {
            return nil
        }

        for window in windowList {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                    == targetProcessIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(
                      dictionaryRepresentation: boundsDictionary as CFDictionary
                  ),
                  bounds.width >= 80,
                  bounds.height >= 60
            else {
                continue
            }

            if let screen = screen(withLargestIntersectionWith: bounds) {
                return screen
            }
        }

        return nil
    }

    private func targetWindowBounds() -> CGRect? {
        guard let targetWindow,
              let position = pointAttribute(kAXPositionAttribute as CFString, of: targetWindow),
              let size = sizeAttribute(kAXSizeAttribute as CFString, of: targetWindow),
              size.width >= 80,
              size.height >= 60
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func screen(withLargestIntersectionWith bounds: CGRect) -> NSScreen? {
        NSScreen.screens
            .compactMap { screen -> (screen: NSScreen, area: CGFloat)? in
                guard let displayID = screen.displayID else { return nil }
                let intersection = CGDisplayBounds(displayID).intersection(bounds)
                guard !intersection.isNull, !intersection.isEmpty else { return nil }
                return (screen, intersection.width * intersection.height)
            }
            .max { $0.area < $1.area }?
            .screen
    }

    private func pointAttribute(_ attribute: CFString, of element: AXUIElement) -> CGPoint? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &rawValue) == .success,
              let rawValue,
              CFGetTypeID(rawValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let value = rawValue as! AXValue
        guard AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ attribute: CFString, of element: AXUIElement) -> CGSize? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &rawValue) == .success,
              let rawValue,
              CFGetTypeID(rawValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let value = rawValue as! AXValue
        guard AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return (lower + upper) / 2 }
        return min(max(value, lower), upper)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value
    }
}

private struct RecordingHUDView: View {
    @ObservedObject var model: AppModel
    @State private var appeared = false

    private var accent: Color {
        switch model.phase {
        case .recording: .red
        case .preparing, .finalizing: .orange
        case .delivering: .blue
        case .idle: .mint
        case .failed: .pink
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if !cleanTranscript.isEmpty {
                GlassEffectContainer {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 4) {
                                transcriptLine
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if model.phase == .recording {
                                    Text(liveHint)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.tertiary)
                                }
                                Color.clear
                                    .frame(height: 1)
                                    .id("transcript-end")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                        }
                        .onAppear {
                            proxy.scrollTo("transcript-end", anchor: .bottom)
                        }
                        .onChange(of: cleanTranscript) { _, _ in
                            proxy.scrollTo("transcript-end", anchor: .bottom)
                        }
                    }
                    .frame(height: HUDLayout.transcriptHeight(for: cleanTranscript))
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            ZStack {
                HStack(spacing: 12) {
                    Circle()
                        .fill(accent.gradient)
                        .frame(width: 8, height: 8)
                    MiniWaveform(
                        meter: model.audioCapture.meter,
                        color: accent,
                        bars: 24,
                        isActive: model.phase == .recording,
                        motionStyle: model.settings.motionStyle
                    )
                    .frame(width: 156, height: 34)
                    TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: model.phase != .recording)) { _ in
                        Text(pillTitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(accent)
                            .frame(minWidth: 52, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background {
                    Capsule()
                        .fill(accent.opacity(0.12))
                    Capsule()
                        .glassEffect(.clear.interactive())
                }

                Button {
                    guard model.phase == .recording else { return }
                    Task { await model.stopRecording() }
                } label: {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.phase != .recording)
                .accessibilityLabel("Stop recording")
            }
            .frame(height: 48)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .scaleEffect(appeared ? 1 : model.settings.motionStyle.appearScale)
        .opacity(appeared ? 1 : 0)
        .animation(model.settings.motionStyle.phaseAnimation, value: appeared)
        .animation(model.settings.motionStyle.phaseAnimation, value: model.phase)
        .onAppear { appeared = true }
    }

    private var pillTitle: String {
        switch model.phase {
        case .recording:
            model.elapsedLabel
        case .preparing:
            model.settings.text("Preparing", "准备中")
        case .finalizing:
            model.settings.text("Finishing", "完成中")
        case .delivering:
            model.settings.text("Sending", "发送中")
        case .failed:
            model.settings.text("Failed", "失败")
        case .idle:
            model.elapsedLabel
        }
    }

    private var cleanTranscript: String {
        model.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanStable: String {
        model.stableTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanDraft: String {
        model.draftTail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var transcriptLine: some View {
        let stable = cleanStable
        let draft = cleanDraft
        let title = Font.system(size: 16, weight: .medium)
        if stable.isEmpty, draft.isEmpty {
            Text(cleanTranscript)
                .font(title)
                .tracking(-0.2)
        } else if draft.isEmpty {
            Text(stable)
                .font(title)
                .tracking(-0.2)
        } else if stable.isEmpty {
            Text(draft)
                .font(title)
                .tracking(-0.2)
                .foregroundStyle(.secondary)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(stable)
                    .font(title)
                    .tracking(-0.2)
                if needsLiveGap(between: stable, and: draft) {
                    Text(" ")
                }
                Text(draft)
                    .font(.system(size: 16, weight: .regular))
                    .tracking(-0.2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func needsLiveGap(between stable: String, and draft: String) -> Bool {
        guard let left = stable.last, let right = draft.first else { return false }
        if left.isWhitespace || right.isWhitespace { return false }
        if " ,.!?:;%)]}，。！？：；％）】》」』、".contains(right) { return false }
        if "([{（【《「『".contains(left) { return false }
        return !isCJK(left) && !isCJK(right)
    }

    private func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F:
                true
            default:
                false
            }
        }
    }

    private var liveHint: String {
        let language = model.settings.dictationLanguage
        if model.refinement.state == .ready {
            return model.settings.text(
                "Live \(language.shortTitle(simplifiedChinese: false)) draft · refined after stop",
                "实时\(language.shortTitle(simplifiedChinese: true))草稿 · 停止后优化"
            )
        }
        return model.settings.text(
            "Live \(language.shortTitle(simplifiedChinese: false)) draft · words lock as they settle",
            "实时\(language.shortTitle(simplifiedChinese: true))草稿 · 说完的词会锁定"
        )
    }
}
