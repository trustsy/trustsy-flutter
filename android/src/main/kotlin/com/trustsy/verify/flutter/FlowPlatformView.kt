package com.trustsy.verify.flutter

import android.app.Activity
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.activity.setViewTreeOnBackPressedDispatcherOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.trustsy.verify.TrustsyVerifyView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Creates one [FlowPlatformView] per `TrustsyVerifyView` widget. */
internal class FlowViewFactory(
    private val messenger: BinaryMessenger,
    private val activity: () -> Activity?,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        FlowPlatformView(context, MethodChannel(messenger, "${VIEW_TYPE}_$viewId"), args, activity)

    companion object {
        const val VIEW_TYPE = "com.trustsy.verify/flow"
    }
}

/**
 * The SDK's [TrustsyVerifyView] inside a platform view. It is created on
 * Dart's `start` — sent once Dart is listening — so a result the flow produces
 * at once is never lost. Exactly one `result` goes back.
 */
internal class FlowPlatformView(
    context: Context,
    private val channel: MethodChannel,
    private val args: Any?,
    private val activity: () -> Activity?,
) : PlatformView, MethodChannel.MethodCallHandler {

    private val container = FrameLayout(context)
    private var started = false
    private var done = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = container

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "start") return result.notImplemented()
        result.success(null)
        if (started) return
        started = true
        begin()
    }

    private fun begin() {
        val host = activity()
            ?: return send(Wire.error(Wire.NO_HOST, "no foreground activity"))
        // Permission requests, the back dispatcher and NFC reader mode all need one.
        if (host !is ComponentActivity) {
            return send(
                Wire.error(
                    Wire.HOST_UNSUPPORTED,
                    "an embedded TrustsyVerifyView needs a ComponentActivity host: " +
                        "make MainActivity extend FlutterFragmentActivity",
                ),
            )
        }
        val session = Wire.session(args).getOrElse { return send((it as Wire.Refused).wire) }
        // The activity's context, not the platform view's: the flow walks its
        // context up to the ComponentActivity. The owners are set explicitly so
        // the composition does not depend on where Flutter parents the view.
        val view = TrustsyVerifyView(host).apply {
            setViewTreeLifecycleOwner(host)
            setViewTreeSavedStateRegistryOwner(host)
            setViewTreeViewModelStoreOwner(host)
            setViewTreeOnBackPressedDispatcherOwner(host)
        }
        container.addView(view, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        view.start(session) { send(Wire.result(it)) }
    }

    private fun send(wire: Map<String, Any?>) {
        if (done) return
        done = true
        channel.invokeMethod("result", wire)
    }

    /** The widget is gone. Removing the view disposes the composition (camera, NFC). */
    override fun dispose() {
        done = true
        channel.setMethodCallHandler(null)
        container.removeAllViews()
    }
}
