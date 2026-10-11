import SwiftUI
import GevunCore

@MainActor
final class PlayerDismissalMotion: ObservableObject {
    @Published private(set) var offset: CGFloat = 0
    @Published private(set) var fadedOut = false
    private enum Phase { case idle, dragging, returning, dismissing }
    private var phase = Phase.idle
    private var physics = PlayerDismissalPhysics(height: 1000)
    private var dragOrigin: Double = 0
    private var dragDistance: Double = 0
    private var dragOffsetAdjustment: Double = 0
    private var spring: PlayerSpring?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var completion: (() -> Void)?

    var progress: CGFloat { min(1, offset / CGFloat(physics.height * 0.4)) }
    var cornerRadius: CGFloat { 28 * offset / (offset + 60) }

    func resize(height: CGFloat) {
        guard abs(Double(height) - physics.height) > 1 else { return }
        interrupt()
        physics = PlayerDismissalPhysics(height: Double(height))
    }

    func begin(overscroll: CGFloat) {
        guard phase != .dismissing else { return }
        stopAnimation()
        phase = .dragging
        // Transfer any native bounce already drawn before pan recognition into the surface.
        setOffset(Double(offset + max(0, overscroll) * (1 - progress * 0.025)))
        // Offset is the actual rendered position, including an interrupted return spring.
        dragOrigin = physics.distance(for: Double(offset))
        dragDistance = dragOrigin
        dragOffsetAdjustment = Double(offset) - physics.offset(for: dragOrigin)
    }

    func drag(by translation: CGFloat) {
        guard phase == .dragging else { return }
        dragDistance = max(0, dragOrigin + Double(translation))
        setOffset(max(0, physics.offset(for: dragDistance) + dragOffsetAdjustment))
    }

    func shouldDismiss(velocity: CGFloat) -> Bool {
        phase == .dragging && physics.shouldDismiss(offset: Double(offset), velocity: Double(velocity))
    }

    func returnToTop(velocity: CGFloat, reduceMotion: Bool) {
        guard phase == .dragging else { return }
        if reduceMotion || offset == 0 {
            stopAnimation()
            phase = .idle
            setOffset(0)
            return
        }
        phase = .returning
        let screenVelocity = physics.velocity(Double(velocity), at: dragDistance)
        // Keep momentum without allowing the return spring to pass above the screen edge.
        animate(to: 0, velocity: max(-18 * Double(offset), min(3000, screenVelocity)), frequency: 18)
    }

    func dismiss(velocity: CGFloat, reduceMotion: Bool, completion: @escaping () -> Void) {
        guard phase != .dismissing else { return }
        stopAnimation()
        phase = .dismissing
        self.completion = completion
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.15), completionCriteria: .removed) {
                fadedOut = true
            } completion: { [weak self] in
                self?.finishDismissal()
            }
        } else {
            let screenVelocity = physics.velocity(Double(velocity), at: dragDistance)
            let remaining = physics.dismissalTarget - Double(offset)
            animate(to: physics.dismissalTarget, velocity: min(14 * remaining, max(0, screenVelocity)), frequency: 14)
        }
    }

    func interrupt() {
        if phase == .dismissing {
            finishDismissal()
        } else {
            stopAnimation()
            phase = .idle
            setOffset(0)
        }
    }

    func stop() {
        stopAnimation()
        completion = nil
    }

    private func animate(to target: Double, velocity: Double, frequency: Double) {
        stopAnimation()
        spring = PlayerSpring(position: Double(offset), velocity: velocity, target: target, frequency: frequency)
        let target = DisplayLinkTarget(owner: self)
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let elapsed = lastTimestamp.map { link.timestamp - $0 } ?? (link.targetTimestamp - link.timestamp)
        lastTimestamp = link.timestamp
        guard var spring else { return }
        spring.advance(by: max(0, elapsed))
        self.spring = spring
        setOffset(max(0, spring.position))
        if phase == .dismissing && spring.position >= physics.hiddenOffset {
            finishDismissal()
        } else if spring.isSettled {
            stopAnimation()
            phase = .idle
            setOffset(0)
        }
    }

    private func finishDismissal() {
        guard phase == .dismissing else { return }
        stopAnimation()
        phase = .idle
        let action = completion
        completion = nil
        action?()
    }

    private func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        spring = nil
    }

    private func setOffset(_ value: Double) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { offset = CGFloat(value) }
    }

    deinit { displayLink?.invalidate() }
}

@MainActor
private final class DisplayLinkTarget: NSObject {
    private weak var owner: PlayerDismissalMotion?
    init(owner: PlayerDismissalMotion) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}

struct PlayerSurfaceMotion: ViewModifier {
    @ObservedObject var motion: PlayerDismissalMotion
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        content
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: reduceMotion ? 0 : motion.cornerRadius,
                    topTrailingRadius: reduceMotion ? 0 : motion.cornerRadius, style: .continuous)
            )
            .shadow(color: .black.opacity(reduceMotion ? 0 : Double(motion.progress) * 0.24), radius: 16, y: 6)
            .scaleEffect(reduceMotion ? 1 : 1 - motion.progress * 0.025, anchor: .top)
            .offset(y: reduceMotion ? 0 : motion.offset)
            .opacity(motion.fadedOut ? 0 : 1)
    }
}
