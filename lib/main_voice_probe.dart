// THROWAWAY DIAGNOSTIC HARNESS — delete when the voice bug is closed.
//
// Isolates the voice-search path from login, Supabase and the search stack, so
// the real VoiceSpeechService can be exercised on real web in two clicks. It
// reports every stage on screen AND to the console, which the app itself
// cannot do in a release web build (its diagnostics are behind kDebugMode).
//
// Run:  flutter run -d web-server --web-port=8081 -t lib/main_voice_probe.dart
import 'package:flutter/material.dart';

import 'services/voice/speech_service.dart';
import 'widgets/voice_listening_sheet.dart';

void main() => runApp(const _ProbeApp());

class _ProbeApp extends StatelessWidget {
  const _ProbeApp();
  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: _Probe(), debugShowCheckedModeBanner: false);
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final List<String> _log = [];

  void _say(String s) {
    // ignore: avoid_print
    print('[PROBE] $s');
    setState(() => _log.add(s));
  }

  Future<void> _stageProbe() async {
    final svc = VoiceSpeechService.current;
    _say('--- stage probe ---');
    _say('maybeAvailable = ${svc.maybeAvailable}');
    _say('ensureMicrophonePermission() = '
        '${await svc.ensureMicrophonePermission()}');
    final ready = await svc.initialize();
    _say('initialize() = $ready');
    _say('initFailure = ${svc.initFailure}');
    _say('isAvailable = ${svc.isAvailable}');
    _say('supportsBangla = ${svc.supportsBangla}');
    _say('banglaLocale = ${svc.banglaLocale?.localeId}');
    if (!ready) {
      _say('STOP: initialize() returned false — listen() would report '
          '${svc.initFailure ?? VoiceFailure.unsupported}');
      return;
    }
    final failure = await svc.listen(
      language: VoiceLanguage.auto,
      onResult: (t, f) => _say('onResult("$t", final=$f)'),
      onLevel: (l) {},
      onFailure: (f) => _say('onFailure($f)'),
      onDone: () => _say('onDone()'),
    );
    _say('listen() returned failure = $failure');
  }

  Future<void> _openSheet() async {
    _say('--- opening the real sheet ---');
    final q = await VoiceListeningSheet.show(context, remoteParser: null);
    _say(
        'sheet returned: ${q == null ? "null (backed out / failed)" : q.transcript}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40),
            SizedBox(
              height: 60,
              child: FilledButton(
                onPressed: _stageProbe,
                child:
                    const Text('STAGE PROBE', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 60,
              child: FilledButton(
                onPressed: _openSheet,
                child: const Text('OPEN SHEET', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                color: const Color(0xFF111111),
                padding: const EdgeInsets.all(10),
                child: ListView(
                  children: [
                    for (final l in _log)
                      Text(l,
                          style: const TextStyle(
                              color: Color(0xFF7CFC7C),
                              fontFamily: 'monospace',
                              fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
