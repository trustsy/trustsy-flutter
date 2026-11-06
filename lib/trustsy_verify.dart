/// trustsy Verify for Flutter.
///
/// Runs a trustsy verification flow — the SAME flow the web verify app runs,
/// built once in the flow builder — with the native Android (Compose) and iOS
/// (SwiftUI) screens. No WebView. Every call is end-to-end sealed to a key your
/// app pins (`sdk/contract/sealed-transport.md`).
///
/// ```dart
/// // link: from your backend (POST /api/v1/cases/{id}/collection-flow-url).
/// // sealingKey: from YOUR build config, never fetched at runtime.
/// final session = TrustsyVerifySession.fromLink(link, sealingKey: trustsySealingKey);
/// final result = await TrustsyVerify.start(session);           // full screen
/// // or, inside your own layout:
/// TrustsyVerifyView(session: session, onResult: (result) { … });
/// ```
///
/// The result is for your UI only. The decision of record reaches your backend
/// by webhook; never grant anything on this result alone.
library;

import 'package:flutter/services.dart';

import 'src/result.dart';
import 'src/session.dart';

export 'src/result.dart';
export 'src/session.dart';
export 'src/view.dart' show TrustsyVerifyView;

class TrustsyVerify {
  TrustsyVerify._();

  static const MethodChannel _channel = MethodChannel('com.trustsy.verify');

  /// Present the flow full-screen and complete when it ends — through the
  /// Android SDK's `TrustsyVerifyContract` activity, or iOS
  /// `TrustsyVerify.present` over the top view controller.
  ///
  /// Never throws: every failure is a [TrustsyError] ([TrustsyError.busy]
  /// while another full-screen run is open).
  /// Hand the native SDK your app's Firebase Cloud Messaging registration token
  /// (`FirebaseMessaging.instance.getToken()` and `onTokenRefresh`), so a message
  /// from the reviewing team can notify the applicant while the app is in the
  /// background. The SDK pairs it with the session while one is active and again
  /// whenever it changes; `null` stops pairing new sessions. The notification
  /// carries no message text. A no-op off Android and iOS.
  static Future<void> setPushToken(String? token) async {
    try {
      await _channel.invokeMethod<void>('setPushToken', token);
    } on MissingPluginException {
      // Not a mobile host: nothing to pair.
    }
  }

  static Future<TrustsyResult> start(TrustsyVerifySession session) async {
    final refusal = session.validate();
    if (refusal != null) return refusal;
    try {
      return TrustsyResult.fromWire(await _channel.invokeMethod<Object?>('start', session.toWire()));
    } on MissingPluginException {
      return const TrustsyError(TrustsyError.hostUnsupported, 'trustsy_verify runs on Android and iOS only');
    } on PlatformException catch (e) {
      return TrustsyError(e.code, e.message ?? '');
    }
  }
}
