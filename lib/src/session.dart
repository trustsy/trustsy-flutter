import 'result.dart';

/// What a verification run needs: where the flow's API lives, the applicant's
/// bearer token, and the server key every call is sealed to
/// (`sdk/contract/sealed-transport.md`).
///
/// Build it from the applicant link your backend got from
/// `POST /api/v1/cases/{id}/collection-flow-url` ([TrustsyVerifySession.fromLink]),
/// or from an API origin plus a token from `POST /api/v1/cases/{id}/tokens`.
///
/// The native SDKs own link parsing and the key check; [validate] only refuses
/// what can be refused without them, so a bad session still reaches the host as
/// a [TrustsyError] result rather than as an exception.
class TrustsyVerifySession {
  /// A token your backend minted. [apiBaseUrl] is the origin; every call is
  /// sealed to `{apiBaseUrl}/api/v1/sealed`.
  TrustsyVerifySession({
    required String this.apiBaseUrl,
    required String this.token,
    required this.sealingKey,
    this.language,
    this.allowInsecure = false,
    this.terminal,
  }) : link = null {
    _checkLanguage(language);
  }

  /// The applicant link: `https://…/u/<code>` or `https://…/verify?token=<uuid>`.
  /// `/resume/…` handoff links are refused by the native SDKs (`invalid_link`).
  TrustsyVerifySession.fromLink(
    String this.link, {
    required this.sealingKey,
    this.language,
    this.allowInsecure = false,
    this.terminal,
  })  : apiBaseUrl = null,
        token = null {
    _checkLanguage(language);
  }

  /// Set by [TrustsyVerifySession.fromLink]; null otherwise.
  final String? link;

  /// Set by the default constructor; null for a link session.
  final String? apiBaseUrl;

  /// The applicant token (a UUID). Travels only inside the sealed envelope;
  /// never log it.
  final String? token;

  /// The server's key config (base64url, 39 bytes). Pin it in your app's
  /// build config; NEVER fetch it at runtime — a key fetched over an
  /// intercepted channel is the interceptor's key.
  final String sealingKey;

  /// `en` or `th`. Null = the link's language, else the device's.
  final String? language;

  /// Accept an `http://` origin. Local development only; a release build must
  /// not set it.
  final bool allowInsecure;

  /// Set when this device is a partner terminal with a USB card reader (the
  /// dip-chip step); without it that step ends with [TrustsyUnsupportedStep].
  final TrustsyTerminal? terminal;

  static const _languages = {'en', 'th'};

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static void _checkLanguage(String? language) {
    if (language != null && !_languages.contains(language)) {
      throw ArgumentError.value(language, 'language', 'must be "en", "th" or null');
    }
  }

  /// The error this session would end with before any network call, or null.
  ///
  /// [TrustsyError.invalidLink] for an origin that is not `https` (or `http`
  /// with [allowInsecure]), or a token that is not a UUID;
  /// [TrustsyError.invalidSealingKey] for an empty key. Everything else — the
  /// link's path, the key's bytes — is checked natively.
  TrustsyError? validate() {
    final origin = link ?? apiBaseUrl!;
    if (!_usableOrigin(origin)) {
      return const TrustsyError(TrustsyError.invalidLink, 'not an https link');
    }
    if (link == null && !_uuid.hasMatch(token!)) {
      return const TrustsyError(TrustsyError.invalidLink, 'the token is not a UUID');
    }
    if (sealingKey.trim().isEmpty) {
      return const TrustsyError(TrustsyError.invalidSealingKey, 'no sealing key');
    }
    final t = terminal;
    if (t != null &&
        (t.terminalId.trim().isEmpty || t.chipKey.trim().isEmpty || t.chipKeyId < 0 || t.chipKeyId > 255)) {
      return const TrustsyError(TrustsyError.invalidChipKey, 'the terminal needs an id, a chip key and a key id of 0-255');
    }
    return null;
  }

  bool _usableOrigin(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty) return false;
    return uri.scheme == 'https' || (allowInsecure && uri.scheme == 'http');
  }

  /// The platform-channel shape both native plugins read.
  Map<String, Object?> toWire() => <String, Object?>{
        'link': link,
        'apiBaseUrl': apiBaseUrl,
        'token': token,
        'sealingKey': sealingKey,
        'language': language,
        'allowInsecure': allowInsecure,
        'terminal': terminal?.toWire(),
      };

  /// Never prints the token.
  @override
  String toString() => 'TrustsyVerifySession(${link != null ? 'link' : apiBaseUrl}, language: $language)';
}

/// This device is a partner terminal: a tablet or counter phone with a USB
/// smart card reader, reading the applicant's Thai ID card for the dip-chip
/// step (`sdk/contract/dip-chip.md`).
class TrustsyTerminal {
  const TrustsyTerminal({required this.terminalId, required this.chipKey, required this.chipKeyId});

  /// On your API key's `allowed_terminals`. Your backend must mint the
  /// applicant token WITH it; the server refuses a read for another terminal.
  final String terminalId;

  /// The server's chip key: base64 of 32 raw X25519 bytes. Pin it in your
  /// build config, like [TrustsyVerifySession.sealingKey] — a different key.
  final String chipKey;

  /// Its rotation epoch, 0–255.
  final int chipKeyId;

  Map<String, Object?> toWire() =>
      <String, Object?>{'terminalId': terminalId, 'chipKey': chipKey, 'chipKeyId': chipKeyId};
}
