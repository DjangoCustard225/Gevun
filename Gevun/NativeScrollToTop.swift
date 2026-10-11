import SwiftUI
import UIKit

/// Keep lazy content laid out at each visible offset during a status-bar return to the top.
/// All other scroll delegate messages continue to SwiftUI's original delegate.
struct NativeScrollToTop: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.isUserInteractionEnabled = false
        anchor.isAccessibilityElement = false
        anchor.attach = { [weak coordinator = context.coordinator] view in coordinator?.attach(from: view) }
        return anchor
    }

    func updateUIView(_ view: Anchor, context: Context) {
        view.attach?(view)
    }

    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) {
        view.attach = nil
        coordinator.detach()
    }

    final class Anchor: UIView {
        var attach: ((UIView) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach?(self)
        }
        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            attach?(self)
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            attach?(self)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        private weak var scrollView: UIScrollView?
        private weak var originalDelegate: UIScrollViewDelegate?
        private var displayLink: CADisplayLink?
        private var startOffset = CGPoint.zero
        private var startTime: CFTimeInterval?
        private var duration: CFTimeInterval = 0.45

        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(interrupted),
                name: UIApplication.willResignActiveNotification, object: nil)
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        func attach(from anchor: UIView) {
            guard anchor.window != nil else {
                detach()
                return
            }
            // Layout runs during ordinary scrolling too. Once attached, no hierarchy walk is needed.
            if let scrollView, scrollView.window === anchor.window, scrollView.delegate === self { return }
            var ancestor = anchor.superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    if scrollView !== scroll {
                        detach()
                        scrollView = scroll
                    }
                    if scroll.delegate !== self {
                        cancel()
                        originalDelegate = scroll.delegate
                        scroll.delegate = self
                        scroll.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
                        scroll.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
                    }
                    return
                }
                ancestor = view.superview
            }
        }

        func detach() {
            cancel()
            if let scrollView {
                scrollView.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
                if scrollView.delegate === self { scrollView.delegate = originalDelegate }
            }
            scrollView = nil
            originalDelegate = nil
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if originalDelegate?.responds(to: selector) == true { return originalDelegate }
            return super.forwardingTarget(for: selector)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            originalDelegate?.scrollViewDidScroll?(scrollView)
        }

        func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
            guard originalDelegate?.scrollViewShouldScrollToTop?(scrollView) != false else { return false }
            let top = -scrollView.adjustedContentInset.top
            guard scrollView.contentOffset.y > top + 0.5 else { return true }
            cancel()
            startOffset = scrollView.contentOffset
            scrollView.setContentOffset(startOffset, animated: false)
            if UIAccessibility.isReduceMotionEnabled {
                updateOffset(CGPoint(x: startOffset.x, y: top), in: scrollView)
                originalDelegate?.scrollViewDidScrollToTop?(scrollView)
            } else {
                duration = min(0.65, 0.35 + Double(startOffset.y - top) / 12_000)
                let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
                displayLink = link
                link.add(to: .main, forMode: .common)
            }
            return false
        }

        @objc private func tick(_ link: CADisplayLink) {
            guard let scrollView, scrollView.window != nil, !scrollView.isTracking,
                !scrollView.isDragging, scrollView.window?.windowScene?.activationState == .foregroundActive,
                scrollView.delegate === self
            else {
                cancel()
                return
            }
            if startTime == nil { startTime = link.timestamp }
            let progress = min(1, max(0, (link.targetTimestamp - (startTime ?? link.timestamp)) / duration))
            let fraction = CGFloat((1 - cos(.pi * progress)) / 2)
            let top = -scrollView.adjustedContentInset.top
            let bottom = max(
                top, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
            let y = max(top, min(bottom, startOffset.y + (top - startOffset.y) * fraction))
            updateOffset(CGPoint(x: startOffset.x, y: y), in: scrollView)
            if progress >= 1 {
                cancel()
                originalDelegate?.scrollViewDidScrollToTop?(scrollView)
            }
        }

        private func updateOffset(_ offset: CGPoint, in scrollView: UIScrollView) {
            UIView.performWithoutAnimation {
                scrollView.setContentOffset(offset, animated: false)
                scrollView.setNeedsLayout()
                scrollView.layoutIfNeeded()
            }
        }

        @objc private func panChanged(_ recognizer: UIPanGestureRecognizer) {
            if recognizer.state == .began { cancel() }
        }

        @objc private func interrupted() { cancel() }

        private func cancel() {
            displayLink?.invalidate()
            displayLink = nil
            startTime = nil
        }
    }
}
