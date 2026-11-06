import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'flow_view_link.dart';
import 'result.dart';
import 'session.dart';

/// The verification flow embedded in your widget tree — the native screens in
/// a platform view, sized by its parent. It asks for camera, location and NFC
/// itself, and calls [onResult] exactly once.
///
/// Android: the host activity must be a `ComponentActivity`. `FlutterActivity`
/// is not one; make `MainActivity` extend `FlutterFragmentActivity`, or the
/// view ends with [TrustsyError.hostUnsupported]. (Full-screen
/// [TrustsyVerify.start] works under either.) It is a hybrid-composition
/// platform view, so the camera previews render.
///
/// iOS: the native view controller is added as a child of the Flutter view
/// controller.
///
/// The session is read once. To run another, give the widget a new [Key].
/// Removing the widget before the flow ends delivers nothing.
class TrustsyVerifyView extends StatefulWidget {
  const TrustsyVerifyView({super.key, required this.session, required this.onResult});

  final TrustsyVerifySession session;
  final ValueChanged<TrustsyResult> onResult;

  @override
  State<TrustsyVerifyView> createState() => _TrustsyVerifyViewState();
}

class _TrustsyVerifyViewState extends State<TrustsyVerifyView> {
  FlowViewLink? _link;
  late final TrustsyError? _refusal = widget.session.validate() ?? _platformRefusal();

  static TrustsyError? _platformRefusal() =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)
          ? null
          : const TrustsyError(TrustsyError.hostUnsupported, 'trustsy_verify runs on Android and iOS only');

  @override
  void initState() {
    super.initState();
    final refusal = _refusal;
    if (refusal != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onResult(refusal);
      });
    }
  }

  void _created(int id) {
    if (!mounted) return;
    _link = FlowViewLink(id, (result) {
      if (mounted) widget.onResult(result);
    });
  }

  @override
  void dispose() {
    _link?.close();
    super.dispose();
  }

  // Every touch belongs to the native screens (text fields, scrolling, buttons).
  static final _gestures = <Factory<OneSequenceGestureRecognizer>>{
    Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
  };

  @override
  Widget build(BuildContext context) {
    if (_refusal != null) return const SizedBox.expand();
    final params = widget.session.toWire();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: flowViewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: _gestures,
        onPlatformViewCreated: _created,
      );
    }
    return PlatformViewLink(
      viewType: flowViewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: _gestures,
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
      onCreatePlatformView: (creation) => PlatformViewsService.initExpensiveAndroidView(
        id: creation.id,
        viewType: flowViewType,
        layoutDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onFocus: () => creation.onFocusChanged(true),
      )
        ..addOnPlatformViewCreatedListener(creation.onPlatformViewCreated)
        ..addOnPlatformViewCreatedListener(_created)
        ..create(),
    );
  }
}
