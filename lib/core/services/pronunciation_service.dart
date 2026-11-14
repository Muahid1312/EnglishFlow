import 'package:flutter/services.dart';

class PronunciationService {
  static const _channel=MethodChannel('lexiflow/pronunciation');
  Future<Map<String,dynamic>> speak(String word) async {
    try {
      return Map<String,dynamic>.from(await _channel.invokeMethod<Map>('speak',{'text':word}).timeout(const Duration(seconds:30)) ?? {});
    } catch (_) { await stop(); rethrow; }
  }
  Future<void> stop() async {
    try { await _channel.invokeMethod<void>('stop'); } on PlatformException { /* Already stopped. */ }
      on MissingPluginException { /* No Android engine in this runtime. */ }
  }
}
