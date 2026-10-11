import SwiftUI
import Combine

/// A separate window isolates player rendering while leaving the native tab accessory mounted.
struct PlayerPresentation: UIViewControllerRepresentable {
    let store: AppStore
    let isPresented: Bool
    let reduceMotion: Bool

    func makeUIViewController(context: Context) -> PlayerPresenterController {
        PlayerPresenterController(store: store)
    }

    func updateUIViewController(_ controller: PlayerPresenterController, context: Context) {
        controller.setPresented(isPresented, reduceMotion: reduceMotion)
    }

    static func dismantleUIViewController(_ controller: PlayerPresenterController, coordinator: ()) {
        controller.invalidate()
    }
}

@MainActor
final class PlayerPresenterController: UIViewController {
    private let store: AppStore
    private var wantsPresentation = false
    private var reduceMotion = false
    private var playerController: PlayerSurfaceController?
    private var playerWindow: UIWindow?
    private var presentationSubscription: AnyCancellable?

    init(store: AppStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
        // UIKit owns the window lifetime directly, including closes initiated from the queue sheet.
        presentationSubscription = store.player.$expanded.removeDuplicates()
            .receive(on: RunLoop.main).sink { [weak self] expanded in
                self?.setPresented(expanded, reduceMotion: UIAccessibility.isReduceMotionEnabled)
            }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        synchronizePresentation()
    }

    func setPresented(_ presented: Bool, reduceMotion: Bool) {
        wantsPresentation = presented
        self.reduceMotion = reduceMotion
        synchronizePresentation()
    }

    func invalidate() {
        presentationSubscription?.cancel()
        presentationSubscription = nil
        setPresented(false, reduceMotion: true)
    }

    private func synchronizePresentation() {
        if wantsPresentation {
            guard playerController == nil, isViewLoaded, let window = view.window,
                let scene = window.windowScene, presentedViewController == nil
            else { return }
            window.endEditing(true)
            let controller = PlayerSurfaceController(
                store: store, safeAreaInsets: window.safeAreaInsets,
                reduceMotion: reduceMotion)
            let overlay = UIWindow(windowScene: scene)
            overlay.frame = window.frame
            overlay.windowLevel = UIWindow.Level(rawValue: window.windowLevel.rawValue + 1)
            overlay.overrideUserInterfaceStyle = .dark
            overlay.backgroundColor = .clear
            overlay.isOpaque = false
            overlay.rootViewController = controller
            playerController = controller
            playerWindow = overlay
            // Show without taking key status or changing the main interface's presentation lifecycle.
            overlay.isHidden = false
            controller.view.layoutIfNeeded()
            controller.animateEntrance(reduceMotion: reduceMotion)
        } else if let overlay = playerWindow {
            // The tab accessory never left the main window, so there is no restore/rebuild transition.
            overlay.isHidden = true
            overlay.rootViewController = nil
            playerController = nil
            playerWindow = nil
        }
    }

}

