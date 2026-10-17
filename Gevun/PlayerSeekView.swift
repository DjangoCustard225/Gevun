import SwiftUI
import GevunCore

struct PlayerSeekView: View {
    @EnvironmentObject private var player: PlayerStore
    @State private var scrub: Double = 0
    @State private var scrubbing = false
    @State private var scrubPlaybackID: UUID?

    var body: some View {
        let playbackID = player.playbackID
        let isScrubbing = scrubbing && scrubPlaybackID == playbackID
        return HStack(spacing: 10) {
            Text(TimeLabel.clock(isScrubbing ? scrub : player.elapsed)).frame(minWidth: 34)
            MinimalSeekSlider(
                value: isScrubbing ? scrub : player.elapsed, duration: player.canSeek ? player.duration : 0,
                onChange: { if player.playbackID == playbackID { scrub = $0 } },
                onCommit: { if player.playbackID == playbackID { player.seek($0) } }
            ) { editing in
                guard player.playbackID == playbackID else { return }
                if editing {
                    scrub = player.elapsed
                    scrubPlaybackID = playbackID
                    scrubbing = true
                } else {
                    scrubbing = false
                    scrubPlaybackID = nil
                }
            }.id(playbackID).frame(height: 44)
            Text(TimeLabel.clock(player.duration)).frame(minWidth: 34)
        }.font(.caption2).monospacedDigit().foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 8)
            .onChange(of: player.playbackID) { _, _ in
                scrubbing = false
                scrub = 0
                scrubPlaybackID = nil
            }
    }

}

private struct MinimalSeekSlider: UIViewRepresentable {
    let value: Double
    let duration: Double
    var onChange: (Double) -> Void
    var onCommit: (Double) -> Void
    var onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SeekControl {
        let control = SeekControl()
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        control.addTarget(context.coordinator, action: #selector(Coordinator.began), for: .editingDidBegin)
        control.addTarget(context.coordinator, action: #selector(Coordinator.ended(_:)), for: .editingDidEnd)
        return control
    }

    func updateUIView(_ control: SeekControl, context: Context) {
        context.coordinator.parent = self
        control.duration = duration.isFinite ? max(0, duration) : 0
        control.isEnabled = control.duration > 0
        // UIKit can still report isTracking while delivering editingDidEnd. Our own
        // editing flag is already cleared then, so the final actual time must be applied.
        if !control.scrubbing { control.value = min(max(0, value), control.duration) }
    }

    final class Coordinator: NSObject {
        var parent: MinimalSeekSlider
        init(_ parent: MinimalSeekSlider) { self.parent = parent }
        @objc func changed(_ control: SeekControl) { parent.onChange(control.value) }
        @objc func began() { parent.onEditingChanged(true) }
        @objc func ended(_ control: SeekControl) {
            if !control.trackingCancelled { parent.onCommit(control.value) }
            parent.onEditingChanged(false)
        }
    }

    final class SeekControl: UIControl {
        var duration: Double = 0 {
            didSet {
                setNeedsLayout()
                updateAccessibility()
            }
        }
        var value: Double = 0 {
            didSet {
                setNeedsLayout()
                updateAccessibility()
            }
        }
        private(set) var trackingCancelled = false
        private(set) var scrubbing = false
        private let rail = CALayer()
        private let progress = CALayer()
        private let thumb = CALayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            rail.backgroundColor = UIColor.white.withAlphaComponent(0.22).cgColor
            progress.backgroundColor = UIColor.white.withAlphaComponent(0.9).cgColor
            thumb.backgroundColor = UIColor.white.cgColor
            [rail, progress, thumb].forEach(layer.addSublayer)
            isAccessibilityElement = true
            accessibilityIdentifier = "player.seek"
            accessibilityLabel = "Playback position"
            accessibilityTraits = [.adjustable]
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            let height: CGFloat = scrubbing ? 3 : 2
            let fraction = duration > 0 ? min(1, max(0, value / duration)) : 0
            let width = bounds.width * fraction
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            rail.frame = CGRect(x: 0, y: bounds.midY - height / 2, width: bounds.width, height: height)
            progress.frame = CGRect(x: 0, y: rail.frame.minY, width: width, height: height)
            rail.cornerRadius = height / 2
            progress.cornerRadius = height / 2
            thumb.frame = CGRect(
                x: min(max(3.5, width), max(3.5, bounds.width - 3.5)) - 3.5, y: bounds.midY - 3.5, width: 7, height: 7)
            thumb.cornerRadius = 3.5
            thumb.opacity = scrubbing ? 1 : 0
            rail.opacity = isEnabled ? 1 : 0.4
            progress.opacity = rail.opacity
            CATransaction.commit()
        }

        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            guard isEnabled else { return false }
            trackingCancelled = false
            scrubbing = true
            sendActions(for: .editingDidBegin)
            move(to: touch.location(in: self).x)
            return true
        }
        override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            move(to: touch.location(in: self).x)
            return true
        }
        override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
            if let touch { move(to: touch.location(in: self).x) }
            finish()
        }
        override func cancelTracking(with event: UIEvent?) {
            trackingCancelled = true
            finish()
        }
        private func move(to x: CGFloat) {
            value = min(1, max(0, x / max(1, bounds.width))) * duration
            sendActions(for: .valueChanged)
        }
        private func finish() {
            scrubbing = false
            setNeedsLayout()
            sendActions(for: .editingDidEnd)
        }
        private func updateAccessibility() {
            accessibilityValue = "\(TimeLabel.clock(value)) of \(TimeLabel.clock(duration))"
        }
        override func accessibilityIncrement() { adjust(by: 10) }
        override func accessibilityDecrement() { adjust(by: -10) }
        private func adjust(by seconds: Double) {
            guard isEnabled else { return }
            trackingCancelled = false
            sendActions(for: .editingDidBegin)
            value = min(duration, max(0, value + seconds))
            sendActions(for: .valueChanged)
            sendActions(for: .editingDidEnd)
        }
    }
}
