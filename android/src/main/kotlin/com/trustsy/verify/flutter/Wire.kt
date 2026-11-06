package com.trustsy.verify.flutter

import com.trustsy.verify.TrustsyResult
import com.trustsy.verify.TrustsyVerify

/** The platform-channel shapes `lib/src/session.dart` and `lib/src/result.dart` read. */
internal object Wire {

    /** A session, or the [TrustsyResult.Error] the native SDK would end with. */
    fun session(args: Any?): Result<TrustsyVerify.Session> {
        val map = args as? Map<*, *> ?: return refused("no session")
        val sealingKey = map["sealingKey"] as? String ?: ""
        val language = map["language"] as? String
        val allowInsecure = map["allowInsecure"] as? Boolean ?: false
        val terminal = terminal(map["terminal"])
        val link = map["link"] as? String
        if (link != null) {
            val session = TrustsyVerify.Session.fromLink(link, sealingKey, language, allowInsecure, terminal)
                ?: return refused("not a trustsy applicant link")
            return Result.success(session)
        }
        val base = map["apiBaseUrl"] as? String ?: return refused("no link or apiBaseUrl")
        val token = map["token"] as? String ?: return refused("no token")
        // The flow itself refuses an unusable origin or token (invalid_link).
        return Result.success(TrustsyVerify.Session(base, token, sealingKey, language, allowInsecure, terminal))
    }

    /** A malformed map becomes a blank terminal, which the SDK refuses as `invalid_chip_key`. */
    private fun terminal(value: Any?): TrustsyVerify.Terminal? {
        val map = value as? Map<*, *> ?: return null
        return TrustsyVerify.Terminal(
            terminalId = map["terminalId"] as? String ?: "",
            chipKey = map["chipKey"] as? String ?: "",
            chipKeyId = (map["chipKeyId"] as? Number)?.toInt() ?: -1,
        )
    }

    fun result(result: TrustsyResult): Map<String, Any?> = when (result) {
        is TrustsyResult.Completed -> mapOf("kind" to "completed", "outcome" to result.outcome.wire)
        TrustsyResult.Cancelled -> mapOf("kind" to "cancelled")
        is TrustsyResult.UnsupportedStep ->
            mapOf("kind" to "unsupported_step", "screen" to result.screen, "state" to result.state)
        is TrustsyResult.Error -> error(result.code, result.message)
    }

    fun error(code: String, message: String): Map<String, Any?> =
        mapOf("kind" to "error", "code" to code, "message" to message)

    /** Carries an error result through [Result.failure]. */
    class Refused(val wire: Map<String, Any?>) : Exception(wire["message"] as? String)

    private fun refused(message: String): Result<TrustsyVerify.Session> =
        Result.failure(Refused(error(TrustsyResult.INVALID_LINK, message)))

    const val HOST_UNSUPPORTED = "host_unsupported"
    const val NO_HOST = "no_host"
    const val BUSY = "busy"
}