@MainActor
private final class PlayerSurfaceController: UIViewController, UIGestureRecognizerDelegate {
    private let store: AppStore
    private let motion = PlayerDismissalMotion()
    private lazy var host = UIHostingController(rootView: playerRootView())
    private lazy var pull = UIPanGestureRecognizer(target: self, action: #selector(handlePull(_:)))
    private var pullOrigin: CGFloat = 0
    private var pullActive = false
    private var closing = false
    private var entering = true
    private var lifecycleSubscriptions = Set<AnyCancellable>()
    private var safeAreaInsets: UIEdgeInsets
    private let reduceMotion: Bool

    init(store: AppStore, safeAreaInsets: UIEdgeInsets, reduceMotion: Bool) {
        self.store = store
        self.safeAreaInsets = safeAreaInsets
        self.reduceMotion = reduceMotion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.accessibilityViewIsModal = true

        addChild(host)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.isUserInteractionEnabled = false
        // Only the player moves; the live tab interface stays mounted in the main window.
        if reduceMotion {
            host.view.alpha = 0
        } else {
            host.view.transform = CGAffineTransform(translationX: 0, y: view.bounds.height)
        }
        view.addSubview(host.view)
        host.didMove(toParent: self)
        pull.maximumNumberOfTouches = 1
        pull.cancelsTouchesInView = true
        pull.delaysTouchesBegan = false
        pull.delegate = self
        host.view.addGestureRecognizer(pull)

        NotificationCenter.default.publisher(for: UIScene.willDeactivateNotification)
            .receive(on: RunLoop.main).sink { [weak self] notification in
                guard let self, let scene = notification.object as? UIScene,
                    scene === self.view.window?.windowScene
                else { return }
                self.motion.interrupt()
                self.pull.isEnabled = false
            }.store(in: &lifecycleSubscriptions)
        NotificationCenter.default.publisher(for: UIScene.didActivateNotification)
            .receive(on: RunLoop.main).sink { [weak self] notification in
                guard let self, let scene = notification.object as? UIScene,
                    scene === self.view.window?.windowScene
                else { return }
                self.pull.isEnabled = !self.closing
            }.store(in: &lifecycleSubscriptions)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        guard view.window != nil, safeAreaInsets != view.safeAreaInsets else { return }
        safeAreaInsets = view.safeAreaInsets
        host.rootView = playerRootView()
    }

    func animateEntrance(reduceMotion: Bool) {
        UIView.animate(
            withDuration: reduceMotion ? 0.15 : 0.42, delay: 0,
            usingSpringWithDamping: 1, initialSpringVelocity: 0,
            options: [.beginFromCurrentState]
        ) {
            self.host.view.transform = .identity
            self.host.view.alpha = 1
        } completion: { _ in
            self.entering = false
            self.host.view.isUserInteractionEnabled = true
        }
    }

    private func playerRootView() -> HostedPlayerView {
        HostedPlayerView(
            store: store, safeAreaInsets: EdgeInsets(safeAreaInsets), motion: motion,
            onClose: { [weak self] velocity in self?.close(velocity: velocity) })
    }

    private func close(velocity: CGFloat) {
        guard !closing else { return }
        closing = true
        pullActive = false
        host.view.isUserInteractionEnabled = false
        motion.dismiss(velocity: velocity, reduceMotion: UIAccessibility.isReduceMotionEnabled) { [weak self] in
            self?.store.player.expanded = false
        }
    }

    @objc private func handlePull(_ recognizer: UIPanGestureRecognizer) {
        guard !closing else { return }
        let space = view.window
        let translation = recognizer.translation(in: space).y
        switch recognizer.state {
        case .began:
            pullOrigin = translation
            pullActive = true
            motion.begin(overscroll: 0)
        case .changed:
            guard pullActive else { return }
            motion.drag(by: translation - pullOrigin)
        case .ended:
            guard pullActive else { return }
            pullActive = false
            motion.drag(by: translation - pullOrigin)
            let velocity = recognizer.velocity(in: space).y
            if motion.shouldDismiss(velocity: velocity) {
                close(velocity: velocity)
            } else {
                motion.returnToTop(velocity: velocity, reduceMotion: UIAccessibility.isReduceMotionEnabled)
            }
        case .cancelled, .failed:
            guard pullActive else { return }
            pullActive = false
            motion.returnToTop(velocity: 0, reduceMotion: UIAccessibility.isReduceMotionEnabled)
        default: break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard !entering, !closing, !pullActive, presentedViewController == nil,
            host.presentedViewController == nil
        else { return false }
        var ancestor = touch.view
        while let view = ancestor {
            // Seeking owns its complete touch sequence, including vertical drift.
            if view.accessibilityIdentifier == "player.seek" { return false }
            if view === host.view { break }
            ancestor = view.superview
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard !entering, !closing, presentedViewController == nil,
            host.presentedViewController == nil,
            view.window?.windowScene?.activationState == .foregroundActive
        else { return false }
        let movement = pull.translation(in: view.window)
        return movement.y > 0 && movement.y > abs(movement.x) * 1.15
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // SwiftUI button recognizers must not prevent a downward pull across their hit areas.
        true
    }
}

private extension EdgeInsets {
    init(_ insets: UIEdgeInsets) {
        self.init(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
    }
}

struct HostedPlayerView: View {
    let store: AppStore
    let safeAreaInsets: EdgeInsets
    let motion: PlayerDismissalMotion
    let onClose: (CGFloat) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var interface: PlaybackInterfaceState
    @ObservedObject private var appearance: ArtworkAppearance

    init(
        store: AppStore, safeAreaInsets: EdgeInsets, motion: PlayerDismissalMotion,
        onClose: @escaping (CGFloat) -> Void
    ) {
        self.store = store
        self.safeAreaInsets = safeAreaInsets
        self.motion = motion
        self.onClose = onClose
        _interface = ObservedObject(wrappedValue: store.player.interface)
        _appearance = ObservedObject(wrappedValue: store.appearance)
    }

    var body: some View {
        NowPlayingView(safeAreaInsets: safeAreaInsets, motion: motion, onClose: onClose)
            .environment(store).environmentObject(store.player).environmentObject(appearance)
            .environmentObject(store.player.interface)
            .environment(\.appTheme, appearance.theme).environment(\.colorScheme, .dark)
            .tint(appearance.theme.accent).ignoresSafeArea()
            .task(id: "\(store.sessionID):\(interface.current?.coverArt ?? "")") {
                await appearance.update(
                    coverArt: interface.current?.coverArt, api: store.api,
                    cache: store.artwork, reduceMotion: reduceMotion)
            }
    }
}
