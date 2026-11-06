import 'package:flutter/material.dart';
import 'package:trustsy_verify/trustsy_verify.dart';

/// The DEV api's key config (`backend/config/config.yaml`). A real app pins
/// its environment's key in its build config; it is never fetched at runtime.
const trustsySealingKey = 'AQAgAAEAAlftwPm3Tckm0oDXKB2LUpCcqfYNbSihX2L4bKTH6NB6';

void main() => runApp(const MaterialApp(title: 'trustsy Flutter', home: VerifyDemo()));

/// Paste an applicant link your backend minted; run it full screen or embedded.
class VerifyDemo extends StatefulWidget {
  const VerifyDemo({super.key});

  @override
  State<VerifyDemo> createState() => _VerifyDemoState();
}

class _VerifyDemoState extends State<VerifyDemo> {
  final _link = TextEditingController();
  String _result = '';

  TrustsyVerifySession _session() {
    final link = _link.text.trim();
    // A local dev api is plain http; a release build never allows it.
    return TrustsyVerifySession.fromLink(link, sealingKey: trustsySealingKey, allowInsecure: link.startsWith('http://'));
  }

  void _show(TrustsyResult result) => setState(() => _result = '$result');

  Future<void> _startFullScreen() async => _show(await TrustsyVerify.start(_session()));

  void _startEmbedded() {
    final session = _session();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Embedded')),
        body: TrustsyVerifyView(
          session: session,
          onResult: (result) {
            _show(result);
            Navigator.of(context).pop();
          },
        ),
      ),
    ));
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('trustsy Flutter')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _link,
                decoration: const InputDecoration(labelText: 'Applicant link'),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _startFullScreen, child: const Text('Start (full screen)')),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _startEmbedded, child: const Text('Embedded')),
              const SizedBox(height: 16),
              SelectableText(_result),
            ],
          ),
        ),
      );
}
