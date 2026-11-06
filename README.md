> This repository is exported from the trustsy monorepo, where the SDKs are built and
> tested together. `contract/` and `SDK-OVERVIEW.md` are copies shared by every trustsy SDK.

# trustsy_verify — Flutter

Runs a trustsy verification flow — the flow built once in the console, the same
one the web verify app runs — with the **native** screens of the Android
(`sdk/android`, Compose) and iOS (`sdk/ios`, SwiftUI) SDKs. No WebView. Every
call is end-to-end sealed to a key your app pins
([`sdk/contract/sealed-transport.md`](contract/sealed-transport.md)).

## Use

```dart
import 'package:trustsy_verify/trustsy_verify.dart';

// Your build config — PINNED, never fetched at runtime: a key fetched over an
// intercepted channel is the interceptor's key.
const trustsySealingKey = String.fromEnvironment('TRUSTSY_SEALING_KEY');

// link: from your backend (POST /api/v1/cases/{id}/collection-flow-url)
final session = TrustsyVerifySession.fromLink(link, sealingKey: trustsySealingKey);
// or: TrustsyVerifySession(apiBaseUrl: origin, token: tokenFromYourBackend, sealingKey: …, language: 'th')

// Full screen — the Android SDK's activity, iOS `TrustsyVerify.present`:
final result = await TrustsyVerify.start(session);

// Or embedded in your own layout (a platform view, sized by its parent):
TrustsyVerifyView(session: session, onResult: (result) { … });

switch (result) {
  case TrustsyCompleted(:final outcome): // approved | rejected | completed | failed | review
  case TrustsyCancelled():
  case TrustsyUnsupportedStep(:final screen): // send the applicant to the web link
  case TrustsyError(:final code): // see below
}
```

The result is for your UI. The decision of record reaches your backend by
webhook; never grant anything on this result alone.

## Public API

```dart
class TrustsyVerifySession {
  TrustsyVerifySession({required String apiBaseUrl, required String token,
      required String sealingKey, String? language, bool allowInsecure = false});
  TrustsyVerifySession.fromLink(String link,
      {required String sealingKey, String? language, bool allowInsecure = false});
  TrustsyError? validate();                // what start / the view would refuse up front
}

class TrustsyVerify {
  static Future<TrustsyResult> start(TrustsyVerifySession session); // never throws
}

class TrustsyVerifyView extends StatefulWidget {
  const TrustsyVerifyView({Key? key, required TrustsyVerifySession session,
      required ValueChanged<TrustsyResult> onResult});
}

sealed class TrustsyResult { static TrustsyResult fromWire(Object? wire); }
final class TrustsyCompleted extends TrustsyResult { final TrustsyOutcome outcome; }
final class TrustsyCancelled extends TrustsyResult {}
final class TrustsyUnsupportedStep extends TrustsyResult { final String screen; final String? state; }
final class TrustsyError extends TrustsyResult { final String code; final String message; }
enum TrustsyOutcome { approved, rejected, completed, failed, review }
```

- `language`: `en`, `th` or null (the link's, else the device's); anything else
  throws `ArgumentError`.
- `allowInsecure` accepts an `http://` origin, for a local dev api only — on both
  platforms (the plugin enforces it on iOS, where the SDK has no such flag).
- `TrustsyError.code`: the SDKs' `invalid_link`, `invalid_sealing_key`,
  `sealing_key_rejected` (the pinned key was rotated out — ship the new one),
  `sealed_response_invalid`, `clock_skew`, `unauthorized`, `network`
  ([`native-flow.md` §5](contract/native-flow.md)); and this plugin's
  `busy` (a full-screen run is already open), `no_host` (no activity / view
  controller to show it from), `host_unsupported` (not Android/iOS, or an
  embedded view on Android without a `ComponentActivity`).
- Link parsing and the key check belong to the native SDKs; Dart refuses only a
  non-https origin, a non-UUID token and an empty key.
- An unreadable or unknown result from the platform reads as
  `TrustsyCancelled` — never as a pass.
- `TrustsyVerifyView` calls `onResult` once. The session is read once: give the
  widget a new `Key` to run another. Removing the widget before the flow ends
  delivers nothing.

## App requirements

### Android

- `minSdk 24`. The SDK's manifest adds `INTERNET`, `CAMERA`, location and `NFC`.
- The native SDK (`com.trustsy:trustsy-verify:0.2.0`) is not on a public
  repository; the plugin adds the repository it comes from to your app's
  projects itself (for the `com.trustsy` group only). Point it at the
  repository `sdk/android` publishes
  ([Distribute](https://github.com/trustsy/trustsy-android#distribute)) in `android/gradle.properties`:

  ```properties
  # https://… where you host it, or a path relative to android/
  trustsyVerifyAndroidRepository=https://<where you host it>
  ```

  Without the property it reads **mavenLocal** — on the machine that ran
  `./gradlew :trustsy-verify:publishToMavenLocal` in `sdk/android`. With it,
  mavenLocal is not consulted, so a stale local copy cannot stand in.
- Bouncy Castle ships one license file twice. In `android/app/build.gradle.kts`:

  ```kotlin
  android { packaging { resources { excludes += setOf("META-INF/LICENSE.md", "META-INF/versions/9/OSGI-INF/MANIFEST.MF") } } }
  ```
- **Embedded view only**: `MainActivity` must extend `FlutterFragmentActivity`
  (a `ComponentActivity` — the flow requests permissions and turns on NFC reader
  mode through it). Under a plain `FlutterActivity` the view ends with
  `host_unsupported`; full-screen `start` works under either. The view is a
  hybrid-composition platform view, so the camera previews render.
- The plugin does not compile Compose: it instantiates the SDK's
  `TrustsyVerifyView` (a classic `View`), so your app needs no Compose compiler.

### iOS

- iOS 17. In the `Podfile`: `platform :ios, '17.0'` and, until the pod is
  published, `pod 'TrustsyVerify', :path => '<repo>/sdk/ios'`.
- `Info.plist`: `NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`,
  `NFCReaderUsageDescription`, and
  `com.apple.developer.nfc.readersession.iso7816.select-identifiers` =
  `[A0000002471001]`. Entitlement `com.apple.developer.nfc.readersession.formats`
  = `[TAG]` (needs a paid team). See [`sdk/ios/README.md`](https://github.com/trustsy/trustsy-ios#readme).
- The embedded view adds the SDK's `TrustsyVerifyViewController` as a child of
  the view controller that owns the Flutter view, and keeps it there until
  Flutter disposes the platform view (not when another route covers it).

## Example

`example/` is **trustsy Flutter**: paste an applicant link, then *Start (full
screen)* or *Embedded*. It pins the DEV api's key config; an `http://` link
turns on `allowInsecure`.

```sh
cd sdk/flutter/trustsy_verify
flutter analyze && flutter test
cd example
flutter build apk --debug                       # after publishToMavenLocal
ORG_GRADLE_PROJECT_trustsyVerifyAndroidRepository=../../../../android/build/repository \
  flutter build apk --release                   # from the published repository, R8 on
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build ios --release --no-codesign
```

Licensing: JMRTD / scuba (Android NFC) are **LGPL-3.0** — see
[`sdk/android/README.md`](https://github.com/trustsy/trustsy-android#readme) before shipping.
