package com.trustsy.verify.flutter

import android.content.Intent
import com.trustsy.verify.TrustsyVerifyContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * `TrustsyVerify.start(session)` → the SDK's own activity through
 * [TrustsyVerifyContract], and the embedded `TrustsyVerifyView` platform view
 * ([FlowViewFactory]). Results go back as [Wire.result] maps.
 *
 * Full screen uses `startActivityForResult` rather than an activity-result
 * registry, so it works under a plain `FlutterActivity` as well.
 */
class TrustsyVerifyPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private var binding: ActivityPluginBinding? = null
    private var pending: MethodChannel.Result? = null
    private val contract = TrustsyVerifyContract()

    override fun onAttachedToEngine(flutter: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutter.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        flutter.platformViewRegistry.registerViewFactory(
            FlowViewFactory.VIEW_TYPE,
            FlowViewFactory(flutter.binaryMessenger) { binding?.activity },
        )
    }

    override fun onDetachedFromEngine(flutter: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "setPushToken") {
            com.trustsy.verify.TrustsyVerify.setPushToken(call.arguments as? String)
            return result.success(null)
        }
        if (call.method != "start") return result.notImplemented()
        if (pending != null) {
            return result.success(Wire.error(Wire.BUSY, "a verification flow is already running"))
        }
        val activity = binding?.activity
            ?: return result.success(Wire.error(Wire.NO_HOST, "no foreground activity"))
        val session = Wire.session(call.arguments).getOrElse {
            return result.success((it as Wire.Refused).wire)
        }
        pending = result
        activity.startActivityForResult(contract.createIntent(activity, session), REQUEST_CODE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pending?.success(Wire.result(contract.parseResult(resultCode, data)))
        pending = null
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        binding?.removeActivityResultListener(this)
        binding = null
    }

    private companion object {
        const val CHANNEL = "com.trustsy.verify"
        const val REQUEST_CODE = 0x7457 // "tW"
    }
}
