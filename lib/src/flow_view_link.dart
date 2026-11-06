import 'package:flutter/services.dart';

import 'result.dart';

/// The platform-view type both native plugins register.
const flowViewType = 'com.trustsy.verify/flow';

/// The Dart end of ONE embedded flow's channel, `com.trustsy.verify/flow_<id>`.
///
/// The native view does not begin the flow until it receives `start`, which is
/// sent only after the result handler is installed — so a result the native
/// side produces immediately (a bad link, an unsupported host) cannot arrive
/// before anyone is listening. The first `result` is delivered; any later one,
/// and any after [close], is dropped.
class FlowViewLink {
  FlowViewLink(int viewId, this._onResult) : _channel = MethodChannel('${flowViewType}_$viewId') {
    _channel.setMethodCallHandler(_handle);
    _channel.invokeMethod<void>('start').catchError((Object _) {
      _deliver(const TrustsyError(TrustsyError.hostUnsupported, 'the native flow view did not answer'));
    });
  }

  final MethodChannel _channel;
  final void Function(TrustsyResult) _onResult;
  bool _done = false;

  Future<void> _handle(MethodCall call) async {
    if (call.method == 'result') _deliver(TrustsyResult.fromWire(call.arguments));
  }

  void _deliver(TrustsyResult result) {
    if (_done) return;
    _done = true;
    _onResult(result);
  }

  /// The widget is gone: stop listening; nothing is delivered after this.
  void close() {
    _done = true;
    _channel.setMethodCallHandler(null);
  }
}
