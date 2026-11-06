import Flutter
import TrustsyVerify
import UIKit

/// Creates one `FlowPlatformView` per `TrustsyVerifyView` widget.
final class FlowViewFactory: NSObject, FlutterPlatformViewFactory {
    static let viewType = "com.trustsy.verify/flow"

    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        let channel = FlutterMethodChannel(name: "\(Self.viewType)_\(viewId)", binaryMessenger: messenger)
        return MainActor.assumeIsolated { FlowPlatformView(frame: frame, channel: channel, arguments: args) }
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

/// `TrustsyVerifyViewController` inside a platform view, added as a child of
/// the view controller that owns the Flutter view (found up the responder
/// chain once the container is in a window).
///
/// The flow begins on Dart's `start` — sent once Dart is listening — and stays
/// attached until Flutter disposes the view: Flutter takes a platform view out
/// of the hierarchy whenever it is not composited (another route on top), and
/// detaching then would cancel the applicant's run. Exactly one `result` goes back.
@MainActor
final class FlowPlatformView: NSObject, FlutterPlatformView {
    private let container: FlowContainerView
    private let channel: FlutterMethodChannel
    private let arguments: Any?
    private var started = false
    private var done = false
    private var child: UIViewController?

    init(frame: CGRect, channel: FlutterMethodChannel, arguments: Any?) {
        container = FlowContainerView(frame: frame)
        self.channel = channel
        self.arguments = arguments
        super.init()
        container.onWindow = { [weak self] in self?.attachIfReady() }
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "start" else { return result(FlutterMethodNotImplemented) }
            result(nil)
            MainActor.assumeIsolated { self?.begin() }
        }
    }

    nonisolated func view() -> UIView {
        MainActor.assumeIsolated { container }
    }

    private func begin() {
        guard !started else { return }
        started = true
        switch Wire.session(arguments) {
        case let .failure(refused):
            send(refused.wire)
        case let .success(session):
            child = TrustsyVerifyViewController(session: session) { [weak self] result in
                self?.send(Wire.result(result))
            }
            attachIfReady()
        }
    }

    private func attachIfReady() {
        guard let child, child.parent == nil, container.window != nil else { return }
        guard let parent = container.owningViewController() else {
            return send(Wire.error(Wire.noHost, "no view controller owns the Flutter view"))
        }
        parent.addChild(child)
        child.view.frame = container.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(child.view)
        child.didMove(toParent: parent)
    }

    private func send(_ wire: [String: Any?]) {
        guard !done else { return }
        done = true
        channel.invokeMethod("result", arguments: wire)
    }

    deinit {
        channel.setMethodCallHandler(nil)
        // Standard containment teardown. Flutter disposes platform views on the
        // main thread; hop there anyway rather than trust it.
        guard let child else { return }
        Task { @MainActor in
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
    }
}

final class FlowContainerView: UIView {
    var onWindow: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onWindow?() }
    }

    /// The nearest view controller up the responder chain (the Flutter view
    /// controller), else the window's root.
    func owningViewController() -> UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return window?.rootViewController
    }
}
