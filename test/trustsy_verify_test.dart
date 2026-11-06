import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustsy_verify/src/flow_view_link.dart';
import 'package:trustsy_verify/trustsy_verify.dart';

const _key = 'AQAgAAEAAlftwPm3Tckm0oDXKB2LUpCcqfYNbSihX2L4bKTH6NB6';
const _token = 'ceb76355-da07-470e-901d-40dc8ed20b85';
const _link = 'https://verify.example.com/u/zrdjVdoHRw6QHUDcjtILhQ';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('setPushToken hands the token to the native SDK, and is a no-op without a plugin', () async {
    const channel = MethodChannel('com.trustsy.verify');
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    await TrustsyVerify.setPushToken('fcmToken:APA91bH-0123456789');
    await TrustsyVerify.setPushToken(null);
    expect(calls.map((c) => c.method), ['setPushToken', 'setPushToken']);
    expect(calls.map((c) => c.arguments), ['fcmToken:APA91bH-0123456789', null]);
    messenger.setMockMethodCallHandler(channel, null);
    await TrustsyVerify.setPushToken('fcmToken:APA91bH-0123456789');
  });

  group('TrustsyResult.fromWire', () {
    test('every outcome the contract names', () {
      for (final outcome in TrustsyOutcome.values) {
        expect(
          TrustsyResult.fromWire({'kind': 'completed', 'outcome': outcome.name}),
          TrustsyCompleted(outcome),
        );
      }
    });

    test('an outcome this version does not know is a cancellation, never a pass', () {
      expect(TrustsyResult.fromWire({'kind': 'completed', 'outcome': 'approved_v2'}), const TrustsyCancelled());
      expect(TrustsyResult.fromWire({'kind': 'completed'}), const TrustsyCancelled());
    });

    test('unreadable data is a cancellation', () {
      expect(TrustsyResult.fromWire(null), const TrustsyCancelled());
      expect(TrustsyResult.fromWire('approved'), const TrustsyCancelled());
      expect(TrustsyResult.fromWire({'outcome': 'approved'}), const TrustsyCancelled());
      expect(TrustsyResult.fromWire({'kind': 'something_new'}), const TrustsyCancelled());
      expect(TrustsyResult.fromWire({'kind': 'cancelled'}), const TrustsyCancelled());
    });

    test('unsupported steps keep screen and state', () {
      expect(
        TrustsyResult.fromWire({'kind': 'unsupported_step', 'screen': 'signature', 'state': 'awaiting_signature'}),
        const TrustsyUnsupportedStep('signature', 'awaiting_signature'),
      );
      expect(
        TrustsyResult.fromWire({'kind': 'unsupported_step', 'screen': 'company', 'state': null}),
        const TrustsyUnsupportedStep('company', null),
      );
    });

    test('errors keep code and message; a missing code reads as network', () {
      expect(
        TrustsyResult.fromWire({'kind': 'error', 'code': 'clock_skew', 'message': 'off by 9 min'}),
        const TrustsyError(TrustsyError.clockSkew, 'off by 9 min'),
      );
      expect(TrustsyResult.fromWire({'kind': 'error'}), const TrustsyError(TrustsyError.network, ''));
    });
  });

  group('TrustsyVerifySession.validate', () {
    test('an https link and an https origin with a UUID token pass', () {
      expect(TrustsyVerifySession.fromLink(_link, sealingKey: _key).validate(), isNull);
      expect(
        TrustsyVerifySession(apiBaseUrl: 'https://api.example.com', token: _token, sealingKey: _key).validate(),
        isNull,
      );
    });

    test('http only with allowInsecure', () {
      const dev = 'http://10.0.2.2:8096/u/zrdjVdoHRw6QHUDcjtILhQ';
      expect(TrustsyVerifySession.fromLink(dev, sealingKey: _key).validate()?.code, TrustsyError.invalidLink);
      expect(TrustsyVerifySession.fromLink(dev, sealingKey: _key, allowInsecure: true).validate(), isNull);
    });

    test('not a link at all', () {
      for (final link in ['', 'verify.example.com/u/x', 'ftp://verify.example.com/u/x', 'https://']) {
        expect(TrustsyVerifySession.fromLink(link, sealingKey: _key).validate()?.code, TrustsyError.invalidLink,
            reason: link);
      }
    });

    test('a token that is not a UUID', () {
      final session = TrustsyVerifySession(apiBaseUrl: 'https://api.example.com', token: 'abc', sealingKey: _key);
      expect(session.validate()?.code, TrustsyError.invalidLink);
    });

    test('a terminal travels to the plugins as its three fields', () {
      const terminal = TrustsyTerminal(terminalId: 'BRANCH-042', chipKey: '02ky9U23ZJiDQY3V085oMBtQ64GU7i7cPfSvc1KRxTc=', chipKeyId: 1);
      final session = TrustsyVerifySession.fromLink(_link, sealingKey: _key, terminal: terminal);
      expect(session.validate(), isNull);
      expect(session.toWire()['terminal'],
          {'terminalId': 'BRANCH-042', 'chipKey': '02ky9U23ZJiDQY3V085oMBtQ64GU7i7cPfSvc1KRxTc=', 'chipKeyId': 1});
      expect(TrustsyVerifySession.fromLink(_link, sealingKey: _key).toWire()['terminal'], isNull);
    });

    test('a terminal without an id, a key or a 0-255 key id is invalid_chip_key', () {
      for (final t in const [
        TrustsyTerminal(terminalId: ' ', chipKey: 'k', chipKeyId: 1),
        TrustsyTerminal(terminalId: 'T', chipKey: '', chipKeyId: 1),
        TrustsyTerminal(terminalId: 'T', chipKey: 'k', chipKeyId: 256),
        TrustsyTerminal(terminalId: 'T', chipKey: 'k', chipKeyId: -1),
      ]) {
        expect(TrustsyVerifySession.fromLink(_link, sealingKey: _key, terminal: t).validate()?.code,
            TrustsyError.invalidChipKey);
      }
    });

    test('no sealing key', () {
      expect(TrustsyVerifySession.fromLink(_link, sealingKey: ' ').validate()?.code, TrustsyError.invalidSealingKey);
    });

    test('only en, th or null', () {
      expect(() => TrustsyVerifySession.fromLink(_link, sealingKey: _key, language: 'fr'), throwsArgumentError);
      expect(TrustsyVerifySession.fromLink(_link, sealingKey: _key, language: 'th').language, 'th');
    });

    test('toString never prints the token or the link', () {
      final text = '${TrustsyVerifySession.fromLink(_link, sealingKey: _key)}'
          '${TrustsyVerifySession(apiBaseUrl: 'https://api.example.com', token: _token, sealingKey: _key)}';
      expect(text, isNot(contains(_token)));
      expect(text, isNot(contains('zrdjVdoHRw6QHUDcjtILhQ')));
    });
  });

  group('TrustsyVerify.start', () {
    const channel = MethodChannel('com.trustsy.verify');
    final calls = <MethodCall>[];

    tearDown(() {
      calls.clear();
      messenger.setMockMethodCallHandler(channel, null);
    });

    void answer(Future<Object?> Function(MethodCall) reply) {
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return reply(call);
      });
    }

    test('sends the session and decodes the native result', () async {
      answer((_) async => {'kind': 'completed', 'outcome': 'review'});
      final session = TrustsyVerifySession.fromLink(_link, sealingKey: _key, language: 'th');
      expect(await TrustsyVerify.start(session), const TrustsyCompleted(TrustsyOutcome.review));
      expect(calls.single.method, 'start');
      expect(calls.single.arguments, {
        'link': _link,
        'apiBaseUrl': null,
        'token': null,
        'sealingKey': _key,
        'language': 'th',
        'allowInsecure': false,
        'terminal': null,
      });
    });

    test('a session refused in Dart never reaches the platform', () async {
      answer((_) async => {'kind': 'completed', 'outcome': 'approved'});
      final result = await TrustsyVerify.start(TrustsyVerifySession.fromLink('http://x.test/u/y', sealingKey: _key));
      expect(result, isA<TrustsyError>().having((e) => e.code, 'code', TrustsyError.invalidLink));
      expect(calls, isEmpty);
    });

    test('a platform exception becomes an error result', () async {
      answer((_) async => throw PlatformException(code: 'busy', message: 'already running'));
      expect(
        await TrustsyVerify.start(TrustsyVerifySession.fromLink(_link, sealingKey: _key)),
        const TrustsyError('busy', 'already running'),
      );
    });

    test('no native plugin (another platform) is host_unsupported', () async {
      final result = await TrustsyVerify.start(TrustsyVerifySession.fromLink(_link, sealingKey: _key));
      expect(result, isA<TrustsyError>().having((e) => e.code, 'code', TrustsyError.hostUnsupported));
    });
  });

  group('FlowViewLink', () {
    const channel = MethodChannel('com.trustsy.verify/flow_7');
    final calls = <String>[];

    tearDown(() {
      calls.clear();
      messenger.setMockMethodCallHandler(channel, null);
    });

    Future<void> nativeSends(Object? result) => messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall('result', result)),
          (_) {},
        );

    test('asks the native view to start, then delivers exactly one result', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      final delivered = <TrustsyResult>[];
      FlowViewLink(7, delivered.add);
      await pumpEventQueue();
      expect(calls, ['start']);

      await nativeSends({'kind': 'completed', 'outcome': 'approved'});
      await nativeSends({'kind': 'cancelled'});
      expect(delivered, [const TrustsyCompleted(TrustsyOutcome.approved)]);
    });

    test('nothing is delivered after close', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      final delivered = <TrustsyResult>[];
      FlowViewLink(7, delivered.add).close();
      await nativeSends({'kind': 'completed', 'outcome': 'approved'});
      expect(delivered, isEmpty);
    });

    test('a native view that never answers start ends as host_unsupported', () async {
      final delivered = <TrustsyResult>[];
      FlowViewLink(7, delivered.add);
      await pumpEventQueue();
      expect(delivered.single, isA<TrustsyError>().having((e) => e.code, 'code', TrustsyError.hostUnsupported));
    });
  });
}
