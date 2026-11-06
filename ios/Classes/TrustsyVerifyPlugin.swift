import Flutter
import TrustsyVerify
import UIKit

/// `TrustsyVerify.start(session)` → `TrustsyVerify.present` over the top view
/// controller, and the embedded `TrustsyVerifyView` platform view
/// (`FlowViewFactory`). Results go back as `Wire.result` maps.
public final class TrustsyVerifyPlugin: NSObject, FlutterPlugin {
    private var running = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.trustsy.verify", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(TrustsyVerifyPlugin(), channel: channel)
        registrar.register(FlowViewFactory(messenger: registrar.messenger()), withId: FlowViewFactory.viewType)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "setPushToken" {
            let token = call.arguments as? String
            // Flutter calls method handlers on the main thread.
            MainActor.assumeIsolated { TrustsyVerify.setPushToken(token) }
            return result(nil)
        }
        guard call.method == "start" else { return result(FlutterMethodNotImplemented) }
        guard !running else {
            return result(Wire.error(Wire.busy, "a verification flow is already running"))
        }
        let session: TrustsyVerifySession
        switch Wire.session(call.arguments) {
        case let .success(value): session = value
        case let .failure(refused): return result(refused.wire)
        }
        // Flutter calls method handlers on the main thread.
        MainActor.assumeIsolated {
            guard let presenter = Self.topViewController() else {
                return result(Wire.error(Wire.noHost, "no view controller to present from"))
            }
            running = true
            TrustsyVerify.present(from: presenter, session: session) { [weak self] outcome in
                self?.running = false
                result(Wire.result(outcome))
            }
        }
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// The platform-channel shapes `lib/src/session.dart` and `lib/src/result.dart` read.
enum Wire {
    static let busy = "busy"
    static let noHost = "no_host"

    struct Refused: Error { let wire: [String: Any?] }

    /// A session, or the error result the native SDK would end with.
    static func session(_ arguments: Any?) -> Swift.Result<TrustsyVerifySession, Refused> {
        guard let args = arguments as? [String: Any] else {
            return .failure(Refused(wire: error("invalid_link", "no session")))
        }
        let sealingKey = args["sealingKey"] as? String ?? ""
        let language = args["language"] as? String
        let allowInsecure = args["allowInsecure"] as? Bool ?? false
        do {
            let terminal = try terminalOf(args["terminal"])
            let session: TrustsyVerifySession
            if let link = args["link"] as? String {
                guard let url = URL(string: link.trimmingCharacters(in: .whitespaces)) else {
                    return .failure(Refused(wire: error("invalid_link", "not a URL")))
                }
                session = try TrustsyVerifySession(link: url, sealingKey: sealingKey, language: language, terminal: terminal)
            } else {
                guard let base = (args["apiBaseUrl"] as? String).flatMap(URL.init(string:)),
                      let token = args["token"] as? String
                else { return .failure(Refused(wire: error("invalid_link", "no link or apiBaseUrl + token"))) }
                session = try TrustsyVerifySession(
                    apiBaseURL: base, token: token, sealingKey: sealingKey, language: language, terminal: terminal)
            }
            // The iOS SDK takes http as given; the Android SDK refuses it unless
            // allowed. Match Android here so the flag means the same on both.
            let scheme = session.apiBaseURL.scheme?.lowercased()
            guard scheme == "https" || (allowInsecure && scheme == "http") else {
                return .failure(Refused(wire: error("invalid_link", "not an https link")))
            }
            return .success(session)
        } catch let invalid as TrustsyVerifyTerminal.Invalid {
            return .failure(Refused(wire: error(invalid.code, "the terminal's chip key or id is not usable")))
        } catch let invalid as TrustsyVerifySession.Invalid {
            return .failure(Refused(wire: error(invalid.code, "the native SDK refused the session")))
        } catch {
            return .failure(Refused(wire: Wire.error("invalid_link", "\(error)")))
        }
    }

    /// `TrustsyTerminal.toWire()`; a malformed map is `invalid_chip_key`, never "no terminal".
    static func terminalOf(_ value: Any?) throws -> TrustsyVerifyTerminal? {
        guard let value, !(value is NSNull) else { return nil }
        guard let map = value as? [String: Any], let id = map["terminalId"] as? String,
              let key = map["chipKey"] as? String, let keyID = (map["chipKeyId"] as? NSNumber)?.intValue,
              let epoch = UInt8(exactly: keyID)
        else { throw TrustsyVerifyTerminal.Invalid.invalidChipKey }
        return try TrustsyVerifyTerminal(terminalID: id, chipKey: key, chipKeyID: epoch)
    }

    static func result(_ result: TrustsyVerifyResult) -> [String: Any?] {
        switch result {
        case let .completed(outcome): return ["kind": "completed", "outcome": outcome.rawValue]
        case .cancelled: return ["kind": "cancelled"]
        case let .unsupportedStep(screen, state): return ["kind": "unsupported_step", "screen": screen, "state": state]
        case let .error(code, message): return error(code, message)
        }
    }

    static func error(_ code: String, _ message: String) -> [String: Any?] {
        ["kind": "error", "code": code, "message": message]
    }
}
