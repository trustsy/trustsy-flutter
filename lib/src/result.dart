/// How a verification run ended (`sdk/contract/native-flow.md` §5). Exactly
/// one per run.
///
/// For your UI only: the decision of record reaches your backend by webhook.
/// Never grant anything on this value alone.
sealed class TrustsyResult {
  const TrustsyResult();

  /// Read what a native plugin sent. Anything unreadable — including a
  /// `completed` with an outcome this version does not know — is
  /// [TrustsyCancelled]: the applicant got no outcome, never a pass.
  static TrustsyResult fromWire(Object? wire) {
    if (wire is! Map) return const TrustsyCancelled();
    String? text(String key) => wire[key] is String ? wire[key] as String : null;
    switch (text('kind')) {
      case 'completed':
        final outcome = TrustsyOutcome.fromWire(text('outcome'));
        return outcome == null ? const TrustsyCancelled() : TrustsyCompleted(outcome);
      case 'unsupported_step':
        return TrustsyUnsupportedStep(text('screen') ?? '', text('state'));
      case 'error':
        return TrustsyError(text('code') ?? TrustsyError.network, text('message') ?? '');
      default:
        return const TrustsyCancelled();
    }
  }
}

/// A terminal screen, or the "submitted" screen the applicant closed.
final class TrustsyCompleted extends TrustsyResult {
  const TrustsyCompleted(this.outcome);

  final TrustsyOutcome outcome;

  @override
  bool operator ==(Object other) => other is TrustsyCompleted && other.outcome == outcome;

  @override
  int get hashCode => outcome.hashCode;

  @override
  String toString() => 'TrustsyCompleted(${outcome.name})';
}

/// The applicant left before handing off.
final class TrustsyCancelled extends TrustsyResult {
  const TrustsyCancelled();

  @override
  bool operator ==(Object other) => other is TrustsyCancelled;

  @override
  int get hashCode => (TrustsyCancelled).hashCode;

  @override
  String toString() => 'TrustsyCancelled()';
}

/// The flow reached a step this SDK version has no native screen for
/// (`signature`, `company`, …). Send the applicant to the web link instead;
/// the server resumes the same step there.
final class TrustsyUnsupportedStep extends TrustsyResult {
  const TrustsyUnsupportedStep(this.screen, this.state);

  /// The screen kind, e.g. `signature`.
  final String screen;

  /// The server's state key, when it has one.
  final String? state;

  @override
  bool operator ==(Object other) =>
      other is TrustsyUnsupportedStep && other.screen == screen && other.state == state;

  @override
  int get hashCode => Object.hash(screen, state);

  @override
  String toString() => 'TrustsyUnsupportedStep($screen, $state)';
}

/// The run could not proceed. [code] is one of the constants below.
final class TrustsyError extends TrustsyResult {
  const TrustsyError(this.code, this.message);

  final String code;
  final String message;

  // The native SDKs' codes (native-flow.md §5).
  static const invalidLink = 'invalid_link';
  static const invalidSealingKey = 'invalid_sealing_key';

  /// The pinned key was rotated out: ship the new one.
  static const sealingKeyRejected = 'sealing_key_rejected';

  /// An answer that did not come from the server.
  static const sealedResponseInvalid = 'sealed_response_invalid';

  /// The device clock is more than 5 minutes off.
  static const clockSkew = 'clock_skew';

  /// 401/404 on the first load: an expired or unknown token.
  static const unauthorized = 'unauthorized';
  static const network = 'network';

  /// [TrustsyTerminal] with a blank id, a chip key that is not 32 base64
  /// bytes, or a key id outside 0–255.
  static const invalidChipKey = 'invalid_chip_key';

  /// The server refused this terminal's card read: the token was not minted
  /// for its terminal id.
  static const terminalNotAuthorized = 'terminal_not_authorized';

  // This plugin's own codes.
  /// [TrustsyVerify.start] while a full-screen run is already open.
  static const busy = 'busy';

  /// No foreground activity / view controller to show the flow from.
  static const noHost = 'no_host';

  /// The host cannot run the flow: a platform other than Android or iOS, or
  /// an embedded [TrustsyVerifyView] on Android under an activity that is not
  /// a `ComponentActivity` (use `FlutterFragmentActivity`).
  static const hostUnsupported = 'host_unsupported';

  @override
  bool operator ==(Object other) => other is TrustsyError && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'TrustsyError($code, $message)';
}

enum TrustsyOutcome {
  approved,
  rejected,
  completed,
  failed,

  /// Submitted; a reviewer decides.
  review;

  /// Null for anything this version does not know.
  static TrustsyOutcome? fromWire(String? value) {
    for (final outcome in values) {
      if (outcome.name == value) return outcome;
    }
    return null;
  }
}
