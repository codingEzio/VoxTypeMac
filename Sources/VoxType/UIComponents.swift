import SwiftUI

extension MotionStyle {
    var phaseAnimation: Animation {
        switch self {
        case .quiet: .easeOut(duration: 0.22)
        case .liquid: .spring(response: 0.32, dampingFraction: 1)
        case .bright: .spring(response: 0.22, dampingFraction: 0.86)
        }
    }
}

struct StatusDot: View {
    let color: Color
    let isActive: Bool
    var motionStyle: MotionStyle = .liquid
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                paused: !isActive || reduceMotion
            )
        ) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let breath = 1 + 0.18 * sin(seconds * .pi * 2 * motionStyle.breathHertz)

            ZStack {
                if isActive {
                    Circle()
                        .fill(color.opacity(0.16))
                        .frame(width: 16, height: 16)
                        .scaleEffect(reduceMotion ? 1 : breath)
                }
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 18, height: 18)
        }
    }
}

struct MiniWaveform: View {
    let meter: AudioLevelMeter
    let color: Color
    let bars: Int
    let isActive: Bool
    var motionStyle: MotionStyle = .liquid
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DisplayLinkedWaveform(
            meter: meter,
            color: NSColor(color),
            bars: bars,
            isActive: isActive,
            reduceMotion: reduceMotion,
            attackSeconds: motionStyle.attackSeconds,
            releaseSeconds: motionStyle.releaseSeconds
        )
    }
}
